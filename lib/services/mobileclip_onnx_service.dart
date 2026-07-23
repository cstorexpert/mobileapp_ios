import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'package:countx/services/mobileclip_model_store.dart';
import 'package:countx/services/product_embedding_repository.dart';
import 'package:countx/utils/mobileclip_preprocess.dart';

/// On-device MobileCLIP-S2 visual embedder (ORT file session).
class MobileClipOnnxService {
  MobileClipOnnxService({MobileClipModelStore? modelStore})
      : _store = modelStore ?? MobileClipModelStore();

  final MobileClipModelStore _store;
  final OnnxRuntime _ort = OnnxRuntime();

  OrtSession? _session;
  String? _inputName;
  String? _outputName;
  Future<bool>? _initFuture;

  MobileClipModelStore get modelStore => _store;

  Future<bool> get isReady async => _store.isReady();

  /// Loads ORT session from cached graph path (weights must be sibling).
  Future<bool> ensureLoaded({
    void Function(double progress)? onDownloadProgress,
  }) async {
    if (_session != null) return true;
    _initFuture ??= _doInit(onDownloadProgress: onDownloadProgress);
    try {
      return await _initFuture!;
    } finally {
      if (_session == null) _initFuture = null;
    }
  }

  Future<bool> _doInit({
    void Function(double progress)? onDownloadProgress,
  }) async {
    final ready = await _store.ensureReady(onProgress: onDownloadProgress);
    if (!ready) return false;
    final path = await _store.sessionPathIfReady();
    if (path == null) return false;

    try {
      _session = await _ort.createSession(path);
      final inputs = await _session!.getInputInfo();
      final outputs = await _session!.getOutputInfo();
      _inputName = inputs.isNotEmpty
          ? (inputs.first['name'] as String? ?? 'input')
          : 'input';
      _outputName = outputs.isNotEmpty
          ? (outputs.first['name'] as String? ?? 'output')
          : 'output';
      debugPrint(
        '[MobileCLIP] ORT session ready in=$_inputName out=$_outputName',
      );
      return true;
    } catch (e) {
      debugPrint('[MobileCLIP] ORT createSession failed: $e');
      _session = null;
      return false;
    }
  }

  /// Embed JPEG crop → L2-normalized 512-d vector, or null on failure.
  Future<List<double>?> embedJpeg(Uint8List jpegBytes) async {
    final ok = await ensureLoaded();
    if (!ok || _session == null) return null;

    try {
      final tensor = MobileClipPreprocess.fromJpegBytesAsList(jpegBytes);
      final input = await OrtValue.fromList(
        tensor,
        [1, 3, MobileClipPreprocess.size, MobileClipPreprocess.size],
      );
      final outputs = await _session!.run({_inputName!: input});
      await input.dispose();

      final outKey = _outputName!;
      final OrtValue? outVal = outputs[outKey] ??
          (outputs.isNotEmpty ? outputs.values.first : null);
      if (outVal == null) {
        debugPrint('[MobileCLIP] no output tensor');
        return null;
      }
      final raw = await outVal.asList();
      for (final v in outputs.values) {
        try {
          await v.dispose();
        } catch (_) {}
      }

      final flat = _flattenToDoubles(raw);
      if (flat.length < ProductEmbeddingRepository.embeddingDim) {
        debugPrint(
          '[MobileCLIP] unexpected dim=${flat.length} '
          '(want ${ProductEmbeddingRepository.embeddingDim})',
        );
        return null;
      }
      final vec = flat.take(ProductEmbeddingRepository.embeddingDim).toList();
      return _l2Normalize(vec);
    } catch (e, st) {
      debugPrint('[MobileCLIP] embed failed: $e\n$st');
      return null;
    }
  }

  static List<double> _flattenToDoubles(dynamic raw) {
    final out = <double>[];
    void walk(dynamic v) {
      if (v is num) {
        out.add(v.toDouble());
      } else if (v is List) {
        for (final e in v) {
          walk(e);
        }
      }
    }

    walk(raw);
    return out;
  }

  static List<double> _l2Normalize(List<double> v) {
    var sumSq = 0.0;
    for (final x in v) {
      sumSq += x * x;
    }
    final norm = math.sqrt(sumSq) + 1e-8;
    return [for (final x in v) x / norm];
  }

  Future<void> dispose() async {
    final s = _session;
    _session = null;
    _initFuture = null;
    if (s != null) {
      try {
        await s.close();
      } catch (_) {}
    }
  }
}
