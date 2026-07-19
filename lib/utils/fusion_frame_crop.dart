import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Center crop matching Live Scan bottle framing (~0.70×W, ~0.58×H, 1.52 aspect).
class FusionCropResult {
  const FusionCropResult({
    required this.jpegBytes,
    required this.width,
    required this.height,
  });

  final Uint8List jpegBytes;
  final int width;
  final int height;
}

/// Decode a full-frame JPEG, crop the center bottle window, re-encode JPEG.
FusionCropResult? centerCropBottleJpeg(
  Uint8List fullJpegBytes, {
  int quality = 90,
}) {
  final decoded = img.decodeImage(fullJpegBytes);
  if (decoded == null || decoded.width < 32 || decoded.height < 32) {
    return null;
  }

  final w = decoded.width;
  final h = decoded.height;
  final maxW = w * 0.70;
  final maxH = h * 0.58;
  const aspectHPerW = 1.52;
  var cropW = maxW;
  var cropH = cropW * aspectHPerW;
  if (cropH > maxH) {
    cropH = maxH;
    cropW = cropH / aspectHPerW;
  }

  // Match Live Scan guide: slightly above geometric center (0.44 of height).
  final cx = w * 0.5;
  final cy = h * 0.44;
  var x0 = (cx - cropW / 2).round();
  var y0 = (cy - cropH / 2).round();
  var cw = cropW.round();
  var ch = cropH.round();

  if (x0 < 0) x0 = 0;
  if (y0 < 0) y0 = 0;
  if (x0 + cw > w) cw = w - x0;
  if (y0 + ch > h) ch = h - y0;
  if (cw < 16 || ch < 16) return null;

  final cropped = img.copyCrop(
    decoded,
    x: x0,
    y: y0,
    width: cw,
    height: ch,
  );
  final out = img.encodeJpg(cropped, quality: quality);
  return FusionCropResult(
    jpegBytes: Uint8List.fromList(out),
    width: cropped.width,
    height: cropped.height,
  );
}
