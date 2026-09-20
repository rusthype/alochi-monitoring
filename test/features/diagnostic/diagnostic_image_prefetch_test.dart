import 'package:alochi_monitoring/features/diagnostic/utils/diagnostic_image_prefetch.dart';
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
}
