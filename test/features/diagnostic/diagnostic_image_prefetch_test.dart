import 'package:alochi_monitoring/features/diagnostic/utils/diagnostic_image_prefetch.dart';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('collectDiagnosticImageUrls', () {
    test('fixes a relative /media/ URL instead of dropping it', () {
      final urls = collectDiagnosticImageUrls({
        'image_url': '/media/diagnostic/questions/cake.png',
      });
      expect(urls, ['https://api.alochi.org/media/diagnostic/questions/cake.png']);
    });

    test('fixes a relative media/ (no leading slash) URL', () {
      final urls = collectDiagnosticImageUrls({
        'image_url': 'media/diagnostic/questions/cake.png',
      });
      expect(urls, ['https://api.alochi.org/media/diagnostic/questions/cake.png']);
    });

    test('keeps an already-absolute https URL', () {
      final urls = collectDiagnosticImageUrls({
        'svg_visual': 'https://api.alochi.org/media/x.svg',
      });
      expect(urls, ['https://api.alochi.org/media/x.svg']);
    });

    test('picks up a bare image-extension string with no path prefix', () {
      final urls = collectDiagnosticImageUrls({'image_url': 'cake.jpg'});
      expect(urls, ['https://api.alochi.org/cake.jpg']);
    });

    test('ignores plain text values that are not image-shaped', () {
      final urls = collectDiagnosticImageUrls({
        'question_text': 'What is 2 + 2?',
        'option_a': 'four',
      });
      expect(urls, isEmpty);
    });

    test('walks nested lists/maps and dedupes repeated URLs', () {
      final urls = collectDiagnosticImageUrls({
        'questions': [
          {'image_url': '/media/a.png'},
          {'image_url': '/media/a.png'},
          {'nested': {'svg_visual': '/media/b.svg'}},
        ],
      });
      expect(urls.toSet(), {
        'https://api.alochi.org/media/a.png',
        'https://api.alochi.org/media/b.svg',
      });
      expect(urls.length, 2);
    });
  });

  group('prefetchDiagnosticImages', () {
    final qs = [
      for (var i = 1; i <= 8; i++) {'image_url': '/media/q$i.png'},
    ];
    String u(int i) => 'https://api.alochi.org/media/q$i.png';

    test('downloads in question order, at most 3 in flight', () async {
      final started = <String>[];
      final gates = <String, Completer<void>>{};
      var inFlight = 0;
      var maxInFlight = 0;
      Future<void> fake(String url) async {
        started.add(url);
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        final c = gates[url] = Completer<void>();
        await c.future;
        inFlight--;
      }

      final done = prefetchDiagnosticImages(qs, download: fake);
      await Future<void>.delayed(Duration.zero);
      expect(started, [u(1), u(2), u(3)]);

      gates[u(1)]!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(started, [u(1), u(2), u(3), u(4)]);

      for (var i = 2; i <= 8; i++) {
        while (gates[u(i)] == null) {
          await Future<void>.delayed(Duration.zero);
        }
        gates[u(i)]!.complete();
        await Future<void>.delayed(Duration.zero);
      }
      await done;
      expect(started, [for (var i = 1; i <= 8; i++) u(i)]);
      expect(maxInFlight, 3);
    });

    test('a failing download does not stop the rest or throw', () async {
      final seen = <String>[];
      await prefetchDiagnosticImages(
        qs.take(4).toList(),
        download: (url) async {
          seen.add(url);
          if (url == u(2)) throw Exception('boom');
        },
      );
      expect(seen.length, 4);
    });
  });

  group('awaitDiagnosticQuestionImages', () {
    test('returns after the timeout when the download never completes',
        () async {
      final sw = Stopwatch()..start();
      await awaitDiagnosticQuestionImages(
        {'image_url': '/media/q1.png'},
        timeout: const Duration(milliseconds: 50),
        download: (_) => Completer<void>().future,
      );
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(45));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('skips questions without an image, and never throws', () async {
      var calls = 0;
      await awaitDiagnosticQuestionImages(
        {'question_text': 'What is 2 + 2?'},
        download: (_) async => calls++,
      );
      expect(calls, 0);
      await awaitDiagnosticQuestionImages(
        {'image_url': '/media/q1.png'},
        download: (_) => throw Exception('offline'),
      );
    });

    test('completes as soon as the image is cached', () async {
      var downloaded = false;
      await awaitDiagnosticQuestionImages(
        {'image_url': '/media/q1.png'},
        download: (_) async => downloaded = true,
      );
      expect(downloaded, isTrue);
    });
  });
}
