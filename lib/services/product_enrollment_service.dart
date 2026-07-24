import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:countx/services/fusion_api_service.dart';
import 'package:countx/services/mobileclip_onnx_service.dart';
import 'package:countx/services/product_embedding_repository.dart';
import 'package:countx/utils/crop_quality.dart';

enum EnrollmentOutcome {
  enrolled,
  skippedAtCap,
  skippedQuality,
  skippedNoScanCode,
  failedLocal,
  failedLan,
  partialLan, // local ok, LAN failed (LAN mode only)
}

enum ForgetOutcome {
  clearedBoth,
  clearedLocalOnly,
  nothingLocal,
  failed,
}

class EnrollmentResult {
  const EnrollmentResult({
    required this.outcome,
    this.message,
    this.localCount,
    this.lanViewCount,
  });

  final EnrollmentOutcome outcome;
  final String? message;
  final int? localCount;
  final int? lanViewCount;

  bool get didStoreLocal =>
      outcome == EnrollmentOutcome.enrolled ||
      outcome == EnrollmentOutcome.partialLan;

  bool get didStoreLan =>
      outcome == EnrollmentOutcome.enrolled ||
      (lanViewCount != null && lanViewCount! > 0);
}

class ForgetResult {
  const ForgetResult({
    required this.outcome,
    this.message,
    this.localDeleted = 0,
    this.lanCleared = false,
  });

  final ForgetOutcome outcome;
  final String? message;
  final int localDeleted;
  final bool lanCleared;
}

/// Face-forward Save appearance: quality-gate → embed → local SQLite (+ LAN when set).
///
/// JPEG is used only in memory for quality / embed / LAN register — not persisted.
/// Never called on unconfirmed CLIP suggestions.
class ProductEnrollmentService {
  ProductEnrollmentService({
    FusionApiService? fusionApi,
    ProductEmbeddingRepository? repository,
    MobileClipOnnxService? onnx,
  })  : _fusionApi = fusionApi ?? FusionApiService(),
        _repo = repository ?? ProductEmbeddingRepository.instance,
        _onnx = onnx ?? MobileClipOnnxService();

  final FusionApiService _fusionApi;
  final ProductEmbeddingRepository _repo;
  final MobileClipOnnxService _onnx;

