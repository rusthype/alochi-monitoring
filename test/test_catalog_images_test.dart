// Monitoring test download: JSON + every question image in the persistent
// test-image store (<support>/test_images/<sha256(url)>.img). "Downloaded"
// means all of it is on disk; no student-start download; survives relaunch.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/cache/test_image_store.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends MonitoringApi {
  _Api(this.catalog, this.tests);
  List<Map<String, dynamic>> catalog;
  final Map<String, Map<String, dynamic>> tests;
  @override
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
          {String? authToken,
              String? groupId,
              String? schoolCode,
              String? schoolId}) async =>
      catalog;
  @override
  Future<Map<String, dynamic>?> fetchTest(String testKey,
          {String? groupId,
          String? schoolCode,
          String? schoolId,
          String? authToken}) async =>
      tests[testKey];
}

String _u(int i) => 'https://img.test/q$i.png';

Map<String, dynamic> _test(int n, {int version = 1, int offset = 0}) => {
      'title': 'T',
      'grade': 5,
      'version': version,
      'variants': {
        '1': [
          for (var i = 0; i < n; i++) {'image_url': _u(i + offset)},
        ],
      },
    };

void main() {
  late Directory dir;
  late List<String> requested;
  late int inFlight;
  late int maxInFlight;
  // url -> handler; default 200 with body.
  late Map<String, Future<http.Response> Function(int attempt)> behaviour;
  late Map<String, int> attempts;

  MockClient client() => MockClient((req) async {
        final url = req.url.toString();
        requested.add(url);
        final n = attempts[url] = (attempts[url] ?? 0) + 1;
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        try {
          final h = behaviour[url];
          if (h != null) return await h(n);
          return http.Response.bytes(utf8.encode('IMG$url'), 200);
        } finally {
          inFlight--;
        }
      });

  TestImageStore newStore() => TestImageStore(
      root: Directory('${dir.path}/test_images'),
      client: client(),
      timeout: const Duration(seconds: 2));

  TestCatalogService svcWith(TestImageStore store, _Api api) =>
      TestCatalogService(api, store: store, retryDelay: Duration.zero);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestCatalogService.resetKnownMissingForTest();
    TestCache.enterMemoryMode();
    dir = Directory.systemTemp.createTempSync('tis_');
    requested = [];
    inFlight = 0;
    maxInFlight = 0;
    behaviour = {};
    attempts = {};
  });
  tearDown(() {
    TestCache.exitMemoryMode();
    dir.deleteSync(recursive: true);
  });

  Future<(TestImageStore, TestCatalogService)> make(
      Map<String, dynamic> data) async {
    final store = newStore();
    await store.init();
    return (store, svcWith(store, _Api([], {'k': data})));
  }

  test('download completes only after all images are stored, bounded parallel',
      () async {
    final gates = {for (var i = 0; i < 10; i++) _u(i): Completer<void>()};
    for (final e in gates.entries) {
      behaviour[e.key] = (_) async {
        await e.value.future;
        return http.Response.bytes([1, 2, 3], 200);
      };
    }
    final (_, svc) = await make(_test(10));
    var finished = false;
    final f = svc.download('k').then((ok) {
      finished = true;
      return ok;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(finished, isFalse);
    expect(maxInFlight, lessThanOrEqualTo(4));
    expect(maxInFlight, greaterThan(1));
    for (var i = 0; i < 10; i++) {
      expect(finished, isFalse);
      gates[_u(i)]!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await f, isTrue);
    expect(await svc.isTestReady('k'), isTrue);
  });

  test('404/410 skipped (counted done), rest stored, no retry for 404',
      () async {
    behaviour[_u(1)] = (_) async => http.Response('', 404);
    behaviour[_u(2)] = (_) async => http.Response('', 410);
    final (store, svc) = await make(_test(4));
    expect(await svc.download('k'), isTrue);
    expect(store.cachedFile(_u(0)), isNotNull);
    expect(store.cachedFile(_u(1)), isNull);
    expect(store.cachedFile(_u(3)), isNotNull);
    expect(attempts[_u(1)], 1);
    expect(await svc.isTestReady('k'), isTrue); // 404s count as done
  });

  test('network failure after retries -> false, JSON cached, not ready',
      () async {
    behaviour[_u(1)] = (_) async => throw const SocketException('down');
    final (_, svc) = await make(_test(3));
    expect(await svc.download('k'), isFalse);
    expect(attempts[_u(1)], 3);
    expect(await TestCache.get('k'), isNotNull);
    expect(await svc.isTestReady('k'), isFalse);
  });

  test('transient failure recovers; 5xx is a failure not a skip', () async {
    behaviour[_u(0)] = (n) async => n < 3
        ? throw TimeoutException('slow')
        : http.Response.bytes([9], 200);
    final (_, svc) = await make(_test(1));
    expect(await svc.download('k'), isTrue);

    behaviour[_u(5)] = (_) async => http.Response('busy', 503);
    final (_, svc2) = await make(_test(1, offset: 5));
    expect(await svc2.download('k'), isFalse);
  });

  test('empty or truncated body is never stored', () async {
    behaviour[_u(0)] = (_) async => http.Response.bytes([], 200);
    final (store, svc) = await make(_test(1));
    expect(await svc.download('k'), isFalse);
    expect(store.cachedFile(_u(0)), isNull);
    expect(Directory('${dir.path}/test_images').listSync(), isEmpty);
  });

  test('relaunch: new store over same dir sees everything, zero network',
      () async {
    final (_, svc) = await make(_test(3));
    expect(await svc.download('k'), isTrue);
    final before = requested.length;

    // "relaunch": brand-new store + service instances over the same folder.
    final store2 = newStore();
    await store2.init();
    final svc2 = svcWith(store2, _Api([], {'k': _test(3)}));
    expect(await svc2.isTestReady('k'), isTrue);
    expect(await svc2.ensureImagesCached(_test(3)), isTrue);
    expect(requested.length, before);
  });

  test('partial test is not ready; retry fetches only the missing images',
      () async {
    final (store, svc) = await make(_test(3));
    await store.fetch(_u(0)); // e.g. an older build got only one image
    await TestCache.upsert('k', 'T', 5, 1, jsonEncode(_test(3)));
    expect(await svc.isTestReady('k'), isFalse);
    requested.clear();
    expect(await svc.ensureImagesCached(_test(3)), isTrue);
    expect(requested.toSet(), {_u(1), _u(2)});
    expect(await svc.isTestReady('k'), isTrue);
  });

  test('progress callback counts done/total', () async {
    behaviour[_u(2)] = (_) async => http.Response('', 404);
    final (store, svc) = await make(_test(4));
    await store.fetch(_u(0));
    final seen = <String>[];
    expect(await svc.download('k', onProgress: (d, t) => seen.add('$d/$t')),
        isTrue);
    expect(seen.first, '1/4');
    expect(seen.last, '4/4');
    expect(seen.length, 4);
  });

  test('offline: previously-404 image does not block, a real miss does',
      () async {
    behaviour[_u(1)] = (_) async => http.Response('', 404);
    final (store, svc) = await make(_test(2));
    expect(await svc.ensureImagesCached(_test(2)), isTrue); // learns u1 = 404

    behaviour[_u(1)] = (_) async => throw const SocketException('off');
    expect(await svc.ensureImagesCached(_test(2)), isTrue);

    // wipe the store: u0 now truly missing while offline -> blocks
    for (final f in Directory('${dir.path}/test_images').listSync()) {
      f.deleteSync();
    }
    behaviour[_u(0)] = (_) async => throw const SocketException('off');
    expect(store.cachedFile(_u(0)), isNull);
    expect(await svc.ensureImagesCached(_test(2)), isFalse);
  });

  test('catalog status: JSON-only (old build) shows notDownloaded, '
      'complete shows cached', () async {
    final store = newStore();
    await store.init();
    final api = _Api([
      {'test_key': 'k', 'title': 'T', 'grade': 5, 'version': 1}
    ], {
      'k': _test(3)
    });
    final svc = svcWith(store, api);
    // old build: JSON cached, one image only
    await TestCache.upsert('k', 'T', 5, 1, jsonEncode(_test(3)));
    await store.fetch(_u(0));
    var entries = await svc.refresh();
    expect(entries.single.status, CatalogStatus.notDownloaded);

    expect(await svc.download('k'), isTrue);
    entries = await svc.refresh();
    expect(entries.single.status, CatalogStatus.cached);
  });

  test('gc after prune: unreferenced files deleted, referenced kept; '
      'no half files counted', () async {
    final (store, svc) = await make(_test(2));
    expect(await svc.download('k'), isTrue);
    // an image of a test that no longer exists + a leftover temp file
    await store.fetch('https://img.test/old.png');
    final root = Directory('${dir.path}/test_images');
    File('${root.path}/abc.img.123.tmp').writeAsBytesSync([1]);
    expect(store.cachedFile('https://img.test/abc'), isNull); // tmp != image
    // still inside the grace period: nothing is removed
    await svc.gcStore();
    expect(root.listSync().length, 4);
    // age everything, then GC
    final old = DateTime.now().subtract(const Duration(days: 3));
    for (final f in root.listSync().whereType<File>()) {
      f.setLastModifiedSync(old);
    }
    await svc.gcStore();
    expect(store.cachedFile(_u(0)), isNotNull);
    expect(store.cachedFile(_u(1)), isNotNull);
    expect(store.cachedFile('https://img.test/old.png'), isNull);
    expect(root.listSync().length, 2);

    // test removed from catalog -> prune + GC drops its images too
    await TestCache.pruneNotIn({});
    for (final f in root.listSync().whereType<File>()) {
      f.setLastModifiedSync(old);
    }
    await svc.gcStore();
    expect(root.listSync(), isEmpty);
  });
}
