import 'package:countx/screens/transactions.dart' show StockItem;

String _normalize(String s) {
  return s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> _tokens(String s) => _normalize(s)
    .split(' ')
    .where((t) => t.length > 2)
    .toList();

/// Best-effort match of noisy OCR text to a row in [stock] using the item
/// [StockItem.name] field. Tuned so a clear brand token like "sprite" matches
/// "SPRITE LEMON LIME 2.25L".
StockItem? fuzzyFindStockByLabelText(
  String rawOcr,
  Map<String, StockItem> stock,
) {
  final ocrNorm = _normalize(rawOcr);
  if (ocrNorm.length < 3) return null;

  final ocrTokens = _tokens(rawOcr);
  if (ocrTokens.isEmpty) return null;

  StockItem? best;
  var bestScore = 0.0;

  for (final item in stock.values) {
    final name = item.name;
    if (name.isEmpty) continue;

    final nameNorm = _normalize(name);
    final nameTokens = _tokens(name);
    if (nameTokens.isEmpty) continue;

    var score = 0.0;

    // Word-in-haystack: "sprite" in "sprite lemon lime 2 25l"
    for (final word in ocrTokens) {
      if (word.length < 3) continue;
      if (nameNorm.contains(word)) {
        score += 18;
        continue;
      }
      for (final n in nameTokens) {
        if (n.length < 3) continue;
        if (n.contains(word) || word.contains(n)) {
          score += 14;
          break;
        }
      }
    }

    // Prefix / leading-brand match (OCR often gets first word right)
    final firstName = nameTokens.first;
    if (firstName.length >= 3) {
      for (final word in ocrTokens) {
        if (word.length >= 3 &&
            (firstName.startsWith(word) ||
                word.startsWith(firstName) ||
                firstName.contains(word))) {
          score += 22;
          break;
        }
      }
    }

    // Token overlap ratio (legacy-style)
    var matchedNameTokens = 0;
    for (final t in nameTokens) {
      if (t.length < 3) continue;
      if (ocrNorm.contains(t)) {
        matchedNameTokens++;
        continue;
      }
      for (final o in ocrTokens) {
        if (o.contains(t) || t.contains(o)) {
          matchedNameTokens++;
          break;
        }
      }
    }
    final overlap = nameTokens.isEmpty
        ? 0.0
        : matchedNameTokens / nameTokens.length * 100;

    final compactName = nameNorm.replaceAll(' ', '');
    final compactOcr = ocrNorm.replaceAll(' ', '');
    final bonus = compactName.length >= 4 && compactOcr.contains(compactName)
        ? 35.0
        : 0.0;

    score += overlap * 0.35 + bonus;

    if (score > bestScore && score >= 16) {
      bestScore = score;
      best = item;
    }
  }

  return best;
}
