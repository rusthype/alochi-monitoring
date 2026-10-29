// F32: in offline-pack (memory) mode TestCache only sees the pack's tests, so
// image GC / catalog pruning built from it would delete the persistent
// downloads. Both must be no-ops there.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/cache/test_image_store.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1];

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('mem_gc_');
    TestCache.enterMemoryMode();
  });
  tearDown(() {
    TestCache.exitMemoryMode();
    dir.deleteSync(recursive: true);
  });

  test('gcStore does not delete persistent images while in pack mode',
      () async {
    final store = TestImageStore(
        root: Directory('${dir.path}/test_images'),
        client: MockClient((r) async => http.Response.bytes(_png, 200)));
    await store.init();
    await store.fetch('https://img.test/persistent.png');
    final root = Directory('${dir.path}/test_images');
    final old = DateTime.now().subtract(const Duration(days: 3));
    for (final f in root.listSync().whereType<File>()) {
      f.setLastModifiedSync(old);
    }
    // The pack's only test references a different image.
    await TestCache.upsert(
        'pack', 'P', 1, 1,
        jsonEncode({
          'variants': {
            '1': {
              'S': [
                {'img': 'https://img.test/pack.png'}
              ]
            }
          }
        }));

    final svc = TestCatalogService(MonitoringApi(), store: store);
    await svc.gcStore();

    expect(store.cachedFile('https://img.test/persistent.png'), isNotNull);
    expect(root.listSync().whereType<File>(), isNotEmpty);
  });

  test('pruneNotIn leaves memory entries alone in pack mode', () async {
    await TestCache.upsert('a', 'A', 1, 1, '{"x":1}');
    await TestCache.upsert('b', 'B', 1, 1, '{"x":1}');
    await TestCache.pruneNotIn({'a'});
    expect((await TestCache.all()).map((r) => r['test_key']).toSet(),
        {'a', 'b'});
  });
}
