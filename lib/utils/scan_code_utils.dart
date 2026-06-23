import 'package:excel/excel.dart';

/// Normalizes raw scanner / spreadsheet scan codes to a stable lookup key.
String normalizeScanCode(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return s;

  // Excel sometimes surfaces numeric barcodes as "4012345678901.0".
  if (RegExp(r'^\d+\.0+$').hasMatch(s)) {
    s = s.replaceAll(RegExp(r'\.0+$'), '');
  }

  // Scientific notation from Excel double cells (e.g. 4.012345678901e+12).
  final sci = RegExp(r'^(\d+(?:\.\d+)?)[eE]([+-]?\d+)$').firstMatch(s);
  if (sci != null) {
    final mantissa = double.tryParse(sci.group(1)!);
    final exp = int.tryParse(sci.group(2)!);
    if (mantissa != null && exp != null) {
      final scaled = mantissa * _pow10(exp);
      if (scaled == scaled.roundToDouble() && scaled.abs() < 1e16) {
        s = scaled.round().toString();
      }
    }
  }

  return s.replaceAll(RegExp(r'[\x00-\x1f]'), '');
}

double _pow10(int exp) {
  if (exp == 0) return 1;
  var v = 1.0;
  final steps = exp.abs();
  for (var i = 0; i < steps; i++) {
    v *= 10;
  }
  return exp < 0 ? 1 / v : v;
}

/// Reads a scan-code cell without losing leading zeros or integer barcodes.
String scanCodeFromExcelCell(dynamic cell) {
  try {
    final cellValue = cell?.value;
    if (cellValue == null) return '';

    if (cellValue is TextCellValue) {
      return normalizeScanCode(cellValue.value.toString());
    }
    if (cellValue is IntCellValue) {
      return normalizeScanCode(cellValue.value.toString());
    }
    if (cellValue is DoubleCellValue) {
      final v = cellValue.value;
      if (v.isFinite && v == v.roundToDouble() && v.abs() < 1e16) {
        return normalizeScanCode(v.round().toString());
      }
      return normalizeScanCode(v.toString());
    }
    return normalizeScanCode(cellValue.toString());
  } catch (_) {
    return '';
  }
}

/// Candidate keys for map lookup (exact, trimmed zeros, EAN padding).
Iterable<String> scanCodeLookupKeys(String raw) sync* {
  final code = normalizeScanCode(raw);
  if (code.isEmpty) return;

  yield code;

  final noLeadingZeros = code.replaceFirst(RegExp(r'^0+'), '');
  if (noLeadingZeros.isNotEmpty && noLeadingZeros != code) {
    yield noLeadingZeros;
  }

  // UPC-A (12) vs EAN-13: scanner may drop or add a leading zero.
  if (code.length == 12) yield '0$code';
  if (code.length == 13 && code.startsWith('0')) yield code.substring(1);
}

/// Resolves a scanned / OCR code against the in-memory price book.
T? lookupStockByScanCode<T>(Map<String, T> stock, String raw) {
  for (final key in scanCodeLookupKeys(raw)) {
    final hit = stock[key];
    if (hit != null) return hit;
  }
  return null;
}
