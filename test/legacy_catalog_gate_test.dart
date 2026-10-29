// F31: the legacy (guest-flow) cache path - unit1 / bob1_4 / math_gN loaders -
// gates on the same image readiness the engine uses, and a corrupt row in
// monitoring_test_cache.db is treated as missing instead of crashing.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/cache/test_image_store.dart';
import 'package:alochi_monitoring/core/db/test_cache_db.dart';
import 'package:alochi_monitoring/core/models/test_catalog.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart'
    as engine;
import 'package:alochi_monitoring/core/sync/test_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1];

class _Api extends MonitoringApi {
  int serverVersion = 1;
  int detailCalls = 0;
  @override
  Future<List<TestCatalogEntry>> getTestCatalog() async => [
        TestCatalogEntry(
            testKey: 'unit1_eng',
            title: 'T',
            grade: 1,
            version: serverVersion,
            imageCount: 2,
            updatedAt: ''),
      ];

  @override
  Future<Map<String, dynamic>> getTestDetail(String testKey) async {
    detailCalls++;
    return {
      'test_key': testKey,
      'version': serverVersion,
      'variants': {
        '1': {
          'Vocab': [
            {'img': 'https://img.test/a.png', 'q': 'a', 'opts': ['x'], 'ans': 0},
            {'img': 'https://img.test/b.png', 'q': 'b', 'opts': ['x'], 'ans': 0},
          ],
        },
      },
    };
  }
}

void main() {
  late Directory dir;
  late _Api api;
  late Set<String> failing;
  late List<String> requested;
  late engine.TestCatalogService images;
  late TestCatalogService svc;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    engine.TestCatalogService.resetKnownMissingForTest();
    await TestCacheDb.openInMemory();
    // sqflite shares one :memory: instance across opens: start empty.
    await (await TestCacheDb.db).delete('test_cache');
    dir = Directory.systemTemp.createTempSync('legacy_gate_');
    api = _Api();
    failing = {};
    requested = [];
    final store = TestImageStore(
        root: Directory('${dir.path}/test_images'),
        client: MockClient((req) async {
          final url = req.url.toString();
          requested.add(url);
          if (failing.contains(url)) return http.Response('boom', 500);
          return http.Response.bytes([..._png, ...url.codeUnits], 200);
        }),
        timeout: const Duration(seconds: 2));
    await store.init();
    images = engine.TestCatalogService(api,
        store: store, retryDelay: Duration.zero);
    svc = TestCatalogService.forTest(() => api, () => images);
  });

  tearDown(() {
    TestCacheDb.reset();
    dir.deleteSync(recursive: true);
  });

  test('first download waits for the images, then marks the test cached',
      () async {
    final out = await svc.ensureDownloaded('unit1_eng');
    expect(out, isNotNull);
    expect(requested.toSet(), {'https://img.test/a.png', 'https://img.test/b.png'});
    expect(await TestCacheDb.cachedVersion('unit1_eng'), 1);
    expect(await images.testImagesComplete(out!), isTrue);
  });

  test('a failed image keeps the version unmarked so the next run retries',
      () async {
    failing = {'https://img.test/b.png'};
    final out = await svc.ensureDownloaded('unit1_eng');
    expect(out, isNotNull, reason: 'the fresh detail is still returned');
    expect(await TestCacheDb.cachedVersion('unit1_eng'), isNull);

    failing = {};
    await svc.ensureDownloaded('unit1_eng');
    expect(await TestCacheDb.cachedVersion('unit1_eng'), 1);
    expect(api.detailCalls, 2);
  });

  test('a current cached copy with missing images is topped up', () async {
    await svc.ensureDownloaded('unit1_eng');
    // Images evicted behind our back.
    final root = Directory('${dir.path}/test_images');
    for (final f in root.listSync().whereType<File>()) {
      f.deleteSync();
    }
    // The store's in-memory index is rebuilt on init; a fresh store sees none.
    final fresh = TestImageStore(
        root: root,
        client: MockClient((req) async {
          requested.add(req.url.toString());
          return http.Response.bytes([..._png, 7], 200);
        }),
        timeout: const Duration(seconds: 2));
    await fresh.init();
    images = engine.TestCatalogService(api,
        store: fresh, retryDelay: Duration.zero);
    svc = TestCatalogService.forTest(() => api, () => images);
    requested.clear();

    final out = await svc.ensureDownloaded('unit1_eng');
    expect(out, isNotNull);
    expect(api.detailCalls, 1, reason: 'version is current: no re-download');
    expect(requested.toSet(), {'https://img.test/a.png', 'https://img.test/b.png'});
  });

  test('a corrupt cached row is dropped and re-downloaded, never a crash',
      () async {
    await svc.ensureDownloaded('unit1_eng');
    final d = await TestCacheDb.db;
    await d.update('test_cache', {'json': '{not json'},
        where: 'test_key = ?', whereArgs: ['unit1_eng']);

    final out = await svc.ensureDownloaded('unit1_eng');
    expect(out, isNotNull);
    expect(api.detailCalls, 2);
    expect(await TestCacheDb.get('unit1_eng'), isNotNull);
  });

  test('TestCacheDb.get: corrupt or non-object row = missing, row deleted',
      () async {
    final d = await TestCacheDb.db;
    for (final bad in ['{not json', '[1,2]', '']) {
      await d.insert('test_cache', {
        'test_key': 'bad',
        'version': 3,
        'json': bad,
        'downloaded_at': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      expect(await TestCacheDb.get('bad'), isNull, reason: 'json=$bad');
      expect(await TestCacheDb.cachedVersion('bad'), isNull,
          reason: 'bad row must be gone');
    }
  });
}
