/// Response from CountX sandbox `POST /api/fuse` (scan_code-keyed gallery).
class FusionCandidate {
  const FusionCandidate({
    required this.scanCode,
    required this.skuName,
    required this.excelName,
    required this.score,
  });

  final String scanCode;
  final String skuName;
  final String excelName;
  final double score;

  factory FusionCandidate.fromJson(Map<String, dynamic> json) {
    return FusionCandidate(
      scanCode: (json['scan_code'] ?? '').toString(),
      skuName: (json['sku_name'] ?? json['sku'] ?? '').toString(),
      excelName: (json['excel_name'] ?? json['sku_name'] ?? json['sku'] ?? '')
          .toString(),
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class FusionResult {
  const FusionResult({
    required this.status,
    required this.scanCode,
    required this.skuName,
    required this.excelName,
    required this.confidence,
    required this.resolutionStatus,
    required this.topK,
    this.ocrText = '',
    this.gateReason = '',
    this.message,
  });

  final String status;
  final String scanCode;
  final String skuName;
  final String excelName;
  final double confidence;
  final String resolutionStatus;
  final List<FusionCandidate> topK;
  final String ocrText;
  final String gateReason;
  final String? message;

  bool get isSuccess => status == 'success';

  /// Open-set reject from sandbox — no claimed gallery winner.
  /// top_k may still list nearest neighbors for Excel mapping.
  bool get isUnknownGallery => resolutionStatus == 'unknown';

  factory FusionResult.fromJson(Map<String, dynamic> json) {
    final topRaw = json['top_k'];
    final topK = <FusionCandidate>[];
    if (topRaw is List) {
      for (final item in topRaw) {
        if (item is Map<String, dynamic>) {
          topK.add(FusionCandidate.fromJson(item));
        } else if (item is Map) {
          topK.add(FusionCandidate.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return FusionResult(
      status: (json['status'] ?? 'error').toString(),
      scanCode: (json['scan_code'] ?? '').toString(),
      skuName: (json['sku_name'] ?? json['winner'] ?? '').toString(),
      excelName: (json['excel_name'] ?? json['sku_name'] ?? json['winner'] ?? '')
          .toString(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      resolutionStatus: (json['resolution_status'] ?? 'needs_review').toString(),
      topK: topK,
      ocrText: (json['ocr_text'] ?? '').toString(),
      gateReason: (json['gate_reason'] ?? '').toString(),
      message: json['message']?.toString(),
    );
  }

  factory FusionResult.error(String message) {
    return FusionResult(
      status: 'error',
      scanCode: '',
      skuName: '',
      excelName: '',
      confidence: 0,
      resolutionStatus: 'needs_review',
      topK: const [],
      message: message,
    );
  }
}
