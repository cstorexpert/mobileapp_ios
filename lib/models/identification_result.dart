import 'package:countx/models/fusion_result.dart';
import 'package:countx/screens/transactions.dart' show StockItem;

/// Where Live Scan resolved identity.
enum IdentificationSource { barcode, ocr, visual, none }

/// How strongly to trust a visual (MobileCLIP) match in the UI.
///
/// Thresholds live in [FusionThresholds] / fusion_thresholds.json (Phase 4).
enum VisualConfidenceBand {
  /// Strong top-1 + margin → single suggested product (still requires ADD).
  high,

  /// Typical phone scores → show top-k picker.
  medium,

  /// Weak but above floor → still show top-k picker (labeled weak); below floor → no claim.
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
      source == IdentificationSource.visual && candidates.isNotEmpty;

  /// Sandbox open-set reject or app low band — offer Save appearance.
  bool get isUnknownVisual =>
      (raw?.isUnknownGallery ?? false) ||
      (source == IdentificationSource.none &&
          band == VisualConfidenceBand.low &&
          (raw?.isSuccess ?? false));

  factory IdentificationResult.none({String? message, FusionResult? raw}) {
    return IdentificationResult(
      source: IdentificationSource.none,
      band: VisualConfidenceBand.low,
      candidates: const [],
      message: message,
      raw: raw,
    );
  }

  factory IdentificationResult.unknown({
    String? message,
    FusionResult? raw,
    List<VisualCandidate> candidates = const [],
  }) {
    return IdentificationResult(
      source: IdentificationSource.none,
      band: VisualConfidenceBand.low,
      candidates: candidates,
      message: message ?? 'No visual match in gallery',
      raw: raw,
    );
  }
}