  /// [source] is Live Scan item source: scanner | visual | manual | ocr.
  Future<EnrollmentResult> enrollAfterConfirm({
    required String scanCode,
    required String skuName,
    required Uint8List jpegBytes,
    String source = 'scanner',
    String department = '',
  }) async {
    final code = scanCode.trim();
    if (code.isEmpty) {
      return const EnrollmentResult(
        outcome: EnrollmentOutcome.skippedNoScanCode,
        message: 'empty scan_code',
      );
    }

    if (!await _repo.hasRoom(code)) {
      debugPrint('[Enroll] skip $code — at local cap');
      return EnrollmentResult(
        outcome: EnrollmentOutcome.skippedAtCap,
        message:
            'Already have ${ProductEmbeddingRepository.maxViewsPerScanCode} local views. '
            'Tap Forget appearance to replace.',
        localCount: await _repo.countForScanCode(code),
      );
    }

    final quality = assessCropJpeg(jpegBytes);
    if (!quality.ok) {
      debugPrint('[Enroll] skip $code — ${quality.reason}');
      return EnrollmentResult(
        outcome: EnrollmentOutcome.skippedQuality,
        message: quality.reason,
      );
    }

    final display = skuName.trim().isEmpty ? code : skuName.trim();
    final prompt = 'A product photo of $display';
    final lanMode = _fusionApi.baseUrl.isNotEmpty;

    debugPrint(
      '[Enroll] start $code name="$display" bytes=${jpegBytes.length} '
      'quality=${quality.laplacianVariance.toStringAsFixed(1)} '
      'size=${quality.width}x${quality.height} mode=${lanMode ? "LAN" : "on-device"}',
    );

    List<double>? embedding;
    if (lanMode) {
      embedding = await _fusionApi.embedCrop(jpegBytes);
      debugPrint(
        '[Enroll] embed_crop ${embedding == null ? "FAIL" : "ok dim=${embedding.length}"}',
      );
    }

    // Phase 5: on-device embed when offline, or when LAN embed failed.
    if (embedding == null ||
        embedding.length != ProductEmbeddingRepository.embeddingDim) {
      final ready = await _onnx.ensureLoaded();
      if (ready) {
        embedding = await _onnx.embedJpeg(jpegBytes);
        debugPrint(
          '[Enroll] on-device embed ${embedding == null ? "FAIL" : "ok dim=${embedding.length}"}',
        );
      } else {
        debugPrint('[Enroll] on-device embed unavailable (model not ready)');
      }
    }

    // Embeddings-only: JPEG is used in-memory for quality/embed/LAN; not persisted.
    var localStored = false;
    if (embedding != null &&
        embedding.length == ProductEmbeddingRepository.embeddingDim) {
      final id = await _repo.insertView(
        scanCode: code,
        embedding: embedding,
        cropPath: null,
        source: source,
      );
      localStored = id != null;
      if (!localStored) {
        return const EnrollmentResult(
          outcome: EnrollmentOutcome.failedLocal,
          message: 'local insert failed (cap or dim)',
        );
      }
      // Drop any legacy on-disk crops from older builds.
      await _repo.purgeAllCropFiles();
    } else {
      debugPrint('[Enroll] no embedding — cannot store local vector for $code');
    }

    var lanOk = false;
    var lanSkipped = false;
    int? lanViews;
    String? lanMessage;
    if (!lanMode) {
      lanMessage = 'fusionBaseUrl is empty';
      debugPrint('[Enroll] LAN skipped — on-device mode');
    } else {
      final reg = await _fusionApi.registerSku(
        scanCode: code,
        skuName: display,
        prompt: prompt,
        jpegBytes: jpegBytes,
        department: department,
        append: true,
      );
      lanOk = reg.success;
      lanSkipped = reg.skipped;
      lanViews = reg.viewCount;
      lanMessage = reg.message;
      debugPrint(
        '[Enroll] register_sku success=${reg.success} skipped=${reg.skipped} '
        'views=${reg.viewCount} imgs=${reg.imagesProcessed} msg=${reg.message}',
      );
    }

    final localCount = await _repo.countForScanCode(code);

    // Offline success: local vector is enough for on-device ✨.
    if (!lanMode) {
      if (localStored && localCount > 0) {
        return EnrollmentResult(
          outcome: EnrollmentOutcome.enrolled,
          message: 'Saved appearance on phone ($localCount views)',
          localCount: localCount,
        );
      }
      return EnrollmentResult(
        outcome: EnrollmentOutcome.failedLocal,
        message:
            'Could not embed on phone — download the visual model first '
            '(or set fusionBaseUrl for LAN).',
        localCount: localCount,
      );
    }

    if (lanOk || lanSkipped) {
      final views = lanViews ?? localCount;
      return EnrollmentResult(
        outcome: EnrollmentOutcome.enrolled,
        message: lanSkipped
            ? 'Appearance already on LAN ($views views). Forget to replace.'
            : 'Saved appearance on LAN ($views views)',
        localCount: localCount,
        lanViewCount: lanViews,
      );
    }

    if (localCount > 0) {
      return EnrollmentResult(
        outcome: EnrollmentOutcome.partialLan,
        message:
            'Saved on phone only — LAN failed (${lanMessage ?? "unreachable"}). '
            'On-device ✨ still works; check Wi‑Fi / sandbox for LAN fuse.',
        localCount: localCount,
        lanViewCount: lanViews,
      );
    }

    return EnrollmentResult(
      outcome: EnrollmentOutcome.failedLan,
      message: lanMessage ??
          'Could not save appearance — is the sandbox running?',
      localCount: localCount,
      lanViewCount: lanViews,
    );
  }

  /// Clears local SQLite views and, when reachable, LAN gallery for [scanCode].
  Future<ForgetResult> forgetAppearance(String scanCode) async {
    final code = scanCode.trim();
    if (code.isEmpty) {
      return const ForgetResult(
        outcome: ForgetOutcome.failed,
        message: 'empty scan_code',
      );
    }

    final localDeleted = await _repo.deleteForScanCode(code);
    await _repo.purgeAllCropFiles();
    var lanCleared = false;
    String? lanMessage;

    if (_fusionApi.baseUrl.isNotEmpty) {
      final lan = await _fusionApi.forgetSku(code);
      lanCleared = lan.success;
      lanMessage = lan.message;
      debugPrint(
        '[Enroll] forget_sku success=${lan.success} '
        'removed=${lan.removedViews} msg=${lan.message}',
      );
    } else {
      lanMessage = 'fusionBaseUrl empty';
    }

    if (lanCleared) {
      return ForgetResult(
        outcome: ForgetOutcome.clearedBoth,
        message: localDeleted > 0
            ? 'Cleared local + LAN appearance for $code'
            : 'Cleared LAN appearance for $code',
        localDeleted: localDeleted,
        lanCleared: true,
      );
    }

    if (localDeleted > 0) {
      final offline = _fusionApi.baseUrl.isEmpty;
      return ForgetResult(
        outcome: ForgetOutcome.clearedLocalOnly,
        message: offline
            ? 'Cleared local appearance for $code'
            : 'Cleared local appearance for $code — LAN not cleared '
                '(${lanMessage ?? "unreachable"}). Check Wi‑Fi / sandbox.',
        localDeleted: localDeleted,
        lanCleared: false,
      );
    }

    return ForgetResult(
      outcome: ForgetOutcome.nothingLocal,
      message: 'No local appearance for $code'
          '${lanMessage != null && _fusionApi.baseUrl.isNotEmpty ? " — LAN: $lanMessage" : ""}',
      localDeleted: 0,
      lanCleared: false,
    );
  }
}
