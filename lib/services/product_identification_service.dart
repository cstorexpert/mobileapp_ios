import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:countx/config/fusion_thresholds.dart';
import 'package:countx/models/fusion_result.dart';
import 'package:countx/models/identification_result.dart';
import 'package:countx/screens/transactions.dart' show StockItem;
import 'package:countx/services/fusion_api_service.dart';
import 'package:countx/services/local_gallery_search.dart';
import 'package:countx/services/mobileclip_onnx_service.dart';
import 'package:countx/utils/scan_code_utils.dart';

/// Orchestrates MobileCLIP identify + confidence banding for Live Scan.
///
/// Empty [FusionApiService.baseUrl] → on-device ORT + SQLite I2I.
/// Non-empty → LAN `/api/fuse` (debug fallback).
///
/// Does not touch barcode/OCR — callers invoke this only after those miss.
class ProductIdentificationService {
  ProductIdentificationService({
    FusionApiService? fusionApi,
    MobileClipOnnxService? onnx,
    LocalGallerySearch? localSearch,
  })  : _fusionApi = fusionApi ??
            FusionApiService(
              dio: Dio(
                BaseOptions(
                  // Identify path: fail fast so Live Scan stays responsive.
                  connectTimeout: const Duration(seconds: 5),
                  receiveTimeout: const Duration(seconds: 20),
                  sendTimeout: const Duration(seconds: 20),
                ),
              ),
            ),
        _onnx = onnx ?? MobileClipOnnxService(),
        _localSearch = localSearch ?? LocalGallerySearch();

  final FusionApiService _fusionApi;
  final MobileClipOnnxService _onnx;
  final LocalGallerySearch _localSearch;

  FusionApiService get fusionApi => _fusionApi;
  MobileClipOnnxService get onnx => _onnx;

  /// Mirrors [FusionThresholds] for tests / callers that import this class.
  static const double highScoreThreshold = FusionThresholds.highScore;
  static const double highMarginThreshold = FusionThresholds.highMargin;
  static const double mediumScoreThreshold = FusionThresholds.mediumScore;
  static const double lowScoreFloor = FusionThresholds.lowScoreFloor;

  bool get useOnDevice => _fusionApi.baseUrl.isEmpty;

  /// Runs visual identify on a center crop and maps winners to Excel rows only.
  Future<IdentificationResult> identifyFromCrop({
    required Uint8List jpegBytes,
    required int width,
    required int height,
    required Map<String, StockItem> previousStock,
  }) async {
    if (useOnDevice) {
      return _identifyOnDevice(
        jpegBytes: jpegBytes,
        previousStock: previousStock,
      );
    }
    return _identifyLan(
      jpegBytes: jpegBytes,
      width: width,
      height: height,
      previousStock: previousStock,
    );
  }

  Future<IdentificationResult> _identifyOnDevice({
    required Uint8List jpegBytes,
    required Map<String, StockItem> previousStock,
  }) async {
    final modelReady = await _onnx.isReady;
    if (!modelReady) {
      return IdentificationResult.none(
        message:
            'Visual model not installed — tap Download or set mobileClipModelBaseUrl',
      );
    }

    final loaded = await _onnx.ensureLoaded();
    if (!loaded) {
      return IdentificationResult.none(
        message: 'Could not load on-device MobileCLIP model',
      );
    }

    final query = await _onnx.embedJpeg(jpegBytes);
    if (query == null) {
      return IdentificationResult.none(
        message: 'On-device embedding failed',
      );
    }

    final hits = await _localSearch.search(query, topK: 10);
    if (hits.isEmpty) {
      final raw = FusionResult(
        status: 'success',
        scanCode: '',
        skuName: '',
        excelName: '',
        confidence: 0,
        resolutionStatus: 'unknown',
        topK: const [],
        message: 'Local gallery empty — Save appearance first',
      );
      return IdentificationResult.unknown(
        message: 'No visual match in local gallery',
        raw: raw,
      );
    }

    final topK = [
      for (final h in hits)
        FusionCandidate(
          scanCode: h.scanCode,
          skuName: h.scanCode,
          excelName: h.scanCode,
          score: h.score,
        ),
    ];
    final top = hits.first;
    final margin =
        hits.length > 1 ? top.score - hits[1].score : top.score;
    final resolution = top.score < FusionThresholds.unknownScoreFloor
        ? 'unknown'
        : (top.score >= FusionThresholds.autoAcceptScore &&
                margin >= FusionThresholds.autoAcceptMargin
            ? 'auto-accepted'
            : 'needs_review');

    final raw = FusionResult(
      status: 'success',
      scanCode: resolution == 'unknown' ? '' : top.scanCode,
      skuName: top.scanCode,
      excelName: top.scanCode,
      confidence: top.score,
      resolutionStatus: resolution,
      topK: topK,
      message: 'on-device I2I',
    );

    final mapped = _mapInSheetCandidates(raw, previousStock);
    debugPrint(
      '[ProductID] on-device status=${raw.resolutionStatus} '
      'conf=${raw.confidence.toStringAsFixed(3)} '
      'mapped=${mapped.length} '
      'top=${mapped.isEmpty ? "-" : "${mapped.first.scanCode}@${mapped.first.score.toStringAsFixed(3)}"}',
    );

    return _bandMappedResult(raw, mapped);
  }

