import 'package:excel/excel.dart';

/// Column indices for a price-book / Excel upload row.
class PriceBookColumnMap {
  const PriceBookColumnMap({
    required this.scanCode,
    required this.description,
    required this.department,
    required this.rate,
    required this.quantity,
  });

  final int scanCode;
  final int description;
  final int department;
  final int rate;
  final int quantity;

  /// Scan Code | Item Description | Department | Rate | Qty
  static const standard = PriceBookColumnMap(
    scanCode: 0,
    description: 1,
    department: 2,
    rate: 3,
    quantity: 4,
  );

  /// Scan Code | Item Description | Item Code (ignored) | Department | Rate | Qty
  static const legacyWithItemCode = PriceBookColumnMap(
    scanCode: 0,
    description: 1,
    department: 3,
    rate: 4,
    quantity: 5,
  );
}

class PriceBookRow {
  const PriceBookRow({
    required this.scanCode,
    required this.name,
    required this.department,
    required this.rate,
    required this.quantity,
  });

  final String scanCode;
  final String name;
  final String department;
  final double rate;
  final int quantity;
}

String excelCellAsString(dynamic cell) {
  try {
    final cellValue = cell?.value;
    if (cellValue == null) return '';
    if (cellValue is TextCellValue) return cellValue.value.toString().trim();
    if (cellValue is IntCellValue) return cellValue.value.toString().trim();
    if (cellValue is DoubleCellValue) {
      final v = cellValue.value;
      if (v.isFinite && v == v.roundToDouble()) {
        return v.round().toString();
      }
      return v.toString().trim();
    }
    return cellValue.toString().trim();
  } catch (_) {
    return '';
  }
}

double excelCellAsDouble(dynamic cell) {
  try {
    final cellValue = cell?.value;
    if (cellValue == null) return 0.0;
    if (cellValue is IntCellValue) return cellValue.value.toDouble();
    if (cellValue is DoubleCellValue) return cellValue.value;
    if (cellValue is TextCellValue) {
      return double.tryParse(cellValue.value.toString().trim()) ?? 0.0;
    }
    return double.tryParse(cellValue.toString()) ?? 0.0;
  } catch (_) {
    return 0.0;
  }
}

int excelCellAsInt(dynamic cell) {
  try {
    final cellValue = cell?.value;
    if (cellValue == null) return 0;
    if (cellValue is IntCellValue) return cellValue.value;
    if (cellValue is DoubleCellValue) return cellValue.value.round();
    if (cellValue is TextCellValue) {
      return int.tryParse(cellValue.value.toString().trim()) ?? 0;
    }
    return int.tryParse(cellValue.toString()) ?? 0;
  } catch (_) {
    return 0;
  }
}

String _normalizeHeader(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Detects columns from the header row. Ignores any [Item Code] column.
PriceBookColumnMap? detectPriceBookColumns(List<dynamic> headerRow) {
  final headers = headerRow.map((c) => _normalizeHeader(excelCellAsString(c))).toList();

  int? colFor(List<String> keys) {
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h.isEmpty) continue;
      for (final key in keys) {
        if (h == key || h.contains(key)) return i;
      }
    }
    return null;
  }

  final scan = colFor(['scan code', 'barcode', 'scan', 'upc', 'ean']);
  final desc = colFor(['item description', 'description', 'item name', 'product name', 'name']);
  final itemCode = colFor(['item code', 'itemcode', 'sku', 'product code', 'plu', 'internal code']);
  final dept = colFor(['department', 'dept', 'category', 'location']);
  final rate = colFor(['rate', 'price group', 'price', 'unit retail', 'retail']);
  final qty = colFor(['qty', 'quantity', 'count', 'on hand']);

  if (scan == null || desc == null || rate == null || qty == null) {
    return null;
  }

  int? departmentCol = dept;
  // If headers name an Item Code column but not Department, dept is usually next.
  if (departmentCol == null && itemCode != null) {
    departmentCol = itemCode + 1;
    if (departmentCol >= headers.length) departmentCol = null;
  }

  if (departmentCol == null) return null;

  return PriceBookColumnMap(
    scanCode: scan,
    description: desc,
    department: departmentCol,
    rate: rate,
    quantity: qty,
  );
}

/// Resolves column layout from headers, with safe fallbacks for legacy sheets.
PriceBookColumnMap resolvePriceBookColumns(
  List<dynamic> headerRow, {
  List<dynamic>? sampleDataRow,
}) {
  final detected = detectPriceBookColumns(headerRow);
  if (detected != null) return detected;

  final headers =
      headerRow.map((c) => _normalizeHeader(excelCellAsString(c))).toList();
  final hasItemCodeHeader = headers.any(
    (h) =>
        h.contains('item code') ||
        h == 'sku' ||
        h.contains('product code') ||
        h.contains('plu'),
  );

  final width = sampleDataRow?.length ?? headerRow.length;
  if (hasItemCodeHeader || width >= 6) {
    return PriceBookColumnMap.legacyWithItemCode;
  }
  return PriceBookColumnMap.standard;
}

/// Parses one data row using [cols]. Returns null if the row is empty/invalid.
PriceBookRow? parsePriceBookRow(List<dynamic> row, PriceBookColumnMap cols) {
  if (row.length <= cols.quantity) return null;

  final scanCode = scanCodeFromExcelCell(row[cols.scanCode]);
  final name = excelCellAsString(row[cols.description]);
  final department = excelCellAsString(row[cols.department]);
  final rate = excelCellAsDouble(row[cols.rate]);
  final quantity = excelCellAsInt(row[cols.quantity]);

  if (scanCode.isEmpty || name.isEmpty) return null;

  return PriceBookRow(
    scanCode: scanCode,
    name: name,
    department: department,
    rate: rate,
    quantity: quantity,
  );
}

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
