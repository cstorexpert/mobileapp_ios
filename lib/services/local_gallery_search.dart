import 'dart:math' as math;

import 'package:countx/services/product_embedding_repository.dart';

/// Ranked I2I hit: max cosine over all local views for one [scanCode].
class LocalGalleryHit {
  const LocalGalleryHit({
    required this.scanCode,
    required this.score,
  });

  final String scanCode;
  final double score;
}

/// Pure Dart cosine search over SQLite gallery embeddings (Phase 5 I2I-only).
class LocalGallerySearch {
  LocalGallerySearch({ProductEmbeddingRepository? repository})
      : _repo = repository ?? ProductEmbeddingRepository.instance;

  final ProductEmbeddingRepository _repo;

  /// Returns scan_codes ranked by max view cosine (desc). Empty if gallery empty.
  Future<List<LocalGalleryHit>> search(
    List<double> query, {
    int topK = 10,
  }) async {
    if (query.length != ProductEmbeddingRepository.embeddingDim) {
      return const [];
    }
    final views = await _repo.listAllViews();
    if (views.isEmpty) return const [];

    final best = <String, double>{};
    for (final view in views) {
      if (view.dim != ProductEmbeddingRepository.embeddingDim) continue;
      final emb = view.embedding;
      if (emb.length != query.length) continue;
      final score = cosine(query, emb);
      final prev = best[view.scanCode];
      if (prev == null || score > prev) {
        best[view.scanCode] = score;
      }
    }

    final hits = best.entries
        .map((e) => LocalGalleryHit(scanCode: e.key, score: e.value))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (topK <= 0 || hits.length <= topK) return hits;
    return hits.take(topK).toList();
  }

  static double cosine(List<double> a, List<double> b) {
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    final n = math.min(a.length, b.length);
    for (var i = 0; i < n; i++) {
      final x = a[i];
      final y = b[i];
      dot += x * y;
      na += x * x;
      nb += y * y;
    }
    final denom = math.sqrt(na) * math.sqrt(nb);
    if (denom < 1e-12) return 0.0;
    return dot / denom;
  }
}
