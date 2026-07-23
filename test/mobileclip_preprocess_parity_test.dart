import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:countx/utils/mobileclip_preprocess.dart';

/// Dart preprocess vs Python `preprocess_clip_numpy` (fixture cosine ≥ 0.99).
void main() {
  test('MobileClipPreprocess matches Python tensor cosine ≥ 0.99', () async {
    final root = _findRepoRoot();
    final fixtureJpeg = File('$root/dataset/phase5_parity/fixture.jpg');
    final expectedPath = File('$root/dataset/phase5_parity/expected_tensor.json');

    expect(fixtureJpeg.existsSync(), isTrue,
        reason: 'missing fixture.jpg — copy a crop into dataset/phase5_parity/');
    expect(expectedPath.existsSync(), isTrue,
        reason: 'run: python scripts/export_phase5_parity_fixture.py');

    final expectedJson =
        jsonDecode(await expectedPath.readAsString()) as Map<String, dynamic>;
    final expected = (expectedJson['values'] as List)
        .map((e) => (e as num).toDouble())
        .toList();

    final jpegBytes = await fixtureJpeg.readAsBytes();
    final actual = MobileClipPreprocess.fromJpegBytes(jpegBytes);

    expect(actual.length, expected.length);
    final cos = _cosine(actual, expected);
    // ignore: avoid_print
    print('Dart vs Python preprocess cosine: $cos');
    expect(cos, greaterThanOrEqualTo(0.99));
  });
}

String _findRepoRoot() {
  // test/ → mobileapp_ios/ → repo root
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = File('${dir.path}/dataset/phase5_parity/fixture.jpg');
    if (candidate.existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  // When cwd is mobileapp_ios
  final fromApp = Directory.current.parent;
  final viaApp = File('${fromApp.path}/dataset/phase5_parity/fixture.jpg');
  if (viaApp.existsSync()) return fromApp.path;
  fail('Could not locate dataset/phase5_parity from ${Directory.current.path}');
}

double _cosine(Float32List a, List<double> b) {
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
  final denom = math.sqrt(na) * math.sqrt(nb) + 1e-12;
  return dot / denom;
}
