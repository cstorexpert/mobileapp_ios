import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:countx/config/config.dart';
import 'package:countx/models/fusion_result.dart';
import 'package:countx/models/identification_result.dart';
import 'package:countx/screens/transactions.dart' show StockItem, ScannedItem;
import 'package:countx/services/product_identification_service.dart';
import 'package:countx/utils/camera_mlkit_input_image.dart';
import 'package:countx/utils/fusion_frame_crop.dart';
import 'package:countx/utils/scan_code_utils.dart';
import 'package:countx/utils/stock_name_matcher.dart';

typedef LiveScanAddCallback = Future<bool> Function(
  StockItem stockItem,
  ScannedItem scannedItem,
);

enum _LockPhase { ready, locking, locked }

enum _UnknownSheetPhase {
  /// Warning + Add to sheet / Skip.
  prompt,
  /// Mini form to inject into [previousStock] in memory.
  miniForm,
}

/// Live scan using the device camera + on-device ML Kit: object gate, barcode
/// decode, then OCR + fuzzy name match on the label when no barcode is read
/// (e.g. bottle facing camera without a visible code).
///
/// Phase 2 visual: LAN MobileCLIP runs only when the user taps ✨ (fusion).
/// Normal Live Scan stays barcode → OCR. CLIP never overrides a barcode hit.
///
/// Not-in-sheet flow: user can inject a row into [previousStock] and add with
/// `__source: manual` so it appears in the missing-items report.
class LiveScanScreen extends StatefulWidget {
  const LiveScanScreen({
    super.key,
    required this.previousStock,
    required this.sectionName,
    required this.allocatedDepartment,
    required this.onAdd,
    this.onPreviousStockChanged,
  });

  final Map<String, StockItem> previousStock;
  final String sectionName;
  final String allocatedDepartment;
  final LiveScanAddCallback onAdd;
  /// Called after a row is added to [previousStock] in memory (parent may refresh UI).
  final VoidCallback? onPreviousStockChanged;

  @override
  State<LiveScanScreen> createState() => _LiveScanScreenState();
}

