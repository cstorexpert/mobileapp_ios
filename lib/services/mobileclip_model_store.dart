import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:countx/config/config.dart';

/// Caches MobileCLIP visual ONNX (+ external weights) under app documents.
///
/// ORT requires both files co-located on disk (cannot load .onnx.data from
/// asset bytes alone). Download-on-first-run keeps the APK lean.
class MobileClipModelStore {
  MobileClipModelStore({Dio? dio, String? modelBaseUrl})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                // ~147 MB over LAN — allow a long receive window.
                receiveTimeout: const Duration(minutes: 30),
                sendTimeout: const Duration(seconds: 30),
              ),
            ),
        _modelBaseUrl = _normalizeBase(
          modelBaseUrl ?? AppConfig.mobileClipModelBaseUrl,
        );

  final Dio _dio;
  final String _modelBaseUrl;

  static const String graphFileName = 'mobileclip_visual.onnx';
  static const String weightsFileName = 'mobileclip_visual.onnx.data';

  /// Expected sizes from the repo `dataset/` export (bytes).
  static const int expectedGraphBytes = 3263485;
  static const int expectedWeightsBytes = 144048128;

  /// Allow ±0.5% drift for alternate re-exports while catching truncated downloads.
  static const double sizeTolerance = 0.005;

  bool _downloading = false;
  double _progress = 0;

  bool get isDownloading => _downloading;
  double get downloadProgress => _progress;

  static String _normalizeBase(String url) {
    if (url.isEmpty) return url;
    return url.endsWith('/') ? url : '$url/';
  }

  Future<Directory> modelDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'mobileclip'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> graphPath() async =>
      p.join((await modelDirectory()).path, graphFileName);

  Future<String> weightsPath() async =>
      p.join((await modelDirectory()).path, weightsFileName);

  /// True when both files exist and sizes look complete.
  Future<bool> isReady() async {
    final graph = File(await graphPath());
    final weights = File(await weightsPath());
    if (!await graph.exists() || !await weights.exists()) return false;
    return _sizeOk(await graph.length(), expectedGraphBytes) &&
        _sizeOk(await weights.length(), expectedWeightsBytes);
  }

  static bool _sizeOk(int actual, int expected) {
    final delta = (actual - expected).abs() / expected;
    return delta <= sizeTolerance;
  }

  /// Ensures model files are on disk. Downloads when missing and [modelBaseUrl]
  /// is set. Returns true when ready for ORT.
  Future<bool> ensureReady({
    void Function(double progress)? onProgress,
  }) async {
    if (await isReady()) return true;
    if (_modelBaseUrl.isEmpty) {
      debugPrint(
        '[MobileCLIP] model missing and mobileClipModelBaseUrl is empty — '
        'push files into app documents/mobileclip/',
      );
      return false;
    }
    return download(onProgress: onProgress);
  }

  /// Downloads both ONNX files into `{documents}/mobileclip/`.
  Future<bool> download({void Function(double progress)? onProgress}) async {
    if (_downloading) return false;
    if (_modelBaseUrl.isEmpty) return false;

    _downloading = true;
    _progress = 0;
    onProgress?.call(0);

    final dir = await modelDirectory();
    final graphTmp = File(p.join(dir.path, '$graphFileName.part'));
    final weightsTmp = File(p.join(dir.path, '$weightsFileName.part'));
    final graphFinal = File(p.join(dir.path, graphFileName));
    final weightsFinal = File(p.join(dir.path, weightsFileName));

    try {
      // Weights dominate size — report combined progress.
      final totalExpected =
          expectedGraphBytes + expectedWeightsBytes.toDouble();
      var graphGot = 0;
      var weightsGot = 0;

      void emit() {
        _progress = ((graphGot + weightsGot) / totalExpected).clamp(0.0, 1.0);
        onProgress?.call(_progress);
      }

      await _dio.download(
        '$_modelBaseUrl$graphFileName',
        graphTmp.path,
        onReceiveProgress: (received, total) {
          graphGot = received;
          emit();
        },
      );
      graphGot = await graphTmp.length();
      if (!_sizeOk(graphGot, expectedGraphBytes)) {
        throw StateError(
          'Graph size mismatch: got $graphGot expected ~$expectedGraphBytes',
        );
      }

      await _dio.download(
        '$_modelBaseUrl$weightsFileName',
        weightsTmp.path,
        onReceiveProgress: (received, total) {
          weightsGot = received;
          emit();
        },
      );
      weightsGot = await weightsTmp.length();
      if (!_sizeOk(weightsGot, expectedWeightsBytes)) {
        throw StateError(
          'Weights size mismatch: got $weightsGot expected ~$expectedWeightsBytes',
        );
      }

      if (await graphFinal.exists()) await graphFinal.delete();
      if (await weightsFinal.exists()) await weightsFinal.delete();
      await graphTmp.rename(graphFinal.path);
      await weightsTmp.rename(weightsFinal.path);

      _progress = 1;
      onProgress?.call(1);
      debugPrint('[MobileCLIP] model ready at ${dir.path}');
      return true;
    } catch (e) {
      debugPrint('[MobileCLIP] download failed: $e');
      try {
        if (await graphTmp.exists()) await graphTmp.delete();
        if (await weightsTmp.exists()) await weightsTmp.delete();
      } catch (_) {}
      return false;
    } finally {
      _downloading = false;
    }
  }

  /// Absolute path for ORT `createSession` (graph file; weights must be sibling).
  Future<String?> sessionPathIfReady() async {
    if (!await isReady()) return null;
    return graphPath();
  }
}
