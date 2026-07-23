import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:countx/config/fusion_thresholds.dart';
import 'package:countx/models/fusion_result.dart';
import 'package:countx/models/identification_result.dart';
import 'package:countx/screens/transactions.dart' show StockItem;
import 'package:countx/services/fusion_api_service.dart';
import 'package:countx/utils/scan_code_utils.dart';

/// Orchestrates LAN MobileCLIP fuse + confidence banding for Live Scan.
///
/// Does not touch barcode/OCR — callers invoke this only after those miss.
class ProductIdentificationService {
  ProductIdentificationService({FusionApiService? fusionApi})
      : _fusionApi = fusionApi ??
            FusionApiService(
              dio: Dio(
                BaseOptions(
                  // Identify path: fail fast so Live Scan stays responsive.
                  connectTimeout: const Duration(seconds: 5),
                  receiveTimeout: const Duration(seconds: 20),
                  sendTimeout: const Duration(seconds: 20),
                ),
              ),
            );

  final FusionApiService _fusionApi;

  FusionApiService get fusionApi => _fusionApi;

  /// Mirrors [FusionThresholds] for tests / callers that import this class.
  static const double highScoreThreshold = FusionThresholds.highScore;
  static const double highMarginThreshold = FusionThresholds.highMargin;
  static const double mediumScoreThreshold = FusionThresholds.mediumScore;
  static const double lowScoreFloor = FusionThresholds.lowScoreFloor;

  /// Runs `/api/fuse` on a center crop and maps winners to Excel rows only.
  Future<IdentificationResult> identifyFromCrop({
    required Uint8List jpegBytes,
    required int width,
    required int height,
    required Map<String, StockItem> previousStock,
  }) async {
    if (_fusionApi.baseUrl.isEmpty) {
      return IdentificationResult.none(message: 'fusionBaseUrl is empty');
    }

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

    // Always map top_k → Excel first. Server may mark open-set "unknown" and
    // clear the winner, but top_k still lists gallery hits (incl. enrolled SKUs).
    final mapped = _mapInSheetCandidates(raw, previousStock);
    debugPrint(
      '[ProductID] fuse status=${raw.resolutionStatus} '
      'conf=${raw.confidence.toStringAsFixed(3)} '
      'winner=${raw.scanCode.isEmpty ? "(none)" : raw.scanCode} '
      'mapped=${mapped.length} '
      'top=${mapped.isEmpty ? "-" : "${mapped.first.scanCode}@${mapped.first.score.toStringAsFixed(3)}"}',
    );

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

    // Absolute floor: no claim at all.
    if (mapped.first.score < lowScoreFloor) {
      return IdentificationResult.unknown(
        message: 'Visual confidence too low',
        raw: raw,
      );
    }

    // Phase 4: low band still offers a weak top-3 picker (not "No visual match").
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

    // Usable Excel-mapped hit — show picker/card even if server said unknown.
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

    // Soft floor: if server confidence is a bit higher than mapped top1, still
    // allow picker when above floor (rare mismatch).
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
          displayName: stock.name.isNotEmpty
              ? stock.name
              : (displayName.isNotEmpty ? displayName : code),
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

    // Ensure winner is considered even if top_k omitted it.
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
}