class _LiveScanScreenState extends State<LiveScanScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color _navy = Color.fromARGB(255, 3, 25, 55);
  static const Duration _idleHideDelay = Duration(milliseconds: 2500);
  static const int _stableFramesNeeded = 2;
  /// Lower = snappier pipeline (barcode + object + OCR feel more “live”).
  static const Duration _minVisionInterval = Duration(milliseconds: 165);

  final BarcodeScanner _barcodeScanner =
      BarcodeScanner(formats: const [BarcodeFormat.all]);
  late final ObjectDetector _objectDetector;
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _cameraInitFailed = false;
  bool _torchOn = false;

  bool _processingVision = false;
  DateTime _lastVisionAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _visionTick = 0;

  bool _objectInFrame = false;

  StockItem? _currentProduct;
  String? _detectedCode;
  bool _isUnknownProduct = false;
  String? _ocrNoMatchSnippet;

  int _manualCount = 1;
  bool _isAdding = false;

  String? _lastBarcode;
  Timer? _hideTimer;
  late final AnimationController _framingPulse;

  final TextEditingController _qtyController = TextEditingController(text: '1');
  final TextEditingController _injectNameController = TextEditingController();
  final TextEditingController _injectDeptController = TextEditingController();
  final TextEditingController _injectRateController = TextEditingController();

  _LockPhase _lockPhase = _LockPhase.ready;
  _UnknownSheetPhase _unknownPhase = _UnknownSheetPhase.prompt;
  /// `manual` after user injects an unknown barcode into the sheet; else `scanner`.
  String _scannedItemSource = 'scanner';
  String? _pendingCode;
  int _stableFrameCount = 0;
  bool _framingPulseWasActive = false;

  /// Phase 2: ✨-triggered LAN MobileCLIP (never auto-runs in the camera loop).
  final ProductIdentificationService _productId =
      ProductIdentificationService();
  bool _fusionBusy = false;
  FusionResult? _fusionDebugResult;
  List<VisualCandidate>? _visualPickerCandidates;

  /// True while the quantity / unknown / visual-picker overlay is active.
  bool get _isInputting =>
      _visualPickerCandidates != null ||
      (_lockPhase == _LockPhase.locked &&
          (_currentProduct != null || _isUnknownProduct));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _objectDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        // Per-frame stills behave more reliably than stream mode on some OEM stacks.
        mode: DetectionMode.single,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
    _framingPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    unawaited(_initCamera());
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraInitFailed = true);
        return;
      }
      _cameraIndex = 0;
      for (var i = 0; i < _cameras.length; i++) {
        if (_cameras[i].lensDirection == CameraLensDirection.back) {
          _cameraIndex = i;
          break;
        }
      }
      await _openCameraAt(_cameraIndex);
    } catch (_) {
      if (mounted) setState(() => _cameraInitFailed = true);
    }
  }

  Future<void> _openCameraAt(int index) async {
    final old = _cameraController;
    if (old != null) {
      try {
        await old.stopImageStream();
      } catch (_) {}
      await old.dispose();
    }
    _cameraController = null;

    if (_cameras.isEmpty) return;

    final cam = _cameras[index % _cameras.length];
    final controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          defaultTargetPlatform == TargetPlatform.android
              ? ImageFormatGroup.nv21
              : ImageFormatGroup.bgra8888,
    );

    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }

    _cameraController = controller;
    if (mounted) setState(() {});

    await controller.startImageStream(_onCameraImage);
  }

  @override
  void dispose() {
    _framingPulse.dispose();
    _qtyController.dispose();
    _injectNameController.dispose();
    _injectDeptController.dispose();
    _injectRateController.dispose();
    _hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    unawaited(_barcodeScanner.close());
    unawaited(_objectDetector.close());
    unawaited(_textRecognizer.close());
    super.dispose();
  }

  Future<void> _disposeCamera() async {
    final c = _cameraController;
    _cameraController = null;
    if (c == null) return;
    try {
      await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_pauseStream());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_resumeStream());
    }
  }

  Future<void> _pauseStream() async {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.stopImageStream();
    } catch (_) {}
  }

  Future<void> _resumeStream() async {
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.startImageStream(_onCameraImage);
    } catch (_) {}
  }

  void _onCameraImage(CameraImage image) {
    unawaited(_processCameraImage(image));
  }

  /// ✨ button: capture still → LAN MobileCLIP → top-k / product card.
  /// Does not replace barcode/OCR during normal scanning; never auto-adds.
  Future<void> _runFusionIdentify() async {
    if (_fusionBusy) return;
    if (AppConfig.fusionBaseUrl.isEmpty) {
      _showFusionSnack('fusionBaseUrl is empty in config.dart');
      return;
    }
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      _showFusionSnack('Camera not ready');
      return;
    }

    setState(() {
      _fusionBusy = true;
      _fusionDebugResult = null;
      _visualPickerCandidates = null;
    });

    try {
      try {
        await controller.stopImageStream();
      } catch (_) {}

      final XFile shot = await controller.takePicture();
      final fullBytes = await File(shot.path).readAsBytes();
      final crop = centerCropBottleJpeg(fullBytes);
      if (crop == null) {
        _showFusionSnack('Could not crop frame for fusion');
        return;
      }

      final result = await _productId.identifyFromCrop(
        jpegBytes: crop.jpegBytes,
        width: crop.width,
        height: crop.height,
        previousStock: widget.previousStock,
      );

      if (!mounted) return;

      if (!result.hasVisualClaim) {
        final raw = result.raw;
        if (raw != null && !raw.isSuccess) {
          setState(() => _fusionDebugResult = raw);
          _showFusionSnack(raw.message ?? 'Fusion failed');
        } else {
          _showFusionSnack(
            result.message ??
                'No confident visual match. Try framing the product clearly.',
          );
        }
        return;
      }

      if (result.band == VisualConfidenceBand.high &&
          result.scanCode != null &&
          result.scanCode!.isNotEmpty) {
        debugPrint(
          '[LiveScan] ✨ HIGH → ${result.scanCode} '
          '(${result.candidates.first.score.toStringAsFixed(3)})',
        );
        _handleCodeRead(
          result.scanCode!,
          sourceBarcode: false,
          itemSource: 'visual',
        );
        return;
      }

      final picks = result.candidates.take(3).toList();
      debugPrint(
        '[LiveScan] ✨ MEDIUM → picker ${picks.length} '
        'top=${picks.first.scanCode} ${picks.first.score.toStringAsFixed(3)}',
      );
      setState(() => _visualPickerCandidates = picks);
    } catch (e) {
      debugPrint('[LiveScan] ✨ fusion error: $e');
      if (mounted) {
        setState(() => _fusionDebugResult = FusionResult.error(e.toString()));
        _showFusionSnack(
          'Fusion failed. Is the sandbox running at ${AppConfig.fusionBaseUrl}?',
        );
      }
    } finally {
      try {
        if (_cameraController != null &&
            _cameraController!.value.isInitialized &&
            !_cameraController!.value.isStreamingImages) {
          await _cameraController!.startImageStream(_onCameraImage);
        }
      } catch (e) {
        debugPrint('[LiveScan] resume stream after fusion: $e');
      }
      if (mounted) setState(() => _fusionBusy = false);
    }
  }

  void _showFusionSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _dismissFusionResult() {
    if (!mounted) return;
    setState(() => _fusionDebugResult = null);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    // Traditional Live Scan: barcode → OCR only.
    // Pause while ✨ fusion is running, debug overlay is open, or qty/unknown
    // card is locked. Visual picker (from ✨) stays open to camera so barcode
    // can still win.
    final lockedOnCard = _lockPhase == _LockPhase.locked &&
        (_currentProduct != null || _isUnknownProduct);
    if (!mounted ||
        _processingVision ||
        lockedOnCard ||
        _fusionBusy ||
        _fusionDebugResult != null) {
      return;
    }
    final pickerOpen = _visualPickerCandidates != null;
    final now = DateTime.now();
    if (now.difference(_lastVisionAt) < _minVisionInterval) return;

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    final input = cameraImageToInputImage(image, controller);
    if (input == null) {
      debugPrint('[LiveScan] InputImage null — planes=${image.planes.length} '
          'fmt=${image.format.group} ${image.width}x${image.height}');
      return;
    }

    _processingVision = true;
    _lastVisionAt = now;
    _visionTick++;

    try {
      final barcodeFuture = _barcodeScanner.processImage(input);
      final objectFuture = _objectDetector.processImage(input);
      final barcodes = await barcodeFuture;
      final bc = _pickMlKitBarcode(barcodes);
      final raw = bc?.rawValue?.trim();

      // Start OCR as soon as we know there is no barcode, while object finishes.
      final Future<RecognizedText>? ocrFuture =
          (raw == null || raw.isEmpty) && !pickerOpen
              ? _textRecognizer.processImage(input)
              : null;

      final objects = await objectFuture;

      final hasObject = _objectGate(objects, image.width, image.height);

      if (_visionTick <= 5 || _visionTick % 20 == 0) {
        debugPrint('[LiveScan] tick=$_visionTick objects=${objects.length} '
            'objGate=$hasObject barcodes=${barcodes.length} raw=$raw');
      }

      if (mounted) {
        setState(() {
          _objectInFrame = hasObject || (raw != null && raw.isNotEmpty);
        });
      }

      if (raw != null && raw.isNotEmpty) {
        if (pickerOpen && mounted) {
          setState(() => _visualPickerCandidates = null);
        }
        _handleCodeRead(raw, sourceBarcode: true);
        return;
      }

      // Keep ✨ top-k until user picks/dismisses; no CLIP in the camera loop.
      if (pickerOpen || ocrFuture == null) return;

      final recognized = await ocrFuture;
      final text = recognized.text.trim();
      if (text.length < 4) return;

      if (mounted) {
        setState(() => _objectInFrame = true);
      }

      debugPrint('[LiveScan] OCR text (${text.length} chars): '
          '${text.length > 80 ? '${text.substring(0, 80)}…' : text}');

      final match = fuzzyFindStockByLabelText(text, widget.previousStock);
      if (match != null) {
        final code = match.scanCode ?? '';
        debugPrint('[LiveScan] OCR matched: ${match.name} code=$code');
        if (code.isEmpty) return;
        if (mounted) {
          setState(() => _ocrNoMatchSnippet = null);
        }
        _handleCodeRead(code, sourceBarcode: false);
      } else if (mounted) {
        setState(() {
          _ocrNoMatchSnippet = text.length > 120
              ? '${text.substring(0, 120)}…'
              : text;
        });
      }
    } catch (e) {
      debugPrint('[LiveScan] frame error: $e');
    } finally {
      _processingVision = false;
    }
  }

  void _dismissVisualPicker() {
    if (!mounted) return;
    setState(() => _visualPickerCandidates = null);
  }

  void _onVisualCandidatePicked(VisualCandidate c) {
    final code = c.scanCode;
    if (code.isEmpty) return;
    setState(() => _visualPickerCandidates = null);
    _handleCodeRead(code, sourceBarcode: false, itemSource: 'visual');
  }

  /// Optional visual hint only (barcode/OCR are **not** gated on this).
  bool _objectGate(List<DetectedObject> objects, int w, int h) {
    if (objects.isEmpty) return false;
    final imgArea = (w * h).toDouble();
    if (imgArea <= 0) return false;

    for (final o in objects) {
      final area = o.boundingBox.width * o.boundingBox.height;
      if (area >= imgArea * 0.004) return true;
    }
    return false;
  }

  Barcode? _pickMlKitBarcode(List<Barcode> list) {
    Barcode? best;
    var bestArea = 0.0;
    for (final b in list) {
      final v = b.rawValue;
      if (v == null || v.trim().isEmpty) continue;
      final r = b.boundingBox;
      final a = r.width * r.height;
      if (a >= bestArea) {
        bestArea = a;
        best = b;
      }
    }
    return best;
  }

  void _handleCodeRead(
    String rawCode, {
    required bool sourceBarcode,
    String itemSource = 'scanner',
  }) {
    // Allow locking a product while the visual picker is open (user just picked).
    final pickerOpen = _visualPickerCandidates != null;
    if (!mounted) return;
    if (_isInputting && !pickerOpen) return;

    final code = normalizeScanCode(rawCode);
    if (code.isEmpty) return;

    if (_lockPhase == _LockPhase.locked && _lastBarcode == code) {
      return;
    }

    // Visual picks: skip multi-frame stability (user picked, or high-band claim).
    // Barcode + OCR keep the existing hold-steady lock.
    final skipStability = itemSource == 'visual' || pickerOpen;

    if (!skipStability) {
      if (_pendingCode != code) {
        _pendingCode = code;
        _stableFrameCount = 1;
        setState(() {
          _lockPhase = _LockPhase.locking;
          if (!sourceBarcode) {
            _ocrNoMatchSnippet = null;
          }
        });
        _resetHideTimer();
        return;
      }

      _stableFrameCount++;

      if (_stableFrameCount < _stableFramesNeeded) {
        if (_lockPhase == _LockPhase.locking) {
          setState(() {});
        }
        _resetHideTimer();
        return;
      }
    }

    _lastBarcode = code;
    _lockPhase = _LockPhase.locked;
    _hideTimer?.cancel();
    _hideTimer = null;
    _pendingCode = code;
    _stableFrameCount = _stableFramesNeeded;

    final found = lookupStockByScanCode(widget.previousStock, code);

    // CLIP must not invent unknown Excel rows — only barcode may open unknown.
    if (found == null && !sourceBarcode && itemSource == 'visual') {
      debugPrint('[LiveScan] visual code not in sheet: $code — ignored');
      setState(() {
        _visualPickerCandidates = null;
        _lockPhase = _LockPhase.ready;
        _lastBarcode = null;
        _pendingCode = null;
        _stableFrameCount = 0;
      });
      return;
    }

    setState(() {
      _visualPickerCandidates = null;
      _detectedCode = code;
      _ocrNoMatchSnippet = null;
      if (found != null) {
        _scannedItemSource = itemSource;
        _unknownPhase = _UnknownSheetPhase.prompt;
        if (_currentProduct?.scanCode != found.scanCode) {
          _manualCount = 1;
        }
        _currentProduct = found;
        _isUnknownProduct = false;
      } else {
        _currentProduct = null;
        _isUnknownProduct = true;
        _unknownPhase = _UnknownSheetPhase.prompt;
        _scannedItemSource = itemSource;
      }
    });

    _syncQtyFieldFromState();
  }

  void _syncQtyFieldFromState() {
    final t = _manualCount.toString();
    if (_qtyController.text != t) {
      _qtyController.value = TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      );
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
    // Never auto-dismiss while the user is entering quantity or unknown flow.
    if (_isInputting) return;
    if (_currentProduct != null || _isUnknownProduct) return;
    _hideTimer = Timer(_idleHideDelay, () {
      if (!mounted || _isInputting) return;
      _clearScanUiForNextItem(resetManualQty: false);
    });
  }

  /// Clears lock/card state. After a successful [Add], reset qty for the next item.
  void _clearScanUiForNextItem({required bool resetManualQty}) {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _currentProduct = null;
      _isUnknownProduct = false;
      _unknownPhase = _UnknownSheetPhase.prompt;
      _scannedItemSource = 'scanner';
      _detectedCode = null;
      _lastBarcode = null;
      _lockPhase = _LockPhase.ready;
      _pendingCode = null;
      _stableFrameCount = 0;
      _ocrNoMatchSnippet = null;
      _visualPickerCandidates = null;
      if (resetManualQty) {
        _manualCount = 1;
        _syncQtyFieldFromState();
      }
    });
  }

  void _incrementCount() {
    HapticFeedback.lightImpact();
    setState(() => _manualCount++);
    _syncQtyFieldFromState();
    _resetHideTimer();
  }

  void _decrementCount() {
    if (_manualCount <= 1) return;
    HapticFeedback.lightImpact();
    setState(() => _manualCount--);
    _syncQtyFieldFromState();
    _resetHideTimer();
  }

  Future<void> _onAddPressed() async {
    final product = _currentProduct;
    if (product == null || _isAdding) return;
    setState(() => _isAdding = true);

    final scanCode = product.scanCode ?? _detectedCode ?? '';
    final department = product.department.isNotEmpty
        ? product.department
        : widget.allocatedDepartment;

    final stockItem = StockItem(
      scanCode: scanCode,
      code: product.code,
      name: product.name,
      department: department,
      rate: product.rate,
      quantity: _manualCount,
    );
    final scannedItem = ScannedItem(
      code: product.code,
      department: department,
      name: product.name,
      qty: _manualCount.toString(),
      rate: product.rate,
      source: _scannedItemSource,
      scanCode: scanCode,
    );

    var ok = false;
    try {
      ok = await widget.onAdd(stockItem, scannedItem);
    } catch (_) {
      ok = false;
    }

    if (!mounted) return;
    setState(() => _isAdding = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to add. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${product.name} × $_manualCount'),
        duration: const Duration(milliseconds: 900),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    _clearScanUiForNextItem(resetManualQty: true);
  }

  Widget _buildCameraPreview(CameraController controller) {
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return Center(child: CameraPreview(controller));
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  /// Fixed framing guide on screen — not derived from ML bounding boxes.
  /// Tall-rectangle ratio fits a typical bottle/label; area outside is dimmed.
  Rect _bottleFramingGuideRect(MediaQueryData mq) {
    final size = mq.size;
    final pad = mq.padding;
    final availH =
        (size.height - pad.top - pad.bottom).clamp(1.0, double.infinity);
    final maxW = size.width * 0.70;
    final maxH = availH * 0.58;
    const aspectHPerW = 1.52;
    var w = maxW;
    var h = w * aspectHPerW;
    if (h > maxH) {
      h = maxH;
      w = h / aspectHPerW;
    }
    final center = Offset(
      size.width * 0.5,
      pad.top + availH * 0.44,
    );
    return Rect.fromCenter(center: center, width: w, height: h);
  }

  /// Border / pulse for the fixed frame (replaces old ML bounding-box colors).
  ({Color border, double pulseT, double borderWidth}) _framingStyleForPhase({
    required bool needPlacementHint,
    double animatedPulse = 0,
  }) {
    switch (_lockPhase) {
      case _LockPhase.locked:
        return (
          border: const Color(0xFF69F0AE),
          pulseT: 0,
          borderWidth: 3,
        );
      case _LockPhase.locking:
        return (
          border: const Color(0xFFFFCA28),
          pulseT: 0,
          borderWidth: 3,
        );
      case _LockPhase.ready:
        if (needPlacementHint) {
          return (
            border: const Color(0xFFFF5252),
            pulseT: animatedPulse,
            borderWidth: 3,
          );
        }
        return (
          border: Colors.white.withValues(alpha: 0.9),
          pulseT: 0,
          borderWidth: 2.5,
        );
    }
  }

  Widget _buildFramingLayer(Rect guideRect, ({Color border, double pulseT, double borderWidth}) style) {
    final painter = _FramingGuidePainter(
      scanWindow: guideRect,
      borderColor: style.border,
      borderWidth: style.borderWidth,
      borderRadius: BorderRadius.circular(20),
      scrimOutside: Colors.black.withValues(alpha: 0.66),
      pulseT: style.pulseT,
    );
    return IgnorePointer(
      child: CustomPaint(painter: painter),
    );
  }

  String get _lockPhaseSubtitle {
    switch (_lockPhase) {
      case _LockPhase.ready:
        return 'barcode or label';
      case _LockPhase.locking:
        return 'hold steady…';
      case _LockPhase.locked:
        return 'locked';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraInitFailed) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Live Scan'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Camera could not be started. Check permission and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    final controller = _cameraController;
    final hasCard = _currentProduct != null ||
        _isUnknownProduct ||
        _visualPickerCandidates != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Builder(
        builder: (context) {
          if (controller == null || !controller.value.isInitialized) {
            return const ColoredBox(
              color: Colors.black,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),
            );
          }

          final mq = MediaQuery.of(context);
          final guideRect = _bottleFramingGuideRect(mq);
          final needPlacementHint =
              _lockPhase == _LockPhase.ready && !hasCard && !_objectInFrame;
          if (needPlacementHint != _framingPulseWasActive) {
            final startPulse = needPlacementHint;
            _framingPulseWasActive = needPlacementHint;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (startPulse) {
                _framingPulse.repeat(reverse: true);
              } else {
                _framingPulse
                  ..stop()
                  ..reset();
              }
            });
          }

          final framingLayer = needPlacementHint
              ? AnimatedBuilder(
                  animation: _framingPulse,
                  builder: (_, _) => _buildFramingLayer(
                    guideRect,
                    _framingStyleForPhase(
                      needPlacementHint: true,
                      animatedPulse: _framingPulse.value,
                    ),
                  ),
                )
              : _buildFramingLayer(
                  guideRect,
                  _framingStyleForPhase(needPlacementHint: false),
                );

          return Stack(
            fit: StackFit.expand,
            children: [
              _buildCameraPreview(controller),
              Positioned.fill(child: framingLayer),
              // Subtle edge vignette — heavy dim is on the framing overlay.
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.28),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.22),
                        ],
                        stops: const [0, 0.14, 0.64, 1],
                      ),
                    ),
                  ),
                ),
              ),
              _buildTopBar(context),
              if (_fusionBusy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'Running visual match…',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_fusionDebugResult != null)
                Positioned.fill(
                  child: _buildFusionResultOverlay(_fusionDebugResult!),
                ),
              if (needPlacementHint)
                Positioned(
                  left: 12,
                  right: 12,
                  top: mq.padding.top + 52,
                  child: IgnorePointer(
                    child: Material(
                      color: Colors.red.shade900.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.center_focus_strong,
                              color: Colors.red.shade100,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Place the bottle or label fully inside the frame',
                                style: TextStyle(
                                  color: Colors.red.shade50,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 1),
                        end: Offset.zero,
                      ).animate(anim),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: hasCard
                        ? (_visualPickerCandidates != null
                            ? _buildVisualPickerCard(_visualPickerCandidates!)
                            : (_currentProduct != null
                                ? _buildProductCard(_currentProduct!)
                                : (_unknownPhase ==
                                        _UnknownSheetPhase.miniForm
                                    ? _buildUnknownMiniForm(
                                        _detectedCode ?? '')
                                    : _buildUnknownPrompt(
                                        _detectedCode ?? ''))))
                        : _buildBottomHint(),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              _circleButton(
                icon: Icons.close,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Tooltip(
                        message:
                            'Live Scan reads barcodes and product labels — '
                            'point the camera; no extra mode to open.',
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade700.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.sectionName.isEmpty
                                  ? 'Live Scan'
                                  : 'Live Scan • ${widget.sectionName}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Barcode',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.95,
                                      ),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  const TextSpan(text: ' or label · '),
                                  TextSpan(
                                    text: _objectInFrame
                                        ? 'In view'
                                        : 'Point camera',
                                  ),
                                  TextSpan(text: ' · $_lockPhaseSubtitle'),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _stabilityPill(),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _circleButton(
                icon: Icons.auto_awesome,
                onTap:
                    _fusionBusy ? () {} : () => unawaited(_runFusionIdentify()),
                tooltip: 'Visual match (LAN MobileCLIP)',
              ),
              const SizedBox(width: 8),
              _circleButton(
                icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                onTap: () async {
                  final c = _cameraController;
                  if (c == null || !c.value.isInitialized) return;
                  try {
                    if (_torchOn) {
                      await c.setFlashMode(FlashMode.off);
                    } else {
                      await c.setFlashMode(FlashMode.torch);
                    }
                    if (mounted) setState(() => _torchOn = !_torchOn);
                  } catch (_) {}
                },
              ),
              const SizedBox(width: 8),
              _circleButton(
                icon: Icons.flip_camera_ios,
                onTap: () async {
                  if (_cameras.length < 2) return;
                  _cameraIndex = (_cameraIndex + 1) % _cameras.length;
                  await _pauseStream();
                  await _openCameraAt(_cameraIndex);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stabilityPill() {
    final (bg, icon, label) = switch (_lockPhase) {
      _LockPhase.ready => (
          Colors.blueGrey.shade700,
          Icons.center_focus_weak,
          'Ready',
        ),
      _LockPhase.locking => (
          Colors.amber.shade800,
          Icons.blur_on,
          'Locking',
        ),
      _LockPhase.locked => (
          Colors.green.shade800,
          Icons.verified_outlined,
          'Locked',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final button = Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
    if (tooltip == null || tooltip.isEmpty) return button;
    return Tooltip(message: tooltip, child: button);
  }

  /// Error/debug sheet when ✨ fusion fails (success uses product card / picker).
  Widget _buildFusionResultOverlay(FusionResult result) {
    final ok = result.isSuccess && result.scanCode.isNotEmpty;
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      ok ? Icons.auto_awesome : Icons.error_outline,
                      color: ok ? Colors.teal.shade700 : Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ok ? 'Fusion details' : 'Fusion error',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _navy,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: _dismissFusionResult,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (!ok) ...[
                  Text(
                    result.message ?? 'Unknown fusion error',
                    style: TextStyle(color: Colors.red.shade800, height: 1.3),
                  ),
                ] else ...[
                  Text(
                    result.excelName.isNotEmpty
                        ? result.excelName
                        : result.skuName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'scan_code: ${result.scanCode}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'confidence: ${result.confidence.toStringAsFixed(3)} · '
                    '${result.resolutionStatus}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  if (result.topK.length > 1) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Top matches',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...result.topK.take(3).map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '${c.score.toStringAsFixed(3)}  ${c.scanCode}  '
                          '${c.excelName.isNotEmpty ? c.excelName : c.skuName}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Fusion error details — tap ✨ again after fixing the server.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _dismissFusionResult,
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomHint() {
    if (_ocrNoMatchSnippet != null &&
        _ocrNoMatchSnippet!.isNotEmpty &&
        _objectInFrame) {
      return Container(
        key: ValueKey('ocr-${_ocrNoMatchSnippet.hashCode}'),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.deepPurple.shade900.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.deepPurple.shade100.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.text_fields, color: Colors.deepPurple.shade100),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Label read — no Excel match',
                    style: TextStyle(
                      color: Colors.deepPurple.shade50,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _ocrNoMatchSnippet!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_lockPhase == _LockPhase.locking) {
      return Container(
        key: const ValueKey('locking'),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.amber.shade900.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.amber.shade200.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.amber.shade100,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Hold steady — confirming (${_stableFrameCount.clamp(1, _stableFramesNeeded)}/$_stableFramesNeeded)',
                style: TextStyle(
                  color: Colors.amber.shade50,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('idle'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.center_focus_strong, color: Colors.white70, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Fit the bottle or label inside the white frame',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Phase 2 medium-confidence UX: pick among Excel-mapped CLIP candidates.
  Widget _buildVisualPickerCard(List<VisualCandidate> candidates) {
    return Container(
      key: ValueKey(
        'visual-picker-${candidates.map((c) => c.scanCode).join(',')}',
      ),
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.teal.shade700, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Select matching product',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _navy,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Dismiss',
                  onPressed: _dismissVisualPicker,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              'Visual match — confirm before adding',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 10),
            ...candidates.map((c) {
              final scorePct = (c.score * 100).clamp(0, 999).toStringAsFixed(0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _onVisualCandidatePicked(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            alignment: Alignment.center,
                            child: Text(
                              '$scorePct%',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Colors.teal.shade900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: _navy,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  c.scanCode,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.teal.shade700,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(StockItem p) {
    final scanCode = p.scanCode ?? _detectedCode ?? '';
    final isVisual = _scannedItemSource == 'visual';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _hideTimer?.cancel();
        _hideTimer = null;
      },
      child: Container(
      key: ValueKey('prod-${p.scanCode}-${p.code}'),
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const FaIcon(
                    FontAwesomeIcons.boxesStacked,
                    color: _navy,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name.isEmpty ? '(no name)' : p.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isVisual) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Text(
                            'Visual match',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.teal.shade800,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '${p.department.isEmpty ? '—' : p.department}  •  Code ${p.code}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    '\$${p.rate.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const FaIcon(FontAwesomeIcons.barcode,
                      size: 12, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      scanCode,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade800,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _qtyButton(
                  icon: Icons.remove,
                  onTap: _decrementCount,
                  enabled: _manualCount > 1,
                ),
                Container(
                  width: 64,
                  alignment: Alignment.center,
                  child: Text(
                    '$_manualCount',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _qtyButton(
                  icon: Icons.add,
                  onTap: _incrementCount,
                  enabled: true,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isAdding ? null : _onAddPressed,
                      icon: _isAdding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check, size: 20),
                      label: Text(_isAdding ? 'Adding…' : 'ADD'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: 'Quantity (type or use ±)',
                isDense: true,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null && n > 0 && n != _manualCount) {
                  setState(() => _manualCount = n);
                  _resetHideTimer();
                }
              },
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _qtyButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return Material(
      color: enabled ? _navy : Colors.grey.shade300,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildUnknownPrompt(String barcode) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _hideTimer?.cancel();
        _hideTimer = null;
      },
      child: Container(
      key: ValueKey('unknown-prompt-$barcode'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FaIcon(FontAwesomeIcons.triangleExclamation,
                  color: Colors.orange.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Not in your sheet',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.orange.shade900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      barcode,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade900,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add details to count it now. It will appear in the '
                      'missing-items report as manually added.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade900.withValues(alpha: 0.85),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    _clearScanUiForNextItem(resetManualQty: true);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade900,
                    side: BorderSide(color: Colors.orange.shade400),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Skip',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _injectNameController.clear();
                      _injectDeptController.text =
                          widget.allocatedDepartment.trim().isEmpty
                              ? widget.sectionName
                              : widget.allocatedDepartment;
                      _injectRateController.clear();
                      _unknownPhase = _UnknownSheetPhase.miniForm;
                    });
                    _resetHideTimer();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Add to sheet',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildUnknownMiniForm(String barcode) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _hideTimer?.cancel();
        _hideTimer = null;
      },
      child: Container(
      key: ValueKey('unknown-form-$barcode'),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'New sheet row',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Colors.orange.shade900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            barcode,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _injectNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Item name',
              isDense: true,
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _injectDeptController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Department',
              isDense: true,
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _injectRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            decoration: InputDecoration(
              labelText: 'Rate',
              isDense: true,
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _unknownPhase = _UnknownSheetPhase.prompt);
                    _resetHideTimer();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _commitInjectedSheetRow(barcode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Save & continue',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  void _commitInjectedSheetRow(String barcode) {
    FocusScope.of(context).unfocus();
    final name = _injectNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter an item name.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    var dept = _injectDeptController.text.trim();
    if (dept.isEmpty) {
      dept = widget.allocatedDepartment.trim().isEmpty
          ? widget.sectionName
          : widget.allocatedDepartment;
    }
    final rateRaw = _injectRateController.text.trim();
    final rate = double.tryParse(rateRaw);
    if (rate == null || rate < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid rate (0 or more).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final scanKey = normalizeScanCode(barcode);
    if (scanKey.isEmpty) return;

    final injected = StockItem(
      scanCode: scanKey,
      code: scanKey,
      name: name,
      department: dept,
      rate: rate,
      quantity: 0,
    );
    widget.previousStock[scanKey] = injected;
    widget.onPreviousStockChanged?.call();

    setState(() {
      _currentProduct = injected;
      _isUnknownProduct = false;
      _unknownPhase = _UnknownSheetPhase.prompt;
      _scannedItemSource = 'manual';
      _lockPhase = _LockPhase.locked;
      _manualCount = 1;
      _syncQtyFieldFromState();
    });
    _hideTimer?.cancel();
    _hideTimer = null;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved to session sheet: $name'),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Full-screen dim with a clear rounded cutout, stroke, and optional red glow.
class _FramingGuidePainter extends CustomPainter {
  _FramingGuidePainter({
    required this.scanWindow,
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
    required this.scrimOutside,
    this.pulseT = 0,
  });

  final Rect scanWindow;
  final Color borderColor;
  final double borderWidth;
  final BorderRadius borderRadius;
  final Color scrimOutside;
  /// 0 = no glow; 1 = full pulse strength (placement hint).
  final double pulseT;

  @override
  void paint(Canvas canvas, Size size) {
    if (scanWindow.isEmpty || scanWindow.isInfinite) return;

    final backgroundPath = Path()..addRect(Offset.zero & size);
    final cutoutRect =
        borderRadius == BorderRadius.zero
            ? RRect.fromRectAndCorners(scanWindow)
            : RRect.fromRectAndCorners(
              scanWindow,
              topLeft: borderRadius.topLeft,
              topRight: borderRadius.topRight,
              bottomLeft: borderRadius.bottomLeft,
              bottomRight: borderRadius.bottomRight,
            );
    final cutoutPath = Path()..addRRect(cutoutRect);
    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    canvas.drawPath(
      overlayPath,
      Paint()
        ..color = scrimOutside
        ..style = PaintingStyle.fill,
    );

    if (pulseT > 0) {
      final glow = Paint()
        ..color = borderColor.withValues(alpha: 0.28 + 0.42 * pulseT)
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth + 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawRRect(cutoutRect, glow);
    }

    canvas.drawRRect(
      cutoutRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FramingGuidePainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.scrimOutside != scrimOutside ||
        oldDelegate.pulseT != pulseT;
  }
}
