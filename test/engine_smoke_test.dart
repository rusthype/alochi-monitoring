// test/engine_smoke_test.dart
// Faza 4b smoke test — pure Dart, no Flutter widget binding required.
//
// Builds a minimal inline TestSpec covering all 7 question types, runs
// TestScorer with known correct/wrong answers, and asserts the score is correct.
// Also verifies the EngineHostScreen section-mapping rules (math vs english).

import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_scorer.dart';

// ── Inline TestSpec fixture ───────────────────────────────────────────────────
//
// Variant "1":
//   Math       — 2 text_choice  (ans=0)
//   Matematika — 1 image_choice (ans=1)   [maps to math bucket too]
//   English    — 1 yes_no       (ans="YES")
//   Spelling   — 1 spelling     (ans="cat")
//   Reading    — reading container with 2 text_choice questions
//   Sentences  — 1 sentence_order (ans="It is a cat.")
//   FillBlank  — 1 fill_blank   (ans="dog")

Map<String, dynamic> _buildSpecJson() {
  return {
    'test_key': 'smoke_test_v1',
    'title': 'Smoke Test',
    'grade': 4,
    'version': 1,
    'parts': [
      'Math',
      'Matematika',
      'English',
      'Spelling',
      'Reading',
      'Sentences',
      'FillBlank',
    ],
    'variants': {
      '1': {
        'Math': [
          {
            'type': 'text_choice',
            'q': 'Q1',
            'opts': ['A', 'B'],
            'ans': 0
          },
          {
            'type': 'text_choice',
            'q': 'Q2',
            'opts': ['A', 'B'],
            'ans': 0
          },
        ],
        'Matematika': [
          {
            'type': 'image_choice',
            'img': 'img.png',
            'q': 'img q',
            'opts': ['X', 'Y'],
            'ans': 1,
          },
        ],
        'English': [
          {'type': 'yes_no', 'q': 'Is it?', 'ans': 'YES'},
        ],
        'Spelling': [
          {'type': 'spelling', 'scramble': 'a t c', 'ans': 'cat'},
        ],
        'Reading': {
          'img': null,
          'title': 'A Short Passage',
          'text': 'A cat sat.',
          'qs': [
            {
              'type': 'text_choice',
              'q': 'What sat?',
              'opts': ['cat', 'dog'],
              'ans': 0
            },
            {
              'type': 'text_choice',
              'q': 'Where?',
              'opts': ['mat', 'car'],
              'ans': 0
            },
          ],
        },
        'Sentences': [
          {
            'type': 'sentence_order',
            'words': 'It is a cat',
            'ans': 'It is a cat.'
          },
        ],
        'FillBlank': [
          {'type': 'fill_blank', 'q': 'A ___ runs.', 'ans': 'dog'},
        ],
      },
    },
  };
}

// ── All-correct answers ───────────────────────────────────────────────────────

Map<String, dynamic> _allCorrect() {
  return {
    'Math/0': 0,
    'Math/1': 0,
    'Matematika/0': 1,
    'English/0': 'YES',
    'Spelling/0': 'cat',
    'Reading/0': 0,
    'Reading/1': 0,
    'Sentences/0': 'It is a cat.',
    'FillBlank/0': 'dog',
  };
}

// ── All-wrong answers ─────────────────────────────────────────────────────────

Map<String, dynamic> _allWrong() {
  return {
    'Math/0': 1, // wrong: correct is 0
    'Math/1': 1, // wrong
    'Matematika/0': 0, // wrong: correct is 1
    'English/0': 'NO', // wrong: correct is YES
    'Spelling/0': 'xyz', // wrong
    'Reading/0': 1, // wrong
    'Reading/1': 1, // wrong
    'Sentences/0': 'cat a is It.', // wrong
    'FillBlank/0': 'cat', // wrong: correct is dog
  };
}

// ── Helper: total question count from spec ────────────────────────────────────

int _totalQs(TestSpec spec, String variantKey) {
  return spec
      .sectionsForVariant(variantKey)
      .fold(0, (sum, s) => sum + s.questionCount);
}

