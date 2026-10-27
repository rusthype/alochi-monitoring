// Monitoring: test download = JSON only; at STUDENT selection only that
// student's variant images (+ shared ones) go into the persistent store
// (<support>/test_images/<sha256(url)>.img); survives relaunch, works offline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/cache/test_image_store.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/session/runner_dispatch.dart';
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

/// Variant `v` owns images q{v*100 + i}; `cover` is shared by every variant.
Map<String, dynamic> _test(int n, {int version = 1, int variants = 2}) => {
      'title': 'T',
      'grade': 5,
      'version': version,
      'cover': 'https://img.test/cover.png',
      'variants': {
        for (var v = 1; v <= variants; v++)
          '$v': {
            'Math': [
              for (var i = 0; i < n; i++) {'image_url': _u(v * 100 + i)},
            ],
          },
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

  String cover = 'https://img.test/cover.png';

  test('only the chosen variant + shared images are requested', () async {
    final data = _test(3);
    final (store, svc) = await make(data);
    expect(svc.variantImageUrls(data, 2).toSet(),
        {cover, _u(200), _u(201), _u(202)});
    expect(await svc.ensureVariantImages(data, 2), isTrue);
    expect(requested.toSet(), {cover, _u(200), _u(201), _u(202)});
    expect(requested.any((u) => u.contains('/q10')), isFalse); // variant 1
    expect(await svc.variantImagesComplete(data, 2), isTrue);
    expect(await svc.variantImagesComplete(data, 1), isFalse);
    expect(store.cachedFile(_u(100)), isNull);
  });

  test('test_data wrapper and no-variants tests: everything is shared',
      () async {
    final (_, svc) = await make({});
    final wrapped = {'test_data': _test(2)};
    expect(svc.variantImageUrls(wrapped, 1).toSet(),
        {cover, _u(100), _u(101)});
    final flat = {
      'a': {'image_url': _u(1)},
      'b': [_u(2)],
    };
    expect(svc.variantImageUrls(flat, 7).toSet(), {_u(1), _u(2)});
  });

  test('download() is JSON only: no image request, status stays cached',
      () async {
    final store = newStore();
    await store.init();
    final api = _Api([
      {'test_key': 'k', 'title': 'T', 'grade': 5, 'version': 1}
    ], {
      'k': _test(3)
    });
    final svc = svcWith(store, api);
    expect(await svc.download('k'), isTrue);
    expect(requested, isEmpty);
    expect((await svc.refresh()).single.status, CatalogStatus.cached);
  });

  test('variant download completes only after all images, bounded parallel',
      () async {
    final data = _test(10);
    final urls = svcWith(newStore(), _Api([], {})).variantImageUrls(data, 1);
    final gates = {for (final u in urls) u: Completer<void>()};
    for (final e in gates.entries) {
      behaviour[e.key] = (_) async {
        await e.value.future;
        return http.Response.bytes([1, 2, 3], 200);
      };
    }
    final (_, svc) = await make(data);
    var finished = false;
    final f = svc.ensureVariantImages(data, 1).then((ok) {
      finished = true;
      return ok;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(finished, isFalse);
    expect(maxInFlight, lessThanOrEqualTo(4));
    expect(maxInFlight, greaterThan(1));
    for (final u in urls) {
      expect(finished, isFalse);
      gates[u]!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await f, isTrue);
  });

  test('404/410 skipped (counted done), rest stored, no retry for 404',
      () async {
    behaviour[_u(101)] = (_) async => http.Response('', 404);
    behaviour[_u(102)] = (_) async => http.Response('', 410);
    final data = _test(4);
    final (store, svc) = await make(data);
    expect(await svc.ensureVariantImages(data, 1), isTrue);
    expect(store.cachedFile(_u(100)), isNotNull);
    expect(store.cachedFile(_u(101)), isNull);
    expect(store.cachedFile(_u(103)), isNotNull);
    expect(attempts[_u(101)], 1);
    expect(await svc.variantImagesComplete(data, 1), isTrue);
  });

  test('network failure after retries -> false; not complete; retry works',
      () async {
    behaviour[_u(101)] = (_) async => throw const SocketException('down');
    final data = _test(3);
    final (_, svc) = await make(data);
    expect(await svc.ensureVariantImages(data, 1), isFalse);
    expect(attempts[_u(101)], 3);
    expect(await svc.variantImagesComplete(data, 1), isFalse);

    behaviour.clear(); // network back
    requested.clear();
    expect(await svc.ensureVariantImages(data, 1), isTrue);
    expect(requested.contains(_u(101)), isTrue);
    expect(requested.contains(_u(100)), isFalse); // already stored
  });

  test('transient failure recovers; 5xx is a failure not a skip', () async {
    behaviour[_u(100)] = (n) async => n < 3
        ? throw TimeoutException('slow')
        : http.Response.bytes([9], 200);
    final data = _test(1);
    final (_, svc) = await make(data);
    expect(await svc.ensureVariantImages(data, 1), isTrue);

    behaviour[_u(200)] = (_) async => http.Response('busy', 503);
    expect(await svc.ensureVariantImages(data, 2), isFalse);
  });

  test('empty or truncated body is never stored', () async {
    behaviour[_u(100)] = (_) async => http.Response.bytes([], 200);
    final data = _test(1);
    final (store, svc) = await make(data);
    expect(await svc.ensureVariantImages(data, 1), isFalse);
    expect(store.cachedFile(_u(100)), isNull);
    expect(
        Directory('${dir.path}/test_images')
            .listSync()
            .any((f) => f.path.endsWith('.tmp')),
        isFalse);
  });

  test('relaunch: new store over same dir sees everything, zero network; '
      're-selecting a student reuses stored images', () async {
    final data = _test(3);
    final (_, svc) = await make(data);
    expect(await svc.ensureVariantImages(data, 1), isTrue);
    final before = requested.length;
    expect(await svc.ensureVariantImages(data, 1), isTrue); // re-select
    expect(requested.length, before);

    final store2 = newStore(); // "relaunch"
    await store2.init();
    final svc2 = svcWith(store2, _Api([], {}));
    expect(await svc2.variantImagesComplete(data, 1), isTrue);
    expect(await svc2.ensureVariantImages(data, 1), isTrue);
    expect(requested.length, before);
  });

  test('progress callback counts done/total', () async {
    behaviour[_u(102)] = (_) async => http.Response('', 404);
    final data = _test(4); // variant 1: 4 + cover = 5 urls
    final (store, svc) = await make(data);
    await store.fetch(_u(100));
    final seen = <String>[];
    expect(
        await svc.ensureVariantImages(data, 1,
            onProgress: (d, t) => seen.add('$d/$t')),
        isTrue);
    expect(seen.first, '1/5');
    expect(seen.last, '5/5');
    expect(seen.length, 5);
  });

  test('offline: previously-404 image does not block, a real miss does',
      () async {
    behaviour[_u(101)] = (_) async => http.Response('', 404);
    final data = _test(2);
    final (store, svc) = await make(data);
    expect(await svc.ensureVariantImages(data, 1), isTrue); // learns u101=404

    behaviour[_u(101)] = (_) async => throw const SocketException('off');
    expect(await svc.ensureVariantImages(data, 1), isTrue);

    for (final f in Directory('${dir.path}/test_images').listSync()) {
      f.deleteSync();
    }
    behaviour[_u(100)] = (_) async => throw const SocketException('off');
    expect(store.cachedFile(_u(100)), isNull);
    expect(await svc.ensureVariantImages(data, 1), isFalse); // no variant swap
  });

  test('prepared variant == launched variant (random draw is not repeated)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final data = _test(2, variants: 6);
    // Student has no saved attempt: preview draws, caller remembers the draw.
    final drawn = await previewAttemptVariant(data,
        testKey: 'nosave_test', studentId: 'S-1');
    // launchRunner passes it back as `drawn`: same variant, never re-drawn.
    for (var i = 0; i < 20; i++) {
      expect(
          await previewAttemptVariant(data,
              testKey: 'nosave_test', studentId: 'S-1', drawn: drawn),
          drawn);
    }
    // resolve (the persisting step) honours the prepared variant.
    expect(
        await resolveAttemptVariant(data,
            testKey: 'nosave_test',
            firstName: 'A',
            lastName: 'B',
            studentId: 'S-1',
            groupName: 'g',
            preferredVariant: drawn),
        drawn);
    // Now the attempt is saved: preview == resume, whatever `drawn` says.
    expect(
        await previewAttemptVariant(data,
            testKey: 'nosave_test',
            studentId: 'S-1',
            drawn: drawn == 1 ? 2 : 1),
        drawn);
  });

  test('gc: keeps every URL of any cached test (all variants), removes the '
      'rest; no half files counted', () async {
    final data = _test(2);
    final (store, svc) = await make(data);
    await TestCache.upsert('k', 'T', 5, 1, jsonEncode(data));
    expect(await svc.ensureVariantImages(data, 1), isTrue);
    await store.fetch(_u(200)); // other variant of the SAME cached test
    await store.fetch('https://img.test/old.png'); // unreferenced
    final root = Directory('${dir.path}/test_images');
    File('${root.path}/abc.img.123.tmp').writeAsBytesSync([1]);
    expect(store.cachedFile('https://img.test/abc'), isNull); // tmp != image

    await svc.gcStore(); // grace period: nothing removed
    expect(root.listSync().length, 6); // cover, 2 v1, v2 one, old, tmp
    final old = DateTime.now().subtract(const Duration(days: 3));
    for (final f in root.listSync().whereType<File>()) {
      f.setLastModifiedSync(old);
    }
    await svc.gcStore();
    expect(store.cachedFile(_u(100)), isNotNull);
    expect(store.cachedFile(_u(200)), isNotNull); // kept: in cached JSON
    expect(store.cachedFile('https://img.test/old.png'), isNull);
    expect(root.listSync().length, 4);

    await TestCache.pruneNotIn({}); // test removed from catalog
    for (final f in root.listSync().whereType<File>()) {
      f.setLastModifiedSync(old);
    }
    await svc.gcStore();
    expect(root.listSync(), isEmpty);
  });
}
