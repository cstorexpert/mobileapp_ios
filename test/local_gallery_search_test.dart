import 'package:flutter_test/flutter_test.dart';

import 'package:countx/services/local_gallery_search.dart';

void main() {
  test('LocalGallerySearch.cosine is 1 for identical vectors', () {
    final a = List<double>.generate(512, (i) => i * 0.001);
    expect(LocalGallerySearch.cosine(a, a), closeTo(1.0, 1e-9));
  });

  test('LocalGallerySearch.cosine is ~0 for orthogonal-ish vectors', () {
    final a = List<double>.filled(512, 0.0);
    final b = List<double>.filled(512, 0.0);
    a[0] = 1.0;
    b[1] = 1.0;
    expect(LocalGallerySearch.cosine(a, b), closeTo(0.0, 1e-9));
  });
}
