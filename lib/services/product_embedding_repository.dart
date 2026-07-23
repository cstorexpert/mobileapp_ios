import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Local gallery of MobileCLIP embeddings keyed by Excel [scan_code].
///
/// Phase 3: persists confirmations so Phase 5 can search offline; LAN register
/// remains the live fuse source until then.
class ProductEmbeddingRepository {
  ProductEmbeddingRepository._();
  static final ProductEmbeddingRepository instance =
      ProductEmbeddingRepository._();

  static const String modelId = 'MobileCLIP-S2';
  static const int embeddingDim = 512;
  static const int maxViewsPerScanCode = 5;

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'countx_product_embeddings.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE product_embeddings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scan_code TEXT NOT NULL,
            model_id TEXT NOT NULL,
            dim INTEGER NOT NULL,
            embedding_blob BLOB NOT NULL,
            crop_path TEXT,
            source TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_pe_scan_code ON product_embeddings(scan_code)',
        );
      },
    );
    return _db!;
  }

  Future<int> countForScanCode(String scanCode) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM product_embeddings WHERE scan_code = ?',
      [scanCode],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<bool> hasRoom(String scanCode) async {
    return (await countForScanCode(scanCode)) < maxViewsPerScanCode;
  }

  /// Saves one view. Returns row id, or null if at cap / invalid dim.
  Future<int?> insertView({
    required String scanCode,
    required List<double> embedding,
    String? cropPath,
    String source = 'scanner',
  }) async {
    if (embedding.length != embeddingDim) return null;
    if (!await hasRoom(scanCode)) return null;

    final db = await _database;
    final blob = _float32ToBytes(embedding);
    return db.insert('product_embeddings', {
      'scan_code': scanCode,
      'model_id': modelId,
      'dim': embeddingDim,
      'embedding_blob': blob,
      'crop_path': cropPath,
      'source': source,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<StoredProductEmbedding>> listForScanCode(String scanCode) async {
    final db = await _database;
    final rows = await db.query(
      'product_embeddings',
      where: 'scan_code = ?',
      whereArgs: [scanCode],
      orderBy: 'id ASC',
    );
    return rows.map(StoredProductEmbedding.fromMap).toList();
  }

  Future<Set<String>> allScanCodes() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT scan_code FROM product_embeddings',
    );
    return rows.map((r) => r['scan_code'] as String).toSet();
  }

  /// Deletes all local views for [scanCode] (and crop files when present).
  Future<int> deleteForScanCode(String scanCode) async {
    final existing = await listForScanCode(scanCode);
    for (final row in existing) {
      final path = row.cropPath;
      if (path != null && path.isNotEmpty) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    final db = await _database;
    return db.delete(
      'product_embeddings',
      where: 'scan_code = ?',
      whereArgs: [scanCode],
    );
  }

  /// Writes JPEG under app documents for optional re-enroll / debug.
  Future<String?> saveCropFile(String scanCode, Uint8List jpegBytes) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory(p.join(dir.path, 'product_crops', scanCode));
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(p.join(folder.path, name));
      await file.writeAsBytes(jpegBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Uint8List _float32ToBytes(List<double> values) {
    final data = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      data.setFloat32(i * 4, values[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static List<double> bytesToFloat32(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final out = <double>[];
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      out.add(data.getFloat32(i, Endian.little));
    }
    return out;
  }
}

class StoredProductEmbedding {
  const StoredProductEmbedding({
    required this.id,
    required this.scanCode,
    required this.modelId,
    required this.dim,
    required this.embeddingBlob,
    this.cropPath,
    this.source,
    required this.createdAt,
  });

  final int id;
  final String scanCode;
  final String modelId;
  final int dim;
  final Uint8List embeddingBlob;
  final String? cropPath;
  final String? source;
  final String createdAt;

  List<double> get embedding =>
      ProductEmbeddingRepository.bytesToFloat32(embeddingBlob);

  factory StoredProductEmbedding.fromMap(Map<String, dynamic> map) {
    return StoredProductEmbedding(
      id: map['id'] as int,
      scanCode: map['scan_code'] as String,
      modelId: map['model_id'] as String,
      dim: map['dim'] as int,
      embeddingBlob: map['embedding_blob'] as Uint8List,
      cropPath: map['crop_path'] as String?,
      source: map['source'] as String?,
      createdAt: map['created_at'] as String,
    );
  }
}
