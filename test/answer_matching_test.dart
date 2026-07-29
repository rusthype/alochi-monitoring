// test/answer_matching_test.dart
// Regression tests for tolerant free-text answer matching in TestScorer:
//   * Uzbek apostrophe glyphs (o'/g') fold together — a correct answer must not
//     fail just because the keyboard produced a different apostrophe codepoint.
//   * case + internal whitespace are normalised.
//   * sentence_order is robust to separator spacing and apostrophe form.
// Pure Dart via flutter_test (same style as engine_smoke_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_scorer.dart';

// The apostrophe glyphs a pupil's keyboard might emit.
const _straight = "'"; // U+0027 straight apostrophe — what seed/AI answers use
const _curly = '’'; //    ’  U+2019 — iOS / autocorrect default
const _okina = 'ʻ'; //    ʻ  U+02BB — Unicode-correct Uzbek turned comma

Map<String, dynamic> _specJson(
  List<Map<String, dynamic>> fill,
  List<Map<String, dynamic>> order,
) =>
    {
      'test_key': 'match_test',
      'title': 'Match',
      'grade': 9,
      'version': 1,
      'parts': ['Fill', 'Order'],
      'variants': {
        '1': {'Fill': fill, 'Order': order},
      },
    };

TestSpec _build(
  List<Map<String, dynamic>> fill,
  List<Map<String, dynamic>> order,
) =>
    TestSpec.fromJson(_specJson(fill, order));

void main() {
  group('fill_blank apostrophe tolerance', () {
    test('curly apostrophe matches straight-apostrophe answer', () {
      final spec = _build([
        {'type': 'fill_blank', 'q': 'valyuta?', 'ans': 'so${_straight}m'},
      ], []);
      final r = TestScorer.score(spec, '1', {'Fill/0': 'so${_curly}m'});
      expect(r.totalCorrect, 1);
    });

    test('okina (U+02BB) apostrophe matches', () {
      final spec = _build([
        {'type': 'fill_blank', 'q': 'organ?', 'ans': 'o${_straight}pka'},
      ], []);
      final r = TestScorer.score(spec, '1', {'Fill/0': 'o${_okina}pka'});
      expect(r.totalCorrect, 1);
    });

    test('case-insensitive', () {
      final spec = _build([
        {'type': 'fill_blank', 'q': 'qonun?', 'ans': 'Konstitutsiya'},
      ], []);
      final r = TestScorer.score(spec, '1', {'Fill/0': 'konstitutsiya'});
      expect(r.totalCorrect, 1);
    });

    test('internal double space collapses (+ curly apostrophes)', () {
      final spec = _build([
        {
          'type': 'fill_blank',
          'q': 'burchak?',
          'ans': 'to${_straight}g${_straight}ri burchak',
        },
      ], []);
      final r = TestScorer.score(
          spec, '1', {'Fill/0': 'to${_curly}g${_curly}ri  burchak'});
      expect(r.totalCorrect, 1);
    });

    test('a genuinely wrong answer still fails', () {
      final spec = _build([
        {'type': 'fill_blank', 'q': 'valyuta?', 'ans': 'so${_straight}m'},
      ], []);
      final r = TestScorer.score(spec, '1', {'Fill/0': 'dollar'});
      expect(r.totalCorrect, 0);
    });
  });

  group('sentence_order robustness', () {
    List<Map<String, dynamic>> order() => [
          {'type': 'sentence_order', 'words': 'B / A / C', 'ans': 'A / B / C'},
        ];

    test('correct order matches (widget joins with " / ")', () {
      final r =
          TestScorer.score(_build([], order()), '1', {'Order/0': 'A / B / C'});
      expect(r.totalCorrect, 1);
    });

    test('wrong order fails', () {
      final r =
          TestScorer.score(_build([], order()), '1', {'Order/0': 'B / A / C'});
      expect(r.totalCorrect, 0);
    });

    test('apostrophes in event names fold', () {
      final spec = _build([], [
        {
          'type': 'sentence_order',
          'words': 'Ulug${_straight}bek / Amir Temur',
          'ans': 'Amir Temur / Ulug${_straight}bek',
        },
      ]);
      final r = TestScorer.score(
          spec, '1', {'Order/0': 'Amir Temur / Ulug${_curly}bek'});
      expect(r.totalCorrect, 1);
    });

    test(
        'slash-joined stored answer (pre-fix widget output) still matches '
        'a natural-sentence correct answer', () {
      final spec = _build([], [
        {
          'type': 'sentence_order',
          'words': 'is / doll / It / a',
          'ans': 'It is a doll.',
        },
      ]);
      final r = TestScorer.score(spec, '1', {'Order/0': 'it / is / a / doll'});
      expect(r.totalCorrect, 1);
    });

    test(
        'plain-space-joined answer (current widget output) matches a '
        'natural-sentence correct answer', () {
      final spec = _build([], [
        {
          'type': 'sentence_order',
          'words': 'is / doll / It / a',
          'ans': 'It is a doll.',
        },
      ]);
      final r = TestScorer.score(spec, '1', {'Order/0': 'It is a doll'});
      expect(r.totalCorrect, 1);
    });
  });

  group('contraction equivalence', () {
    test('expanded typed answer matches contracted correct answer', () {
      final spec = _build([], [
        {
          'type': 'sentence_order',
          'words': 'in / They / bedroom / are / the',
          'ans': "They're in the bedroom.",
        },
      ]);
      final r =
          TestScorer.score(spec, '1', {'Order/0': 'they are in the bedroom'});
      expect(r.totalCorrect, 1);
    });

    test(
        'contracted typed answer matches expanded correct answer '
        '(reverse direction)', () {
      final spec = _build([], [
        {
          'type': 'sentence_order',
          'words': 'in / They / bedroom / are / the',
          'ans': 'They are in the bedroom.',
        },
      ]);
      final r =
          TestScorer.score(spec, '1', {'Order/0': "they're in the bedroom"});
      expect(r.totalCorrect, 1);
    });

    test('a genuinely wrong verb still fails despite contraction expansion',
        () {
      final spec = _build([], [
        {
          'type': 'sentence_order',
          'words': 'in / They / bedroom / were / the',
          'ans': "They're in the bedroom.",
        },
      ]);
      final r =
          TestScorer.score(spec, '1', {'Order/0': 'they was in the bedroom'});
      expect(r.totalCorrect, 0);
    });

    test('contraction expansion also applies to fill_blank', () {
      final spec = _build([
        {'type': 'fill_blank', 'q': 'Complete: ___ a doll.', 'ans': "It's"},
      ], []);
      final r = TestScorer.score(spec, '1', {'Fill/0': 'It is'});
      expect(r.totalCorrect, 1);
    });
  });
}
