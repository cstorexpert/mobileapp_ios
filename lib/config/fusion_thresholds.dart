/// Confidence / quality thresholds for Live Scan visual match + enrollment.
///
/// Keep numeric values identical to
/// `countx_live_preview_sandbox/fusion_thresholds.json`.
/// Run `scripts/assert_threshold_parity.py` after edits.
class FusionThresholds {
  FusionThresholds._();

  /// Server open-set: below this → resolution_status unknown.
  static const double unknownScoreFloor = 0.32;

  /// Server resolution_status auto-accepted (app never auto-adds).
  static const double autoAcceptScore = 0.82;
  static const double autoAcceptMargin = 0.08;

  /// App UI: strong top-1 + margin → single suggested product (still requires ADD).
  static const double highScore = 0.70;
  static const double highMargin = 0.08;

  /// App UI: show top-k picker at/above this (typical phone crops ~0.45–0.55).
  static const double mediumScore = 0.38;

  /// Below this → no visual claim / no weak picker.
  static const double lowScoreFloor = 0.30;

  /// Enrollment crop quality gates.
  static const int minSide = 64;
  static const int minBytes = 1500;
  static const double minLaplacianVariance = 25.0;
}
