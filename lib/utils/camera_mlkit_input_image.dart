import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// Same rotation value passed to [InputImage] — use for overlay coordinate mapping.
InputImageRotation resolveInputImageRotation(CameraController controller) {
  final cam = controller.description;
  final sensorOrientation = cam.sensorOrientation;

  final orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  if (Platform.isIOS) {
    return InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;
  }
  if (Platform.isAndroid) {
    var rotationCompensation =
        orientations[controller.value.deviceOrientation] ?? 0;
    if (cam.lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (sensorOrientation - rotationCompensation + 360) % 360;
    }
    return InputImageRotationValue.fromRawValue(rotationCompensation) ??
        InputImageRotation.rotation0deg;
  }
  return InputImageRotation.rotation0deg;
}

/// Converts a [CameraImage] from the `camera` package into an [InputImage]
/// for Google ML Kit.
///
/// Handles both single-plane NV21 (some devices) **and** the much more common
/// multi-plane YUV_420_888 by concatenating Y + VU interleaved into NV21.
InputImage? cameraImageToInputImage(
  CameraImage image,
  CameraController controller,
) {
  final rotation = resolveInputImageRotation(controller);

  final format = InputImageFormatValue.fromRawValue(image.format.raw);

  if (Platform.isIOS) {
    if (format != InputImageFormat.bgra8888) return null;
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format!,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  if (Platform.isAndroid) {
    Uint8List bytes;
    int bytesPerRow;

    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
      bytesPerRow = image.planes.first.bytesPerRow;
    } else if (image.planes.length >= 3) {
      bytes = _yuv420toNv21(image);
      bytesPerRow = image.planes[0].bytesPerRow;
    } else {
      debugPrint('[LiveScan] Unexpected plane count: ${image.planes.length}');
      return null;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  return null;
}

/// Converts a YUV_420_888 [CameraImage] (3 planes: Y, U, V) into an NV21
/// byte array (Y plane followed by interleaved VU).
Uint8List _yuv420toNv21(CameraImage image) {
  final width = image.width;
  final height = image.height;

  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  final nv21 = Uint8List(width * height + (width * height ~/ 2));

  var pos = 0;
  for (var row = 0; row < height; row++) {
    final offset = row * yRowStride;
    for (var col = 0; col < width; col++) {
      nv21[pos++] = yPlane.bytes[offset + col];
    }
  }

  final chromaHeight = height ~/ 2;
  final chromaWidth = width ~/ 2;
  for (var row = 0; row < chromaHeight; row++) {
    final uvOffset = row * uvRowStride;
    for (var col = 0; col < chromaWidth; col++) {
      final uvIdx = uvOffset + col * uvPixelStride;
      nv21[pos++] = vPlane.bytes[uvIdx]; // V first in NV21
      nv21[pos++] = uPlane.bytes[uvIdx]; // then U
    }
  }

  return nv21;
}