  Future<IdentificationResult> _identifyLan({
    required Uint8List jpegBytes,
    required int width,
    required int height,
    required Map<String, StockItem> previousStock,
  }) async {
    final raw = await _fusionApi.fuseFrame(
      jpegBytes: jpegBytes,
      x1: 0,
      y1: 0,
      x2: width,
      y2: height,
      filename: 'live_crop.jpg',
    );

    if (!raw.isSuccess) {
      return IdentificationResult.none(
        message: raw.message ?? 'Fusion failed',
        raw: raw,
      );
    }

    final mapped = _mapInSheetCandidates(raw, previousStock);
    debugPrint(
      '[ProductID] fuse status=${raw.resolutionStatus} '
      'conf=${raw.confidence.toStringAsFixed(3)} '
      'winner=${raw.scanCode.isEmpty ? "(none)" : raw.scanCode} '
      'mapped=${mapped.length} '
      'top=${mapped.isEmpty ? "-" : "${mapped.first.scanCode}@${mapped.first.score.toStringAsFixed(3)}"}',
    );

    return _bandMappedResult(raw, mapped);
  }

  IdentificationResult _bandMappedResult(
    FusionResult raw,
    List<VisualCandidate> mapped,
  ) {
    if (mapped.isEmpty) {
      return IdentificationResult.unknown(
        message: raw.isUnknownGallery
            ? (raw.message ?? 'No visual match in gallery')
            : 'No Excel match for visual candidates',
        raw: raw,
      );
    }

    final band = classifyBand(
      top1Score: mapped.first.score,
      margin: mapped.length > 1
          ? mapped.first.score - mapped[1].score
          : mapped.first.score,
      rawConfidence: raw.confidence,
    );

    if (mapped.first.score < lowScoreFloor) {
      return IdentificationResult.unknown(
        message: 'Visual confidence too low',
        raw: raw,
      );
    }

    if (band == VisualConfidenceBand.low) {
      return IdentificationResult(
        source: IdentificationSource.visual,
        band: VisualConfidenceBand.low,
        scanCode: mapped.first.scanCode,
        candidates: mapped.take(3).toList(),
        raw: raw,
        message: 'Weak visual match — pick carefully or save appearance',
      );
    }

    return IdentificationResult(
      source: IdentificationSource.visual,
      band: band,
      scanCode: mapped.first.scanCode,
      candidates: mapped.take(3).toList(),
      raw: raw,
      message: raw.isUnknownGallery
          ? 'Gallery open-set was weak; showing Excel-mapped candidates'
          : null,
    );
  }

  /// Public for tests / tuning.
  VisualConfidenceBand classifyBand({
    required double top1Score,
    required double margin,
    double? rawConfidence,
  }) {
    final score = top1Score;
    if (score < lowScoreFloor) return VisualConfidenceBand.low;

    if (score >= highScoreThreshold && margin >= highMarginThreshold) {
      return VisualConfidenceBand.high;
    }

    if (score >= mediumScoreThreshold) {
      return VisualConfidenceBand.medium;
    }

    final server = rawConfidence ?? score;
    if (server >= mediumScoreThreshold && score >= lowScoreFloor) {
      return VisualConfidenceBand.medium;
    }

    return VisualConfidenceBand.low;
  }

  List<VisualCandidate> _mapInSheetCandidates(
    FusionResult raw,
    Map<String, StockItem> previousStock,
  ) {
    final seen = <String>{};
    final out = <VisualCandidate>[];

    void consider(String scanCode, String displayName, double score) {
      final code = normalizeScanCode(scanCode);
      if (code.isEmpty || seen.contains(code)) return;
      final stock = lookupStockByScanCode(previousStock, code);
      if (stock == null) return;
      seen.add(code);
      out.add(
        VisualCandidate(
          scanCode: stock.scanCode ?? code,
          displayName: _stockDisplayName(stock, displayName, code),
          score: score,
          stockItem: stock,
        ),
      );
    }

    for (final c in raw.topK) {
      consider(
        c.scanCode,
        c.excelName.isNotEmpty ? c.excelName : c.skuName,
        c.score,
      );
    }

    if (raw.scanCode.isNotEmpty) {
      consider(
        raw.scanCode,
        raw.excelName.isNotEmpty ? raw.excelName : raw.skuName,
        raw.confidence,
      );
      out.sort((a, b) => b.score.compareTo(a.score));
    }

    return out;
  }

  /// Prefer Excel Item Description, then Item Code, then any fuse label, then scan_code.
  /// Ampm sheets often leave description empty and put the readable name in `code`.
  static String _stockDisplayName(
    StockItem stock,
    String fuseLabel,
    String scanCode,
  ) {
    if (stock.name.trim().isNotEmpty) return stock.name.trim();
    if (stock.code.trim().isNotEmpty) return stock.code.trim();
    if (fuseLabel.trim().isNotEmpty) return fuseLabel.trim();
    return scanCode;
  }
}
