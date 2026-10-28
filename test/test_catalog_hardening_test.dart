// Download-time hardening of TestCatalogService: image URL discovery, batch
// resilience, readiness of the variant the engine really renders, version
// change cleanup, JSON validation, background pause / heal throttle and a
// corrupt cache DB.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/cache/test_image_store.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1];

class _Api extends MonitoringApi {
  final Map<String, Map<String, dynamic>> tests = {};
  List<Map<String, dynamic>> catalog = [];
  @override
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
          {String? groupId,
          String? schoolCode,
          String? schoolId,
          String? authToken}) async =>
      catalog;
  @override
  Future<Map<String, dynamic>?> fetchTest(String testKey,
          {String? groupId,
          String? schoolCode,
          String? schoolId,
          String? authToken}) async =>
      tests[testKey];
}

Map<String, dynamic> _q(String img) =>
    {'type': 'image_choice', 'img': img, 'q': '?', 'opts': ['a', 'b'], 'ans': 0};

Map<String, dynamic> _spec(Map<String, List<String>> byVariant,
        {int version = 1, String? cover}) =>
    {
      'title': 'T',
      'grade': 5,
      'version': version,
      if (cover != null) 'cover': cover,
      'parts': ['Math'],
      'variants': {
        for (final e in byVariant.entries)
          e.key: {
            'Math': [for (final u in e.value) _q(_u(u))]
          }
      },
    };

String _u(String n) => 'https://img.test/$n.png';

