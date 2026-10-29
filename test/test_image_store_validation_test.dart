// TestImageStore must never keep a non-image body (captive-portal HTML, proxy
// error page) under a final `<sha256>.img` name, and a download is bounded by
// a per-chunk IDLE timeout (slow-but-alive links finish) plus a hard ceiling.
import 'dart:async';
import 'dart:io';

import 'package:alochi_monitoring/core/cache/test_image_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];
const _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46];
const _gif = <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 0, 1, 0];
const _webp = <int>[
  0x52, 0x49, 0x46, 0x46, 4, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50
];
List<int> _s(String s) => s.codeUnits;

void main() {
  late Directory dir;
  const url = 'https://img.test/a.png';

  setUp(() => dir = Directory.systemTemp.createTempSync('tis_val_'));
  tearDown(() => dir.deleteSync(recursive: true));

  TestImageStore store(http.Client c,
          {Duration idle = const Duration(seconds: 2),
          Duration max = const Duration(minutes: 3)}) =>
      TestImageStore(
          root: Directory('${dir.path}/imgs'),
          client: c,
          timeout: idle,
          maxDuration: max);

  MockClient bodyClient(List<int> body, {Map<String, String>? headers}) =>
      MockClient((_) async => http.Response.bytes(body, 200,
          headers: headers ?? const {}));

  List<String> files() => Directory('${dir.path}/imgs')
      .listSync()
      .map((e) => e.path.split('/').last)
      .toList();

  group('magic bytes', () {
    test('captive-portal HTML is rejected, nothing is left behind', () async {
      final s = store(bodyClient(_s('<html><body>wifi login</body></html>'),
          headers: {'content-type': 'text/html'}));
      await s.init();
      await expectLater(s.fetch(url), throwsA(isA<HttpException>()));
      expect(s.cachedFile(url), isNull);
      expect(files(), isEmpty);
    });

    test('JSON error body with 200 is rejected', () async {
      final s = store(bodyClient(_s('{"detail":"nope"}')));
      await s.init();
      await expectLater(s.fetch(url), throwsA(isA<HttpException>()));
      expect(files(), isEmpty);
    });

    for (final e in {
      'png': _png,
      'jpeg': _jpeg,
      'gif': _gif,
      'webp': _webp,
      'svg': _s('<svg xmlns="http://www.w3.org/2000/svg"/>'),
      'svg with prolog':
          _s('<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg"/>'),
      'svg after BOM+space': [0xEF, 0xBB, 0xBF, 0x20, ..._s('<svg/>')],
    }.entries) {
      test('${e.key} is stored', () async {
        final s = store(bodyClient(e.value));
        await s.init();
        expect(await s.fetch(url), StoreFetch.stored);
        expect(s.cachedFile(url), isNotNull);
      });
    }

    test('an xml document that is not an svg is rejected', () async {
      final s = store(bodyClient(_s('<?xml version="1.0"?><error>503</error>')));
      await s.init();
      await expectLater(s.fetch(url), throwsA(isA<HttpException>()));
    });

    test('cachedFile rejects and deletes a stored non-image', () async {
      final s = store(bodyClient(_png));
      await s.init();
      await s.fetch(url);
      final f = s.cachedFile(url)!;
      f.writeAsStringSync('<html>poisoned earlier by a captive portal</html>');
      // "Relaunch": a fresh store has not sniffed that path yet.
      final s2 = store(bodyClient(_png));
      await s2.init();
      expect(s2.cachedFile(url), isNull);
      expect(f.existsSync(), isFalse);
      // ...and a re-fetch heals it.
      expect(await s2.fetch(url), StoreFetch.stored);
      expect(s2.cachedFile(url), isNotNull);
    });

    test('evict removes the file', () async {
      final s = store(bodyClient(_png));
      await s.init();
      await s.fetch(url);
      s.evict(url);
      expect(s.cachedFile(url), isNull);
    });
  });

  group('timeouts', () {
    MockClient streaming(Stream<List<int>> Function() body,
            {int? contentLength}) =>
        MockClient.streaming((req, _) async => http.StreamedResponse(
            body(), 200,
            contentLength: contentLength));

    Stream<List<int>> trickle(List<List<int>> chunks, Duration gap) async* {
      for (final c in chunks) {
        await Future<void>.delayed(gap);
        yield c;
      }
    }

    test('a slow but steady download (total > idle timeout) completes',
        () async {
      final s = store(
          streaming(() => trickle(
              [_png, [4], [5], [6], [7], [8], [9]],
              const Duration(milliseconds: 60))),
          idle: const Duration(milliseconds: 250));
      await s.init();
      expect(await s.fetch(url), StoreFetch.stored);
      expect(s.cachedFile(url)!.lengthSync(), _png.length + 6);
    });

    test('a stalled body fails after the idle timeout and leaves no .tmp',
        () async {
      // (a controller, not async*: cancelling a generator parked on a
      // never-completing future would hang the test, not the production code)
      Stream<List<int>> stalls() =>
          (StreamController<List<int>>()..add(_png)).stream;

      final s = store(streaming(stalls),
          idle: const Duration(milliseconds: 150));
      await s.init();
      await expectLater(s.fetch(url), throwsA(isA<TimeoutException>()));
      expect(s.cachedFile(url), isNull);
      expect(files(), isEmpty);
    });

    test('an endless trickle hits the hard ceiling', () async {
      Stream<List<int>> endless() async* {
        yield _png;
        while (true) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          yield [1];
        }
      }

      final s = store(streaming(endless),
          idle: const Duration(milliseconds: 300),
          max: const Duration(milliseconds: 400));
      await s.init();
      await expectLater(s.fetch(url), throwsA(isA<TimeoutException>()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(files().where((f) => f.endsWith('.img')), isEmpty);
    });

    test('a timed-out download aborts only its own request', () async {
      final aborted = <String, bool>{};
      final client = MockClient.streaming((req, _) async {
        final path = req.url.path;
        aborted[path] = false;
        if (req is http.Abortable) {
          req.abortTrigger?.then((_) => aborted[path] = true);
        }
        if (path == '/stall.png') {
          return http.StreamedResponse(
              (StreamController<List<int>>()..add(_png)).stream, 200);
        }
        // A healthy download that outlives the stalled one's timeout.
        return http.StreamedResponse(
            trickle([_png, [4], [5], [6]], const Duration(milliseconds: 80)),
            200);
      });
      final s = store(client, idle: const Duration(milliseconds: 150));
      await s.init();
      final stalled = s.fetch('https://img.test/stall.png');
      final healthy = s.fetch('https://img.test/ok.png');
      await expectLater(stalled, throwsA(isA<TimeoutException>()));
      expect(await healthy, StoreFetch.stored);
      expect(aborted['/stall.png'], isTrue);
      expect(aborted['/ok.png'], isFalse);
    });

    test('truncated body (content-length mismatch) is rejected', () async {
      final s = store(streaming(() => Stream.value(_png),
          contentLength: _png.length + 100));
      await s.init();
      await expectLater(s.fetch(url), throwsA(isA<HttpException>()));
      expect(files(), isEmpty);
    });
  });
}
