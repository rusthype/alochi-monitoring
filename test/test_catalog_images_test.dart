// Monitoring test download must be fully awaited: JSON + every question image
// on disk before it reports success (no in-test spinners, works offline).
import 'dart:async';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:file/local.dart';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends MonitoringApi {
  _Api(this.data);
  final Map<String, dynamic> data;
  @override
  Future<Map<String, dynamic>?> fetchTest(String testKey,
          {String? groupId,
          String? schoolCode,
          String? schoolId,
          String? authToken}) async =>
      data;
}

class _FakeCache extends Fake implements BaseCacheManager {
  final Set<String> cached = {};
  final List<String> downloadCalls = [];
  int inFlight = 0;
  int maxInFlight = 0;

  /// Per-url behaviour; default = success.
  final Map<String, Future<void> Function(int attempt)> behaviour = {};
  final Map<String, int> attempts = {};

  @override
  Future<FileInfo?> getFileFromCache(String key,
      {bool ignoreMemCache = false}) async {
    if (!cached.contains(key)) return null;
    return FileInfo(const LocalFileSystem().file('/tmp/x'), FileSource.Cache,
        DateTime.now().add(const Duration(days: 1)), key);
  }

  @override
  Future<FileInfo> downloadFile(String url,
      {String? key,
      Map<String, String>? authHeaders,
      bool force = false}) async {
    downloadCalls.add(url);
    final n = attempts[url] = (attempts[url] ?? 0) + 1;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await (behaviour[url]?.call(n) ?? Future<void>.value());
    } finally {
      inFlight--;
    }
    cached.add(url);
    return FileInfo(const LocalFileSystem().file('/tmp/x'), FileSource.Online,
        DateTime.now().add(const Duration(days: 1)), url);
  }
}

String _u(int i) => 'https://img.test/q$i.png';

Map<String, dynamic> _test(int n) => {
      'title': 'T',
      'grade': 5,
      'version': 1,
      'variants': {
        '1': [
          for (var i = 0; i < n; i++) {'image_url': _u(i)},
        ],
      },
    };

void main() {
  late _FakeCache cache;

  TestCatalogService svc(Map<String, dynamic> data) => TestCatalogService(
      _Api(data),
      cacheManager: cache,
      retryDelay: Duration.zero);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestCatalogService.resetKnownMissingForTest();
    TestCache.enterMemoryMode();
    cache = _FakeCache();
  });
  tearDown(TestCache.exitMemoryMode);

  test('download completes only after all images are fetched, bounded parallel',
      () async {
    final gates = {for (var i = 0; i < 10; i++) _u(i): Completer<void>()};
    for (final e in gates.entries) {
      cache.behaviour[e.key] = (_) => e.value.future;
    }
    var finished = false;
    final f = svc(_test(10)).download('k').then((ok) {
      finished = true;
      return ok;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(finished, isFalse);
    expect(cache.maxInFlight, lessThanOrEqualTo(4));
    expect(cache.maxInFlight, greaterThan(1));
    // release in a trickle; must not finish until the last one.
    for (var i = 0; i < 10; i++) {
      expect(finished, isFalse);
      gates[_u(i)]!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await f, isTrue);
    expect(cache.cached.length, 10);
    expect(await TestCache.get('k'), isNotNull);
  });

  test('404/410 image is skipped, the rest are cached, result true', () async {
    cache.behaviour[_u(1)] = (_) async =>
        throw const HttpExceptionWithStatus(404, 'nf');
    cache.behaviour[_u(2)] = (_) async =>
        throw const HttpExceptionWithStatus(410, 'gone');
    final ok = await svc(_test(4)).download('k');
    expect(ok, isTrue);
    expect(cache.cached, {_u(0), _u(3)});
    // no retries for 404
    expect(cache.attempts[_u(1)], 1);
  });

  test('network failure after retries -> false, JSON stays cached', () async {
    cache.behaviour[_u(1)] = (_) async => throw const SocketException('down');
    final ok = await svc(_test(3)).download('k');
    expect(ok, isFalse);
    expect(cache.attempts[_u(1)], 3); // 1 try + 2 retries
    expect(await TestCache.get('k'), isNotNull);
  });

  test('transient failure recovers within the retry budget', () async {
    cache.behaviour[_u(0)] = (n) async {
      if (n < 3) throw TimeoutException('slow');
    };
    expect(await svc(_test(2)).download('k'), isTrue);
    expect(cache.attempts[_u(0)], 3);
  });

  test('5xx counts as network failure (not skipped)', () async {
    cache.behaviour[_u(0)] = (_) async =>
        throw const HttpExceptionWithStatus(503, 'busy');
    expect(await svc(_test(1)).download('k'), isFalse);
  });

  test('already cached -> no network calls at all', () async {
    cache.cached.addAll([_u(0), _u(1), _u(2)]);
    final s = svc(_test(3));
    expect(await s.ensureImagesCached(_test(3)), isTrue);
    expect(cache.downloadCalls, isEmpty);
  });

  test('only missing images are fetched on retry', () async {
    cache.cached.add(_u(0));
    expect(await svc(_test(3)).ensureImagesCached(_test(3)), isTrue);
    expect(cache.downloadCalls.toSet(), {_u(1), _u(2)});
  });

  test('progress callback counts done/total up to total', () async {
    cache.cached.add(_u(0));
    cache.behaviour[_u(2)] = (_) async =>
        throw const HttpExceptionWithStatus(404, 'nf');
    final seen = <String>[];
    final ok = await svc(_test(4)).download('k',
        onProgress: (d, t) => seen.add('$d/$t'));
    expect(ok, isTrue);
    expect(seen.first, '1/4'); // initial: 1 already cached
    expect(seen.last, '4/4'); // 404 counts as handled
    expect(seen.length, 4); // initial + 3 downloads handled
  });

  test('offline: previously-404 image does not block, real missing does',
      () async {
    final s = svc(_test(2));
    cache.behaviour[_u(1)] = (_) async =>
        throw const HttpExceptionWithStatus(404, 'nf');
    expect(await s.ensureImagesCached(_test(2)), isTrue); // learns u1 missing

    // now offline
    cache.behaviour[_u(1)] = (_) async => throw const SocketException('off');
    expect(await s.ensureImagesCached(_test(2)), isTrue);

    // a different, never-seen image missing while offline -> blocks
    cache.cached.clear();
    cache.behaviour[_u(0)] = (_) async => throw const SocketException('off');
    expect(await s.ensureImagesCached(_test(2)), isFalse);
  });
}