// ── Section→bucket mapper (mirrors EngineHostScreen.isMathSection) ──────────
// This is the rule that must stay in sync with EngineHostScreen._isMathSection.

bool _isMathSection(String name) {
  final n = name.trim().toLowerCase();
  return n == 'math' || n.startsWith('matema');
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('TestSpec.fromJson', () {
    test('parses inline spec without error', () {
      final spec = TestSpec.fromJson(_buildSpecJson());
      expect(spec.testKey, 'smoke_test_v1');
      expect(spec.grade, 4);
      expect(spec.parts.length, 7);
      expect(spec.variants.containsKey('1'), isTrue);
    });

    test('sectionsForVariant("1") returns 7 sections in parts order', () {
      final spec = TestSpec.fromJson(_buildSpecJson());
      final sections = spec.sectionsForVariant('1');
      expect(sections.length, 7);
      expect(sections.map((s) => s.name).toList(), [
        'Math',
        'Matematika',
        'English',
        'Spelling',
        'Reading',
        'Sentences',
        'FillBlank',
      ]);
    });

    test('total question count is 9', () {
      final spec = TestSpec.fromJson(_buildSpecJson());
      expect(_totalQs(spec, '1'), 9);
    });

    test('Reading section parsed as reading container', () {
      final spec = TestSpec.fromJson(_buildSpecJson());
      final sections = spec.sectionsForVariant('1');
      final reading = sections.firstWhere((s) => s.name == 'Reading');
      expect(reading.isReading, isTrue);
      expect(reading.readingContainer!.qs.length, 2);
    });
  });

  group('TestScorer — all correct', () {
    late TestSpec spec;
    late ScoredResult result;

    setUp(() {
      spec = TestSpec.fromJson(_buildSpecJson());
      result = TestScorer.score(spec, '1', _allCorrect());
    });

    test('totalCorrect == 9', () => expect(result.totalCorrect, 9));
    test('totalQuestions == 9', () => expect(result.totalQuestions, 9));
    test('totalPct == 100.0',
        () => expect(result.totalPct, closeTo(100.0, 0.01)));
    test(
        'testKey is propagated', () => expect(result.testKey, 'smoke_test_v1'));

    test('Math section: 2/2 correct', () {
      final s = result.sectionScores.firstWhere((s) => s.name == 'Math');
      expect(s.correct, 2);
      expect(s.total, 2);
    });

    test('Matematika section: 1/1 correct', () {
      final s = result.sectionScores.firstWhere((s) => s.name == 'Matematika');
      expect(s.correct, 1);
      expect(s.total, 1);
    });

    test('English section: 1/1 correct', () {
      final s = result.sectionScores.firstWhere((s) => s.name == 'English');
      expect(s.correct, 1);
      expect(s.total, 1);
    });

    test('Spelling section: 1/1 correct', () {
      final s = result.sectionScores.firstWhere((s) => s.name == 'Spelling');
      expect(s.correct, 1);
      expect(s.total, 1);
    });

    test('Reading section: 2/2 correct', () {
      final s = result.sectionScores.firstWhere((s) => s.name == 'Reading');
      expect(s.correct, 2);
      expect(s.total, 2);
    });

    test('Sentences section: 1/1 correct', () {
      final s = result.sectionScores.firstWhere((s) => s.name == 'Sentences');
      expect(s.correct, 1);
      expect(s.total, 1);
    });

    test('FillBlank section: 1/1 correct', () {
      final s = result.sectionScores.firstWhere((s) => s.name == 'FillBlank');
      expect(s.correct, 1);
      expect(s.total, 1);
    });
  });

  group('TestScorer — all wrong', () {
    late TestSpec spec;
    late ScoredResult result;

    setUp(() {
      spec = TestSpec.fromJson(_buildSpecJson());
      result = TestScorer.score(spec, '1', _allWrong());
    });

    test('totalCorrect == 0', () => expect(result.totalCorrect, 0));
    test('totalPct == 0.0', () => expect(result.totalPct, closeTo(0.0, 0.01)));
  });

  group('TestScorer — partial answers', () {
    test('unanswered question counts as wrong', () {
      final spec = TestSpec.fromJson(_buildSpecJson());
      // Answer only Math/0 correctly, leave everything else unanswered.
      final answers = <String, dynamic>{'Math/0': 0};
      final result = TestScorer.score(spec, '1', answers);
      expect(result.totalCorrect, 1);
      expect(result.totalQuestions, 9);
      expect(result.totalPct, closeTo(100.0 / 9, 0.1));
    });

    test('mixed: some correct, some wrong', () {
      final spec = TestSpec.fromJson(_buildSpecJson());
      final answers = <String, dynamic>{
        'Math/0': 0, // correct
        'Math/1': 1, // wrong (correct=0)
        'Matematika/0': 1, // correct
        'English/0': 'NO', // wrong
        'Reading/0': 0, // correct
        'Reading/1': 1, // wrong
      };
      final result = TestScorer.score(spec, '1', answers);
      // Math/0 + Matematika/0 + Reading/0 = 3 correct
      expect(result.totalCorrect, 3);
      expect(result.totalQuestions, 9);
    });
  });

  group('Section→bucket mapping (mirrors EngineHostScreen.isMathSection)', () {
    test('"Math" is math bucket', () => expect(_isMathSection('Math'), isTrue));
    test('"math" (lowercase) is math bucket',
        () => expect(_isMathSection('math'), isTrue));
    test('"Matematika" is math bucket',
        () => expect(_isMathSection('Matematika'), isTrue));
    test('"matematika" (lowercase) is math bucket',
        () => expect(_isMathSection('matematika'), isTrue));
    test('"English" is NOT math',
        () => expect(_isMathSection('English'), isFalse));
    test('"Reading" is NOT math',
        () => expect(_isMathSection('Reading'), isFalse));
    test('"Spelling" is NOT math',
        () => expect(_isMathSection('Spelling'), isFalse));
    test('"Sentences" is NOT math',
        () => expect(_isMathSection('Sentences'), isFalse));
    test('"FillBlank" is NOT math',
        () => expect(_isMathSection('FillBlank'), isFalse));
    test('"Vocabulary" is NOT math',
        () => expect(_isMathSection('Vocabulary'), isFalse));
    test('"Grammar" is NOT math',
        () => expect(_isMathSection('Grammar'), isFalse));

    test('math+matematika totals 3 from all-correct result', () {
      final spec = TestSpec.fromJson(_buildSpecJson());
      final result = TestScorer.score(spec, '1', _allCorrect());
      int mathCor = 0;
      for (final s in result.sectionScores) {
        if (_isMathSection(s.name)) mathCor += s.correct;
      }
      expect(mathCor, 3); // Math: 2 + Matematika: 1
    });

    test('english (non-math) totals 6 from all-correct result', () {
      final spec = TestSpec.fromJson(_buildSpecJson());
      final result = TestScorer.score(spec, '1', _allCorrect());
      int engCor = 0;
      for (final s in result.sectionScores) {
        if (!_isMathSection(s.name)) engCor += s.correct;
      }
      // English(1) + Spelling(1) + Reading(2) + Sentences(1) + FillBlank(1) = 6
      expect(engCor, 6);
    });
  });

  group('SectionScore.pct', () {
    test('pct 0 when total=0', () {
      const s = SectionScore(name: 'Empty', correct: 0, total: 0);
      expect(s.pct, 0.0);
    });

    test('pct 50.0 for 1/2', () {
      const s = SectionScore(name: 'Half', correct: 1, total: 2);
      expect(s.pct, closeTo(50.0, 0.01));
    });

    test('pct 100.0 for 5/5', () {
      const s = SectionScore(name: 'Perfect', correct: 5, total: 5);
      expect(s.pct, closeTo(100.0, 0.01));
    });
  });
}