void main() {
  late Directory dir;
  late List<String> requested;
  late Map<String, Future<http.Response> Function(int attempt)> behaviour;
  late Map<String, int> attempts;
  late _Api api;
  late TestImageStore store;
  late TestCatalogService svc;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestCatalogService.resetKnownMissingForTest();
    TestCache.enterMemoryMode();
    dir = Directory.systemTemp.createTempSync('catalog_hard_');
    requested = [];
    behaviour = {};
    attempts = {};
    api = _Api();
    store = TestImageStore(
        root: Directory('${dir.path}/imgs'),
        timeout: const Duration(seconds: 2),
        client: MockClient((req) async {
          final url = req.url.toString();
          requested.add(url);
          final n = attempts[url] = (attempts[url] ?? 0) + 1;
          final h = behaviour[url];
          if (h != null) return h(n);
          return http.Response.bytes([..._png, ...utf8.encode(url)], 200);
        }));
    await store.init();
    svc = TestCatalogService(api,
        store: store,
        retryDelay: Duration.zero,
        bgJitter: () => Duration.zero,
        bgBackoff: const [Duration.zero],
        bgYield: const Duration(milliseconds: 5));
  });

  tearDown(() {
    TestCache.exitMemoryMode();
    TestCatalogService.isTestRunning = () => false;
    TestCatalogService.clock = DateTime.now;
    dir.deleteSync(recursive: true);
  });

  group('F7: which strings are images', () {
    test('links and sources are not images; image keys / extensions are', () {
      final data = {
        'title': 'T',
        'source': 'https://example.com/article',
        'link': 'https://t.me/alochi',
        'variants': {
          '1': {
            'Math': [
              {'q': 'see https://example.com/page', 'img': 'https://img.test/noext'},
              {'text': 'https://img.test/b.PNG?v=2'},
              {'opts': ['x'], 'option_images': ['https://img.test/o1', 'https://img.test/o2']},
              {'ref': 'https://example.com/doc.pdf'},
            ]
          }
        },
      };
      expect(svc.variantImageUrls(data, 1).toSet(), {
        'https://img.test/noext',
        'https://img.test/b.PNG?v=2',
        'https://img.test/o1',
        'https://img.test/o2',
      });
    });

    test('relative image paths are still absolutized', () {
      final urls = svc.variantImageUrls({
        'variants': {'1': {'Math': [{'img': '/media/q/1.png'}]}}
      }, 1);
      expect(urls, ['https://api.alochi.org/media/q/1.png']);
    });
  });

  group('F7: batch resilience', () {
    test('one failing URL does not abort the rest', () async {
      final data = _spec({'1': ['a', 'b', 'c', 'd', 'e', 'f']});
      behaviour[_u('b')] = (_) async => http.Response('busy', 503);
      expect(await svc.ensureVariantImages(data, 1), isFalse);
      for (final n in ['a', 'c', 'd', 'e', 'f']) {
        expect(store.cachedFile(_u(n)), isNotNull, reason: n);
      }
      expect(store.cachedFile(_u('b')), isNull);
      expect(attempts[_u('b')], 3); // 5xx keeps being retried
      // second pass fetches only the missing one
      behaviour.clear();
      requested.clear();
      expect(await svc.ensureVariantImages(data, 1), isTrue);
      expect(requested, [_u('b')]);
    });

    test('403 and other permanent 4xx are known-missing, not failures',
        () async {
      final data = _spec({'1': ['a', 'b', 'c']});
      behaviour[_u('a')] = (_) async => http.Response('', 403);
      behaviour[_u('b')] = (_) async => http.Response('', 401);
      behaviour[_u('c')] = (_) async => http.Response('', 404);
      expect(await svc.ensureVariantImages(data, 1), isTrue);
      expect(attempts.values.every((n) => n == 1), isTrue);
      expect(await svc.variantImagesComplete(data, 1), isTrue);
    });

    test('408 and 429 stay retryable failures', () async {
      final data = _spec({'1': ['a']});
      behaviour[_u('a')] = (_) async => http.Response('', 429);
      expect(await svc.ensureVariantImages(data, 1), isFalse);
      expect(attempts[_u('a')], 3);
    });
  });

  group('F9: the variant the engine renders', () {
    test('effectiveVariantKey mirrors TestSpec._fallbackVariant', () {
      final cases = <Map<String, dynamic>, List<int>>{
        {'1': 1, '2': 1, '3': 1}: [1, 2, 3, 4, 0, 99],
        {'1': 1, '5': 1}: [1, 2, 3, 4, 5, 6],
        {'A': 1, 'B': 1}: [1, 2, 7],
        {'A': 1, '3': 1, '10': 1}: [1, 3, 6, 7, 10, 12],
      };
      for (final e in cases.entries) {
        final blob = {
          'title': 't',
          'parts': ['Math'],
          'variants': {
            for (final k in e.key.keys)
              k: {
                'Math': [_q(_u('v$k'))]
              }
          },
        };
        final spec = TestSpec.fromJson(blob);
        for (final v in e.value) {
          final rendered = spec
              .sectionsForVariant(v.toString())
              .expand((s) => s.questions)
              .map((q) => q.img)
              .toSet();
          final gate = svc.variantImageUrls(blob, v).toSet();
          expect(gate, rendered,
              reason: 'variants ${e.key.keys} requested $v');
        }
      }
    });

    test('saved attempt on a missing variant key checks the fallback images',
        () async {
      final data = _spec({'1': ['a'], '2': ['b']});
      await svc.ensureVariantImages(data, 2);
      // variant 9 does not exist: the engine shows variant 2 (nearest).
      expect(await svc.variantImagesComplete(data, 9), isTrue);
      expect(await svc.variantImagesComplete(data, 1), isFalse);
    });
  });

  group('F10: new version drops the old images', () {
    test('old-spec images are evicted unless another test uses them',
        () async {
      api.tests['k'] = _spec({'1': ['own', 'shared']}, version: 1);
      api.tests['other'] = _spec({'1': ['shared']}, version: 1);
      expect(await svc.download('k'), isTrue);
      expect(await svc.download('other'), isTrue);
      await svc.backgroundPrefetch('k', api.tests['k']!);
      await svc.backgroundPrefetch('other', api.tests['other']!);
      expect(store.cachedFile(_u('own')), isNotNull);
      expect(store.cachedFile(_u('shared')), isNotNull);

      // v2 keeps the same URL for `own` (content may have changed there).
      api.tests['k'] = _spec({'1': ['own', 'new']}, version: 2);
      behaviour[_u('own')] = (_) async => http.Response.bytes([..._png, 7], 200);
      expect(await svc.download('k'), isTrue);
      await svc.backgroundJob('k');
      expect(store.cachedFile(_u('shared')), isNotNull); // other test's
      // fresh copy of `own` was fetched again, not the stale one
      expect(attempts[_u('own')], 2);
      expect(store.cachedFile(_u('new')), isNotNull);
    });

    test('same version re-download evicts nothing', () async {
      api.tests['k'] = _spec({'1': ['own']});
      await svc.download('k');
      await svc.backgroundJob('k');
      requested.clear();
      await svc.download('k');
      await svc.backgroundJob('k');
      expect(requested, isEmpty);
    });
  });

  group('F13: downloaded JSON is validated', () {
    test('invalid payloads never replace the cached copy', () async {
      api.tests['k'] = _spec({'1': ['a']}, version: 1);
      expect(await svc.download('k'), isTrue);
      final bad = <Map<String, dynamic>>[
        {'title': 'T', 'version': 2, 'parts': ['Math'], 'variants': {}},
        {'title': 'T', 'version': 2, 'variants': {'1': {'Math': []}}},
        {'title': 'T', 'version': 2, 'parts': [], 'variants': {'1': {'Math': [1]}}},
        {'detail': 'error page', 'version': 2},
        {'title': 'T', 'version': 2, 'parts': ['Math'], 'variants': {'1': {}}},
      ];
      for (final b in bad) {
        api.tests['k'] = b;
        expect(await svc.download('k'), isFalse, reason: '$b');
        expect(await TestCache.versionOf('k'), 1);
      }
    });

    test('test_data wrapper is accepted', () async {
      api.tests['k'] = {
        'title': 'T',
        'version': 1,
        'test_data': _spec({'1': ['a']}),
      };
      expect(await svc.download('k'), isTrue);
    });

    test('a cached row whose JSON cannot be read is notDownloaded', () async {
      // metadata row exists but the blob is gone (e.g. interrupted write)
      TestCache.exitMemoryMode();
      final path = '${dir.path}/tc.db';
      TestCache.pathOverride = path;
      addTearDown(TestCache.resetForTest);
      await TestCache.upsert('k', 'T', 1, 1, '{"a":1}');
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.update('cached_tests', {'json': '{broken'});
      await db.close();
      await TestCache.resetForTest();
      TestCache.pathOverride = path;

      api.catalog = [
        {'test_key': 'k', 'title': 'T', 'grade': 1, 'version': 1}
      ];
      final entries = await svc.refresh();
      expect(entries.single.status, CatalogStatus.notDownloaded);
    });
  });

  group('F21: background work and heal', () {
    test('prefetch waits while a test is running', () async {
      final data = _spec({'1': ['a', 'b']});
      var running = true;
      TestCatalogService.isTestRunning = () => running;
      final job = svc.backgroundPrefetch('k', data);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(requested, isEmpty);
      running = false;
      await job;
      expect(requested.toSet(), {_u('a'), _u('b')});
    });

    test('heal runs at most once per 10 minutes and never during a test',
        () async {
      api.tests['k'] = _spec({'1': ['a']});
      await svc.download('k');
      await svc.backgroundJob('k');
      var now = DateTime(2026, 10, 28, 9);
      TestCatalogService.clock = () => now;

      void wipe() {
        for (final f in Directory('${dir.path}/imgs').listSync()) {
          f.deleteSync();
        }
        requested.clear();
      }

      TestCatalogService.isTestRunning = () => true;
      wipe();
      await svc.healIncompleteTests(); // test running: skipped, not counted
      expect(requested, isEmpty);

      TestCatalogService.isTestRunning = () => false;
      await svc.healIncompleteTests();
      await svc.backgroundJob('k');
      expect(requested, [_u('a')]);

      wipe();
      now = now.add(const Duration(minutes: 5));
      await svc.healIncompleteTests();
      expect(requested, isEmpty); // throttled

      now = now.add(const Duration(minutes: 6));
      await svc.healIncompleteTests();
      await svc.backgroundJob('k');
      expect(requested, [_u('a')]);
    });
  });

  group('F12: corrupt cache DB', () {
    test('garbage file is moved aside, cache recreated empty, refresh never '
        'throws', () async {
      TestCache.exitMemoryMode();
      final path = '${dir.path}/test_cache.db';
      File(path).writeAsBytesSync(List.filled(4096, 0x41));
      TestCache.pathOverride = path;
      addTearDown(TestCache.resetForTest);

      api.catalog = [
        {'test_key': 'k', 'title': 'T', 'grade': 1, 'version': 1}
      ];
      final entries = await svc.refresh();
      expect(entries.single.status, CatalogStatus.notDownloaded);
      expect(
          dir
              .listSync()
              .any((e) => e.path.contains('test_cache.db.corrupt-')),
          isTrue);

      // and the fresh DB is fully usable
      api.tests['k'] = _spec({'1': ['a']});
      expect(await svc.download('k'), isTrue);
      expect(await TestCache.versionOf('k'), 1);
      expect(await TestCache.get('k'), isNotNull);
    });

    test('corrupt file is also recovered by reads and writes directly',
        () async {
      TestCache.exitMemoryMode();
      final path = '${dir.path}/c2.db';
      File(path).writeAsBytesSync(List.filled(2048, 0x42));
      TestCache.pathOverride = path;
      addTearDown(TestCache.resetForTest);
      await TestCache.upsert('x', 'T', 1, 3, '{"a":1}');
      expect(await TestCache.versionOf('x'), 3);
    });
  });
}
