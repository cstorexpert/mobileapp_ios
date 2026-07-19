import 'package:countx/models/fusion_result.dart';
import 'package:countx/screens/transactions.dart' show StockItem;

/// Where Live Scan resolved identity.
enum IdentificationSource { barcode, ocr, visual, none }

/// How strongly to trust a visual (MobileCLIP) match in the UI.
///
/// Thresholds are intentionally lenient for LAN phone crops (~0.45–0.55).
/// Phase 4 will recalibrate from a device matrix.
enum VisualConfidenceBand {
  /// Strong top-1 + margin → single suggested product (still requires ADD).
  high,

  /// Typical phone scores → show top-k picker.
  medium,

  /// Too weak / no Excel-mapped candidates → do not claim a product.
  low,
}

class VisualCandidate {
  const VisualCandidate({
    required this.scanCode,
    required this.displayName,
    required this.score,
    required this.stockItem,
  });

  final String scanCode;
  final String displayName;
  final double score;

  /// Null when [scanCode] is not in the uploaded price book.
  final StockItem? stockItem;

  bool get inSheet => stockItem != null;
}

class IdentificationResult {
  const IdentificationResult({
    required this.source,
    required this.band,
    required this.candidates,
    this.scanCode,
    this.message,
    this.raw,
  });

  final IdentificationSource source;
  final VisualConfidenceBand band;

  /// Best Excel-mapped scan code when [band] is high (or after user pick).
  final String? scanCode;

  /// Excel-mapped candidates only, best score first (max 3 for UI).
  final List<VisualCandidate> candidates;

  final String? message;
  final FusionResult? raw;

  bool get hasVisualClaim =>
      source == IdentificationSource.visual &&
      (band == VisualConfidenceBand.high ||
          band == VisualConfidenceBand.medium) &&
      candidates.isNotEmpty;

  factory IdentificationResult.none({String? message, FusionResult? raw}) {
    return IdentificationResult(
      source: IdentificationSource.none,
      band: VisualConfidenceBand.low,
      candidates: const [],
      message: message,
      raw: raw,
    );
  }
}
