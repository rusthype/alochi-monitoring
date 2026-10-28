// A fresh variant draw prefers a variant whose images are all on disk, so a
// student is not blocked offline by one missing picture when another variant of
// the same test is complete. A resumed attempt keeps its variant.
import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/session/runner_dispatch.dart';
import 'package:flutter_test/flutter_test.dart';

class _Catalog extends TestCatalogService {
  _Catalog(this.complete) : super(MonitoringApi());
  final Set<int> complete;
  final checked = <int>[];
  @override
  Future<bool> variantImagesComplete(
      Map<String, dynamic> cached, int variant) async {
    checked.add(variant);
    return complete.contains(variant);
  }
}

Map<String, dynamic> _test(int variants) => {
      'variants': {for (var v = 1; v <= variants; v++) '$v': {}},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an incomplete draw is swapped for the one complete variant', () async {
    final catalog = _Catalog({3});
    final v = await previewAttemptVariant(_test(5),
        testKey: 'k', studentId: 's', drawn: 1, catalog: catalog);
    expect(v, 3);
  });

  test('a complete draw is kept without looking further', () async {
    final catalog = _Catalog({1, 2, 3});
    final v = await previewAttemptVariant(_test(5),
        testKey: 'k', studentId: 's', drawn: 2, catalog: catalog);
    expect(v, 2);
    expect(catalog.checked, [2]);
  });

  test('nothing complete: the draw stays (the caller downloads it)', () async {
    final catalog = _Catalog({});
    final v = await previewAttemptVariant(_test(4),
        testKey: 'k', studentId: 's', drawn: 4, catalog: catalog);
    expect(v, 4);
  });

  test('a fresh random draw is also steered to a complete variant', () async {
    final catalog = _Catalog({5});
    for (var i = 0; i < 20; i++) {
      final v = await previewAttemptVariant(_test(5),
          testKey: 'k', studentId: 's', catalog: catalog);
      expect(v, 5);
    }
  });

  test('a failing completeness check falls back to the draw', () async {
    final v = await previewAttemptVariant(_test(3),
        testKey: 'k', studentId: 's', drawn: 2, catalog: _Throwing());
    expect(v, 2);
  });
}

class _Throwing extends TestCatalogService {
  _Throwing() : super(MonitoringApi());
  @override
  Future<bool> variantImagesComplete(
          Map<String, dynamic> cached, int variant) =>
      throw StateError('disk');
}
