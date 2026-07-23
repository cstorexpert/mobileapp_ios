import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:countx/config/config.dart';
import 'package:countx/models/fusion_result.dart';

/// Thin LAN client for the CountX MobileCLIP sandbox (`countx_live_preview_sandbox`).
/// Does not use the Render auth token — local Wi‑Fi only.
class FusionApiService {
  FusionApiService({Dio? dio, String? baseUrl})
      : _baseUrl = _normalizeBase(baseUrl ?? AppConfig.fusionBaseUrl),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 45),
                sendTimeout: const Duration(seconds: 45),
              ),
            );

  final Dio _dio;
  final String _baseUrl;

  static String _normalizeBase(String url) {
    if (url.isEmpty) return url;
    return url.endsWith('/') ? url : '$url/';
  }

  String get baseUrl => _baseUrl;

  Future<bool> healthCheck() async {
    try {
      final res = await _dio.get('${_baseUrl}api/health');
      final data = res.data;
      if (data is Map && data['status'] == 'ok') return true;
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Runs MobileCLIP fuse on [jpegBytes].
  /// Prefer sending a center crop with bbox covering the full crop
  /// (`0,0,width,height`) so the server does not re-crop incorrectly.
  Future<FusionResult> fuseFrame({
    required Uint8List jpegBytes,
    required int x1,
    required int y1,
    required int x2,
    required int y2,
    String filename = 'frame.jpg',
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(jpegBytes, filename: filename),
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
      });
      final res = await _dio.post(
        '${_baseUrl}api/fuse',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        return FusionResult.fromJson(data);
      }
      if (data is Map) {
        return FusionResult.fromJson(Map<String, dynamic>.from(data));
      }
      return FusionResult.error('Unexpected fuse response');
    } on DioException catch (e) {
      final msg = e.message ?? e.toString();
      return FusionResult.error(
        'Fusion server unreachable ($msg). Check Wi‑Fi and fusionBaseUrl.',
      );
    } catch (e) {
      return FusionResult.error(e.toString());
    }
  }

  Future<List<double>?> embedCrop(Uint8List jpegBytes) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(jpegBytes, filename: 'crop.jpg'),
      });
      final res = await _dio.post(
        '${_baseUrl}api/embed_crop',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      final data = res.data;
      if (data is Map && data['status'] == 'success' && data['embedding'] is List) {
        return (data['embedding'] as List)
            .map((e) => (e as num).toDouble())
            .toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Registers / appends a reference crop under [scanCode] on the LAN sandbox.
  /// When [append] is true, existing gallery views are kept (Phase 3 multi-view).
  Future<RegisterSkuResult> registerSku({
    required String scanCode,
    required String skuName,
    required String prompt,
    required Uint8List jpegBytes,
    String keywords = '',
    String department = '',
    bool append = true,
  }) async {
    try {
      final form = FormData.fromMap({
        'scan_code': scanCode,
        'sku_name': skuName,
        'excel_name': skuName,
        'prompt': prompt,
        'keywords': keywords,
        'department': department,
        'append': append ? 'true' : 'false',
        'files': MultipartFile.fromBytes(jpegBytes, filename: 'enroll.jpg'),
      });
      final res = await _dio.post(
        '${_baseUrl}api/register_sku',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      final data = res.data;
      if (data is Map) {
        final status = data['status']?.toString() ?? '';
        if (status == 'success' || status == 'skipped') {
          return RegisterSkuResult(
            success: status == 'success',
            skipped: status == 'skipped',
            scanCode: data['scan_code']?.toString() ?? scanCode,
            message: data['message']?.toString(),
            imagesProcessed: (data['images_processed'] as num?)?.toInt() ?? 0,
            viewCount: (data['view_count'] as num?)?.toInt(),
          );
        }
        return RegisterSkuResult(
          success: false,
          message: data['message']?.toString() ?? 'register_sku failed',
        );
      }
      return const RegisterSkuResult(
        success: false,
        message: 'Unexpected register_sku response',
      );
    } on DioException catch (e) {
      return RegisterSkuResult(
        success: false,
        message: e.message ?? e.toString(),
      );
    } catch (e) {
      return RegisterSkuResult(success: false, message: e.toString());
    }
  }
}

class RegisterSkuResult {
  const RegisterSkuResult({
    required this.success,
    this.skipped = false,
    this.scanCode,
    this.message,
    this.imagesProcessed = 0,
    this.viewCount,
  });

  final bool success;
  final bool skipped;
  final String? scanCode;
  final String? message;
  final int imagesProcessed;
  final int? viewCount;
}
