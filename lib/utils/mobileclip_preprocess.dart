import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// MobileCLIP-S2 preprocess matching sandbox `preprocess_clip_numpy`.
///
/// Resize 256×256 bicubic → /255 → CHW → CLIP mean/std → `[1,3,256,256]` float32.
class MobileClipPreprocess {
  MobileClipPreprocess._();

  static const int size = 256;

  static const List<double> mean = [
    0.48145466,
    0.4578275,
    0.40821073,
  ];
  static const List<double> std = [
    0.26862954,
    0.26130258,
    0.27577711,
  ];

  /// Returns a flat float32 NCHW tensor (length `1*3*256*256`).
  static Float32List fromJpegBytes(Uint8List jpegBytes) {
    final decoded = img.decodeImage(jpegBytes);
    if (decoded == null) {
      throw StateError('Failed to decode JPEG for MobileCLIP preprocess');
    }
    return fromImage(decoded);
  }

  static Float32List fromImage(img.Image source) {
    final resized = img.copyResize(
      source,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );

    final out = Float32List(1 * 3 * size * size);
    var i = 0;
    // CHW layout
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final pixel = resized.getPixel(x, y);
          final channel = c == 0
              ? pixel.r.toDouble()
              : c == 1
                  ? pixel.g.toDouble()
                  : pixel.b.toDouble();
          final v = (channel / 255.0 - mean[c]) / std[c];
          out[i++] = v;
        }
      }
    }
    return out;
  }

  /// Same tensor as a plain `List<double>` for OrtValue.fromList.
  static List<double> fromJpegBytesAsList(Uint8List jpegBytes) {
    return fromJpegBytes(jpegBytes).toList(growable: false);
  }
}
