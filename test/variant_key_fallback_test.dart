// Non-numeric / missing variant keys must never resolve to an empty test.
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';

/// One yes_no question whose text is [tag], so tests can tell variants apart.
List<Map<String, dynamic>> _sec(String tag) => [
      {'type': 'yes_no', 'q': tag, 'ans': 'YES'},
    ];

TestSpec _spec(List<String> keys) => TestSpec.fromJson({
      'test_key': 't',
      'parts': ['S'],
      'variants': {
        for (final k in keys) k: {'S': _sec('v$k')},
      },
    });

String? _tag(TestSpec s, String key) {
  final secs = s.sectionsForVariant(key);
  if (secs.isEmpty) return null;
  return secs.first.questions.first.q;
}

void main() {
  group('sectionsForVariant', () {
    test('numeric keys: exact match unchanged', () {
      final s = _spec(['1', '2', '3']);
      expect(_tag(s, '1'), 'v1');
      expect(_tag(s, '3'), 'v3');
    });

    test('{"A"} resolves to A sections for any requested key', () {
      final s = _spec(['A']);
      expect(_tag(s, 'A'), 'vA');
      expect(_tag(s, '1'), 'vA');
    });

    test('{"2","3"} with requested 1 falls back to nearest (2)', () {
      final s = _spec(['2', '3']);
      expect(_tag(s, '1'), 'v2');
      expect(_tag(s, '9'), 'v3');
    });

    test('empty variants stay empty', () {
      final s = _spec([]);
      expect(s.sectionsForVariant('1'), isEmpty);
    });

    test('mixed keys: numeric preferred over non-numeric on fallback', () {
      final s = _spec(['A', '2']);
      expect(_tag(s, '1'), 'v2');
      expect(_tag(s, 'zzz'), 'v2');
      expect(_tag(s, 'A'), 'vA');
    });
  });

  group('pickVariantNumber', () {
    test('numeric keys: only real keys, all of them reachable', () {
      final m = {'1': {}, '2': {}, '3': {}};
      final seen = <int>{};
      for (var i = 0; i < 300; i++) {
        seen.add(pickVariantNumber(m));
      }
      expect(seen, {1, 2, 3});
    });

    test('{"2","3"} never yields 1', () {
      final m = {'2': {}, '3': {}};
      for (var i = 0; i < 100; i++) {
        expect(pickVariantNumber(m), anyOf(2, 3));
      }
    });

    test('mixed keys pick only the numeric one', () {
      for (var i = 0; i < 50; i++) {
        expect(pickVariantNumber({'A': {}, '2': {}}), 2);
      }
    });

    test('only non-numeric keys -> 1 (resolved by sectionsForVariant)', () {
      expect(pickVariantNumber({'A': {}}), 1);
    });

    test('empty / non-map -> 1', () {
      expect(pickVariantNumber({}), 1);
      expect(pickVariantNumber(null), 1);
    });
  });
}
