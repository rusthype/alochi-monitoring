import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/utils/topic_format.dart';

void main() {
  group('topicsFromSections', () {
    test('maps name/cor/tot to name/correct/total', () {
      final sections = [
        {'name': 'Vocabulary', 'cor': 20, 'tot': 25},
        {'name': 'Grammar', 'cor': 4, 'tot': 6},
      ];
      final result = topicsFromSections(sections);
      expect(result, [
        {'name': 'Vocabulary', 'correct': 20, 'total': 25},
        {'name': 'Grammar', 'correct': 4, 'total': 6},
      ]);
    });

    test('empty input returns empty list', () {
      expect(topicsFromSections([]), []);
    });
  });

  group('topicsFromEngEntries', () {
    test('maps MapEntry<String, ({int ok, int tot})> to name/correct/total', () {
      final entries = [
        MapEntry('vocab', (ok: 5, tot: 6)),
        MapEntry('grammar', (ok: 6, tot: 6)),
      ];
      final result = topicsFromEngEntries(entries);
      expect(result, [
        {'name': 'vocab', 'correct': 5, 'total': 6},
        {'name': 'grammar', 'correct': 6, 'total': 6},
      ]);
    });

    test('empty input returns empty list', () {
      expect(topicsFromEngEntries([]), []);
    });
  });
}
