import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:countx/config/fusion_thresholds.dart';

/// Simple blur / size gates for Phase 3 enrollment crops.
class CropQualityResult {
  const CropQualityResult({
    required this.ok,
    required this.reason,
    this.width = 0,
    this.height = 0,
    this.laplacianVariance = 0,
  });

  final bool ok;
  final String reason;
  final int width;
  final int height;
  final double laplacianVariance;
}

/// Rejects tiny or very blurry JPEGs before we spend LAN / SQLite on them.
CropQualityResult assessCropJpeg(
  Uint8List jpegBytes, {
  int minSide = FusionThresholds.minSide,
  int minBytes = FusionThresholds.minBytes,
  double minLaplacianVariance = FusionThresholds.minLaplacianVariance,
}) {
  if (jpegBytes.length < minBytes) {
    return const CropQualityResult(
      ok: false,
      reason: 'crop too small (bytes)',
    );
  }

  final decoded = img.decodeImage(jpegBytes);
  if (decoded == null) {
    return const CropQualityResult(ok: false, reason: 'decode failed');
  }
  if (decoded.width < minSide || decoded.height < minSide) {
    return CropQualityResult(
      ok: false,
      reason: 'crop too small (${decoded.width}x${decoded.height})',
      width: decoded.width,
      height: decoded.height,
    );
  }

  final variance = _laplacianVariance(decoded);
  if (variance < minLaplacianVariance) {
    return CropQualityResult(
      ok: false,
      reason: 'crop too blurry (var=${variance.toStringAsFixed(1)})',
      width: decoded.width,
      height: decoded.height,
      laplacianVariance: variance,
    );
  }

  return CropQualityResult(
    ok: true,
    reason: 'ok',
    width: decoded.width,
    height: decoded.height,
    laplacianVariance: variance,
  );
}

double _laplacianVariance(img.Image src) {
  // Downscale for speed; enrollment is not latency-critical.
  final gray = img.copyResize(
    img.grayscale(src),
    width: src.width > 160 ? 160 : src.width,
  );
  final w = gray.width;
  final h = gray.height;
  if (w < 3 || h < 3) return 0;

  double sum = 0;
  double sumSq = 0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final c = gray.getPixel(x, y).luminance;
      final lap = gray.getPixel(x, y - 1).luminance +
          gray.getPixel(x, y + 1).luminance +
          gray.getPixel(x - 1, y).luminance +
          gray.getPixel(x + 1, y).luminance -
          4 * c;
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return (sumSq / n) - (mean * mean);
}
