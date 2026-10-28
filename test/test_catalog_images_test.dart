// Monitoring: test download = JSON only; at STUDENT selection only that
// student's variant images (+ shared ones) go into the persistent store
// (<support>/test_images/<sha256(url)>.img); survives relaunch, works offline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:crypto/crypto.dart';
import 'package:alochi_monitoring/core/cache/test_image_store.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/session/runner_dispatch.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/features/session/test_session.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RosterApi extends MonitoringApi {
  @override
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId) async => [
        {'id': 's1', 'student_code': 'S-1', 'name': 'Valiyev Ali'},
      ];
}

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

const cover = 'https://img.test/cover.png';

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

  // ---------------- background prefetch / heal / strictness ----------------

  TestCatalogService svcBg(TestImageStore store, _Api api) => TestCatalogService(
      api,
      store: store,
      retryDelay: Duration.zero,
      bgJitter: () => Duration.zero,
      bgBackoff: const [Duration.zero, Duration.zero, Duration.zero],
      bgYield: const Duration(milliseconds: 5));

  Future<(TestImageStore, TestCatalogService)> makeBg(
      Map<String, dynamic> data) async {
    final store = newStore();
    await store.init();
    return (store, svcBg(store, _Api([], {'k': data})));
  }

  List<String> allUrls(Map<String, dynamic> d) =>
      svcWith(newStore(), _Api([], {})).variantImageUrls(d, 1) +
      svcWith(newStore(), _Api([], {})).variantImageUrls(d, 2);

  test('background job downloads ALL variants, concurrency never above 2',
      () async {
    final data = _test(4);
    behaviour = {
      for (final u in allUrls(data).toSet())
        u: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 15));
          return http.Response.bytes([1, 2, 3], 200);
        }
    };
    final (store, svc) = await makeBg(data);
    await svc.backgroundPrefetch('k', data);
    for (final u in allUrls(data)) {
      expect(store.cachedFile(u), isNotNull, reason: u);
    }
    expect(maxInFlight, lessThanOrEqualTo(2));
    expect(maxInFlight, greaterThan(1));
    expect(requested.toSet().length, requested.length); // each url once
  });

  test('single-flight per testKey: a second call joins the running job',
      () async {
    final data = _test(2);
    final (_, svc) = await makeBg(data);
    final a = svc.backgroundPrefetch('k', data);
    final b = svc.backgroundPrefetch('k', data);
    expect(identical(a, b), isTrue);
    await a;
    expect(requested.toSet().length, requested.length);
  });

  test('foreground + background overlap: no URL is downloaded twice, '
      'foreground waits for the in-flight ones and is ready only when all '
      'are on disk', () async {
    final data = _test(3);
    final gate = Completer<void>();
    behaviour = {
      for (final u in allUrls(data).toSet())
        u: (_) async {
          await gate.future;
          return http.Response.bytes([1, 2, 3], 200);
        }
    };
    final (store, svc) = await makeBg(data);
    final bg = svc.backgroundPrefetch('k', data);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    var ready = false;
    final fg = svc.ensureVariantImages(data, 1).then((ok) {
      ready = ok;
      return ok;
    });
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(ready, isFalse); // (a)/(b): not ready while downloads are in flight
    expect(await svc.variantImagesComplete(data, 1), isFalse);
    gate.complete();
    expect(await fg, isTrue);
    expect(await svc.variantImagesComplete(data, 1), isTrue);
    await bg;
    expect(attempts.values.every((n) => n == 1), isTrue);
    expect(store.cachedFile(_u(200)), isNotNull);
  });

  test('(c) network failure after retries: variant never ready, retry works',
      () async {
    final data = _test(2);
    behaviour[_u(101)] = (_) async => throw const SocketException('down');
    final (_, svc) = await makeBg(data);
    expect(await svc.ensureVariantImages(data, 1), isFalse);
    expect(await svc.variantImagesComplete(data, 1), isFalse);
    behaviour.clear();
    expect(await svc.ensureVariantImages(data, 1), isTrue);
    expect(await svc.variantImagesComplete(data, 1), isTrue);
  });

  test('background retries with backoff, then succeeds; gives up quietly',
      () async {
    final data = _test(1, variants: 1);
    behaviour[_u(100)] = (n) async => n < 3
        ? throw const SocketException('flaky')
        : http.Response.bytes([7], 200);
    final (store, svc) = await makeBg(data);
    await svc.backgroundPrefetch('k', data);
    expect(attempts[_u(100)], 3);
    expect(store.cachedFile(_u(100)), isNotNull);

    final d2 = _test(1, variants: 1)..['cover'] = 'https://img.test/c2.png';
    behaviour['https://img.test/c2.png'] =
        (_) async => throw const SocketException('dead');
    await svc.backgroundPrefetch('k2', d2); // must not throw
    expect(attempts['https://img.test/c2.png'], 4); // 1 + 3 backoff steps
    expect(store.cachedFile('https://img.test/c2.png'), isNull);
  });

  test('background: 404 skipped and remembered', () async {
    final data = _test(2, variants: 1);
    behaviour[_u(101)] = (_) async => http.Response('', 404);
    final (_, svc) = await makeBg(data);
    await svc.backgroundPrefetch('k', data);
    expect(await svc.variantImagesComplete(data, 1), isTrue);
    expect(attempts[_u(101)], 1);
  });

  test('resume after relaunch fetches only the missing files', () async {
    final data = _test(3);
    final (_, svc) = await makeBg(data);
    await svc.ensureVariantImages(data, 1);
    requested.clear();
    final store2 = newStore(); // relaunch
    await store2.init();
    final svc2 = svcBg(store2, _Api([], {'k': data}));
    await svc2.backgroundPrefetch('k', data);
    expect(requested.toSet(), {_u(200), _u(201), _u(202)});
  });

  test('init removes leftover partial files; zero-byte/truncated never counts',
      () async {
    final root = Directory('${dir.path}/test_images')..createSync();
    final old = DateTime.now().subtract(const Duration(minutes: 10));
    final part = File('${root.path}/abc.part')..writeAsBytesSync([1]);
    final tmp = File('${root.path}/${'a' * 64}.img.1.tmp')
      ..writeAsBytesSync([1]);
    final fresh = File('${root.path}/zzz.tmp')..writeAsBytesSync([1]);
    part.setLastModifiedSync(old);
    tmp.setLastModifiedSync(old);
    final url = _u(1);
    final name = sha256.convert(utf8.encode(url)).toString();
    File('${root.path}/$name.img').writeAsBytesSync([]); // zero byte
    final store = newStore();
    expect(store.cachedFile(url), isNull);
    await store.init();
    expect(part.existsSync(), isFalse);
    expect(tmp.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue); // young temp may be a live write
    expect(File('${root.path}/$name.img').existsSync(), isFalse);
    expect(store.cachedFile(url), isNull);
  });

  test('truncated body (Content-Length mismatch) is never stored', () async {
    final data = _test(1, variants: 1);
    final store = TestImageStore(
        root: Directory('${dir.path}/test_images'),
        client: MockClient.streaming((req, _) async => http.StreamedResponse(
            Stream.value([1, 2, 3]), 200,
            contentLength: 10)),
        timeout: const Duration(seconds: 2));
    await store.init();
    final svc = svcBg(store, _Api([], {'k': data}));
    expect(await svc.ensureVariantImages(data, 1), isFalse);
    expect(store.cachedFile(_u(100)), isNull);
  });

  test('refresh() heals incomplete cached tests in the background', () async {
    final data = _test(2);
    final store = newStore();
    await store.init();
    final api = _Api([
      {'test_key': 'k', 'title': 'T', 'grade': 5, 'version': 1}
    ], {
      'k': data
    });
    final svc = svcBg(store, api);
    await TestCache.upsert('k', 'T', 5, 1, jsonEncode(data)); // JSON only
    await svc.refresh();
    for (var i = 0; i < 100; i++) {
      if (await svc.variantImagesComplete(data, 1) &&
          await svc.variantImagesComplete(data, 2)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    for (final u in allUrls(data)) {
      expect(store.cachedFile(u), isNotNull, reason: u);
    }
  });

  test('download() returns before the background job finishes', () async {
    final data = _test(2);
    final gate = Completer<void>();
    behaviour = {
      for (final u in allUrls(data).toSet())
        u: (_) async {
          await gate.future;
          return http.Response.bytes([1], 200);
        }
    };
    final store = newStore();
    await store.init();
    final svc = svcBg(store, _Api([], {'k': data}));
    expect(await svc.download('k'), isTrue); // returns while gated
    expect(store.cachedFile(_u(100)), isNull);
    gate.complete();
    await svc.backgroundPrefetch('k', data); // joins the running job
    expect(store.cachedFile(_u(100)), isNotNull);
  });

  testWidgets('(d) launchRunner refuses when one image is missing and never '
      'downloads', (tester) async {
    final data = _test(2, variants: 1);
    final store = newStore();
    // real file I/O must not run inside the testWidgets FakeAsync zone
    await tester.runAsync(() async {
      await store.init();
      await store.fetch(_u(100)); // cover + _u(101) stay missing
      await TestCache.upsert('mon:t', 'T', 5, 1, jsonEncode(data));
    });
    requested.clear();
    TestImageStore.instanceForTest = store;

    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      }),
    ));
    await tester.runAsync(() => launchRunner(
          ctx,
          session: const TestSession(
            testKey: 'mon:t',
            title: 'T',
            runnerType: 'engine',
            schoolCode: '1',
            schoolLabel: '1',
            testGrade: 5,
          ),
          firstName: 'A',
          lastName: 'B',
          studentGrade: 5,
          studentId: 'S-9',
        ));
    await tester.pump();
    final l10n = AppLocalizations.of(ctx)!;
    expect(find.text(l10n.testNotInCache), findsOneWidget);
    expect(requested, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    TestImageStore.instanceForTest = TestImageStore();
  });

  group('(a)/(c) student_entry Start button', () {
    Future<void> openRoster(WidgetTester tester, TestImageStore store) async {
      final data = _test(2, variants: 1);
      await tester.runAsync(() async {
        await store.init();
        await TestCache.upsert('mon:t', 'T', 5, 1, jsonEncode(data));
      });
      TestImageStore.instanceForTest = store;
      final saved = api;
      api = _RosterApi();
      addTearDown(() {
        api = saved;
        TestImageStore.instanceForTest = TestImageStore();
      });
      // ignore: prefer_const_constructors
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const StudentEntryScreen(
          session: TestSession(
            testKey: 'mon:t',
            title: 'T',
            runnerType: 'engine',
            schoolCode: '1',
            schoolLabel: '1',
            testGrade: 5,
          ),
          preselectedGroup: {'id': 'g1', 'name': '5-A'},
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    InkWell startButton(WidgetTester tester) => tester.widget<InkWell>(
        find.byWidgetPredicate(
            (w) => w is InkWell && w.borderRadius == BorderRadius.circular(30)));

    testWidgets('disabled while any image is missing/in flight; enabled only '
        'when 100% on disk', (tester) async {
      final gate = Completer<void>();
      behaviour = {
        for (final u in [cover, _u(100), _u(101)])
          u: (_) async {
            await gate.future;
            return http.Response.bytes([1], 200);
          }
      };
      await openRoster(tester, newStore());
      await tester.tap(find.textContaining('Ali'));
      await settle(tester);
      expect(startButton(tester).onTap, isNull); // downloading, gated
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      expect(find.textContaining(l10n.downloading), findsOneWidget);

      gate.complete();
      for (var i = 0; i < 20 && startButton(tester).onTap == null; i++) {
        await settle(tester);
      }
      expect(startButton(tester).onTap, isNotNull); // everything on disk
    });

    testWidgets('network failure: stays blocked with downloadError toast; '
        're-tapping the student retries', (tester) async {
      var failing = true;
      behaviour = {
        for (final u in [cover, _u(100), _u(101)])
          u: (_) async => failing
              ? throw const SocketException('down')
              : http.Response.bytes([1], 200)
      };
      await openRoster(tester, newStore());
      await tester.tap(find.textContaining('Ali'));
      final l10n0 = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      for (var i = 0; i < 30 && find.text(l10n0.downloadError).evaluate().isEmpty; i++) {
        await settle(tester);
      }
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      expect(startButton(tester).onTap, isNull);
      expect(find.text(l10n.downloadError), findsOneWidget);

      failing = false;
      await tester.pump(const Duration(seconds: 5)); // toast gone
      await tester.tap(find.textContaining('Ali'));
      for (var i = 0; i < 20 && startButton(tester).onTap == null; i++) {
        await settle(tester);
      }
      expect(startButton(tester).onTap, isNotNull);
    });
  });
}
