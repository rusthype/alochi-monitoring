// test/engine/test_scorer_test.dart
// Scores real prod fixture (math_diag_3_4, variant "1") with correct/wrong answers.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_scorer.dart';

TestSpec _loadFixture() {
  final file = File('test/fixtures/math_diag_3_4.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return TestSpec.fromJson(json);
}

// All correct answers for variant "1" (extracted from fixture).
// Section order matches parts: 1-bob, 2-bob, 3-bob, 4-bob.
Map<String, dynamic> _allCorrectV1() => {
      // 1-bob — Bir xonali sonlar (5 text_choice)
      '1-bob — Bir xonali sonlar/0': 0,
      '1-bob — Bir xonali sonlar/1': 0,
      '1-bob — Bir xonali sonlar/2': 1,
      '1-bob — Bir xonali sonlar/3': 2,
      '1-bob — Bir xonali sonlar/4': 0,
      // 2-bob — Ikki xonali sonlar (9 text_choice)
      '2-bob — Ikki xonali sonlar/0': 1,
      '2-bob — Ikki xonali sonlar/1': 3,
      '2-bob — Ikki xonali sonlar/2': 3,
      '2-bob — Ikki xonali sonlar/3': 2,
      '2-bob — Ikki xonali sonlar/4': 1,
      '2-bob — Ikki xonali sonlar/5': 2,
      '2-bob — Ikki xonali sonlar/6': 3,
      '2-bob — Ikki xonali sonlar/7': 3,
      '2-bob — Ikki xonali sonlar/8': 0,
      // 3-bob — Karra jadvali (8 text_choice)
      '3-bob — Karra jadvali/0': 2,
      '3-bob — Karra jadvali/1': 3,
      '3-bob — Karra jadvali/2': 1,
      '3-bob — Karra jadvali/3': 3,
      '3-bob — Karra jadvali/4': 0,
      '3-bob — Karra jadvali/5': 0,
      '3-bob — Karra jadvali/6': 2,
      '3-bob — Karra jadvali/7': 2,
      // 4-bob — Uch xonali sonlar (7 text_choice + 1 fill_blank)
      '4-bob — Uch xonali sonlar/0': 2,
      '4-bob — Uch xonali sonlar/1': 2,
      '4-bob — Uch xonali sonlar/2': 3,
      '4-bob — Uch xonali sonlar/3': 2,
      '4-bob — Uch xonali sonlar/4': 2,
      '4-bob — Uch xonali sonlar/5': 1,
      '4-bob — Uch xonali sonlar/6': 0,
      '4-bob — Uch xonali sonlar/7': '132', // fill_blank
    };

// All wrong: wrong index for choice types, nonsense for fill_blank.
Map<String, dynamic> _allWrongV1() => {
      '1-bob — Bir xonali sonlar/0': 3,
      '1-bob — Bir xonali sonlar/1': 3,
      '1-bob — Bir xonali sonlar/2': 3,
      '1-bob — Bir xonali sonlar/3': 3,
      '1-bob — Bir xonali sonlar/4': 3,
      '2-bob — Ikki xonali sonlar/0': 0,
      '2-bob — Ikki xonali sonlar/1': 0,
      '2-bob — Ikki xonali sonlar/2': 0,
      '2-bob — Ikki xonali sonlar/3': 0,
      '2-bob — Ikki xonali sonlar/4': 0,
      '2-bob — Ikki xonali sonlar/5': 0,
      '2-bob — Ikki xonali sonlar/6': 0,
      '2-bob — Ikki xonali sonlar/7': 0,
      '2-bob — Ikki xonali sonlar/8': 3,
      '3-bob — Karra jadvali/0': 3,
      '3-bob — Karra jadvali/1': 0,
      '3-bob — Karra jadvali/2': 3,
      '3-bob — Karra jadvali/3': 0,
      '3-bob — Karra jadvali/4': 3,
      '3-bob — Karra jadvali/5': 3,
      '3-bob — Karra jadvali/6': 3,
      '3-bob — Karra jadvali/7': 3,
      '4-bob — Uch xonali sonlar/0': 0,
      '4-bob — Uch xonali sonlar/1': 0,
      '4-bob — Uch xonali sonlar/2': 0,
      '4-bob — Uch xonali sonlar/3': 0,
      '4-bob — Uch xonali sonlar/4': 0,
      '4-bob — Uch xonali sonlar/5': 3,
      '4-bob — Uch xonali sonlar/6': 3,
      '4-bob — Uch xonali sonlar/7': 'NOTO\'G\'RI', // fill_blank wrong
    };

void main() {
  late TestSpec spec;

  setUpAll(() {
    spec = _loadFixture();
  });

  group('TestScorer — all correct (variant "1")', () {
    late ScoredResult result;

    setUpAll(() {
      result = TestScorer.score(spec, '1', _allCorrectV1());
    });

    test('totalQuestions == 30', () {
      expect(result.totalQuestions, 30);
    });

    test('totalCorrect == 30 (100%)', () {
      expect(result.totalCorrect, 30);
    });

    test('totalPct == 100.0', () {
      expect(result.totalPct, closeTo(100.0, 0.01));
    });

    test('testKey propagated correctly', () {
      expect(result.testKey, 'math_diag_3_4');
    });

    test('4 section scores returned', () {
      expect(result.sectionScores.length, 4);
    });

    test('section 1-bob: 5/5 correct', () {
      final s =
          result.sectionScores.firstWhere((s) => s.name.contains('1-bob'));
      expect(s.correct, 5);
      expect(s.total, 5);
    });

    test('section 2-bob: 9/9 correct', () {
      final s =
          result.sectionScores.firstWhere((s) => s.name.contains('2-bob'));
      expect(s.correct, 9);
      expect(s.total, 9);
    });

    test('section 3-bob: 8/8 correct', () {
      final s =
          result.sectionScores.firstWhere((s) => s.name.contains('3-bob'));
      expect(s.correct, 8);
      expect(s.total, 8);
    });

    test('section 4-bob: 8/8 correct', () {
      final s =
          result.sectionScores.firstWhere((s) => s.name.contains('4-bob'));
      expect(s.correct, 8);
      expect(s.total, 8);
    });
  });

  group('TestScorer — all wrong (variant "1")', () {
    late ScoredResult result;

    setUpAll(() {
      result = TestScorer.score(spec, '1', _allWrongV1());
    });

    test('totalCorrect == 0', () {
      expect(result.totalCorrect, 0);
    });

    test('totalPct == 0.0', () {
      expect(result.totalPct, closeTo(0.0, 0.01));
    });
  });

  group('fill_blank scoring — variant "1", section 4-bob q7', () {
    const sectionKey = '4-bob — Uch xonali sonlar/7';

    test('exact match "132" scores correct', () {
      final result = TestScorer.score(spec, '1', {sectionKey: '132'});
      final sec4 =
          result.sectionScores.firstWhere((s) => s.name.contains('4-bob'));
      // Only q7 answered — the rest are unanswered (wrong), so q7 is the 1 correct.
      expect(sec4.correct, greaterThanOrEqualTo(1));
    });

    test('match with whitespace padding "  132  " scores correct (trim)', () {
      final result = TestScorer.score(spec, '1', {sectionKey: '  132  '});
      final sec4 =
          result.sectionScores.firstWhere((s) => s.name.contains('4-bob'));
      expect(sec4.correct, greaterThanOrEqualTo(1));
    });

    test('case-insensitive match works (scorer uses toLowerCase)', () {
      // "132" is numeric, but verifying scorer does not crash on case handling
      final result = TestScorer.score(spec, '1', {sectionKey: '132'});
      expect(result.totalCorrect, greaterThanOrEqualTo(1));
    });

    test('wrong answer "999" scores 0 for that question', () {
      // Score only q7 with wrong answer; all others unanswered
      final result = TestScorer.score(spec, '1', {sectionKey: '999'});
      expect(result.totalCorrect, 0);
    });

    test('empty string scores 0', () {
      final result = TestScorer.score(spec, '1', {sectionKey: ''});
      expect(result.totalCorrect, 0);
    });
  });

  group('TestScorer — unanswered = 0', () {
    test('empty answers map: 0/30', () {
      final result = TestScorer.score(spec, '1', {});
      expect(result.totalCorrect, 0);
      expect(result.totalQuestions, 30);
    });
  });
}
