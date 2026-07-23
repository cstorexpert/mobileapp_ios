import 'package:flutter_test/flutter_test.dart';
import 'package:countx/config/fusion_thresholds.dart';
import 'package:countx/models/identification_result.dart';
import 'package:countx/services/product_identification_service.dart';

void main() {
  final svc = ProductIdentificationService();

  group('classifyBand', () {
    test('below floor is low', () {
      expect(
        svc.classifyBand(top1Score: FusionThresholds.lowScoreFloor - 0.01, margin: 1.0),
        VisualConfidenceBand.low,
      );
    });

    test('high requires score and margin', () {
      expect(
        svc.classifyBand(
          top1Score: FusionThresholds.highScore,
          margin: FusionThresholds.highMargin,
        ),
        VisualConfidenceBand.high,
      );
      expect(
        svc.classifyBand(
          top1Score: FusionThresholds.highScore,
          margin: FusionThresholds.highMargin - 0.01,
        ),
        isNot(VisualConfidenceBand.high),
      );
    });

    test('medium at typical phone score', () {
      expect(
        svc.classifyBand(top1Score: 0.50, margin: 0.02),
        VisualConfidenceBand.medium,
      );
    });

    test('between floor and medium is low (weak picker path)', () {
      final mid = (FusionThresholds.lowScoreFloor + FusionThresholds.mediumScore) / 2;
      expect(
        svc.classifyBand(top1Score: mid, margin: 0.01),
        VisualConfidenceBand.low,
      );
    });

    test('soft floor uses rawConfidence', () {
      expect(
        svc.classifyBand(
          top1Score: FusionThresholds.lowScoreFloor + 0.01,
          margin: 0.01,
          rawConfidence: FusionThresholds.mediumScore,
        ),
        VisualConfidenceBand.medium,
      );
    });
  });

  group('FusionThresholds mirrors', () {
    test('service aliases match FusionThresholds', () {
      expect(ProductIdentificationService.highScoreThreshold, FusionThresholds.highScore);
      expect(ProductIdentificationService.mediumScoreThreshold, FusionThresholds.mediumScore);
      expect(ProductIdentificationService.lowScoreFloor, FusionThresholds.lowScoreFloor);
    });
  });
}
