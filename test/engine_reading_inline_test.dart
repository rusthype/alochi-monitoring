// test/engine_reading_inline_test.dart
// Sprint 1 (2026-07-14 history/onatili-diagnostics plan) — list-shaped
// inline reading passages: a `type:"reading"` item living inside a section's
// question LIST (not the whole section itself). Before Task 1.1-1.5 these
// were rendered as SizedBox.shrink() (test_engine.dart) and never scored
// (test_scorer.dart _isCorrect case QuestionType.reading always returned
// false) — a real §5 in a Tarix/Ona tili test silently scored 0.
//
// engine_smoke_test.dart's fixture and 30+ assertions are untouched by this
// file — this is a separate, additive group covering the new shape plus one
// test proving both shapes (whole-section Map-shaped reading AND list-shaped
// inline reading) coexist in the same spec without answer-key collisions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_scorer.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/question_widgets.dart' show EngineQNum;

// ── List-shaped reading fixture ─────────────────────────────────────────────
//
// Section "Manba" (list): [text_choice, reading{2 q}, reading{2 q}, yes_no]
//   list index 0 → text_choice            → key "Manba/0"
//   list index 1 → reading (2 inner qs)   → keys "Manba/1/0", "Manba/1/1"
//   list index 2 → reading (2 inner qs)   → keys "Manba/2/0", "Manba/2/1"
//   list index 3 → yes_no                 → key "Manba/3"
// questionCount == 6.

Map<String, dynamic> _readingItem(String title, String text, List<Map<String, dynamic>> qs) {
  return {'type': 'reading', 'title': title, 'text': text, 'qs': qs};
}

List<Map<String, dynamic>> _manbaSection() {
  return [
    {'type': 'text_choice', 'q': 'Q0', 'opts': ['A', 'B'], 'ans': 0},
    _readingItem('Passage One', 'Text one.', [
      {'type': 'text_choice', 'q': 'P1Q0', 'opts': ['A', 'B'], 'ans': 0},
      {'type': 'yes_no', 'q': 'P1Q1', 'ans': 'YES'},
    ]),
    _readingItem('Passage Two', 'Text two.', [
      {'type': 'text_choice', 'q': 'P2Q0', 'opts': ['A', 'B'], 'ans': 1},
      {'type': 'fill_blank', 'q': 'P2Q1', 'ans': 'dog'},
    ]),
    {'type': 'yes_no', 'q': 'Q3', 'ans': 'YES'},
  ];
}

Map<String, dynamic> _buildListShapedSpecJson() {
  return {
    'test_key': 'reading_inline_test_v1',
    'title': 'Reading Inline Test',
    'grade': 5,
    'version': 1,
    'parts': ['Manba'],
    'variants': {
      '1': {'Manba': _manbaSection()},
    },
  };
}

Map<String, dynamic> _allCorrectManba() {
  return {
    'Manba/0': 0,
    'Manba/1/0': 0,
    'Manba/1/1': 'YES',
    'Manba/2/0': 1,
    'Manba/2/1': 'dog',
    'Manba/3': 'YES',
  };
}

Map<String, dynamic> _allWrongManba() {
  return {
    'Manba/0': 1, // wrong: correct 0
    'Manba/1/0': 1, // wrong: correct 0
    'Manba/1/1': 'NO', // wrong: correct YES
    'Manba/2/0': 0, // wrong: correct 1
    'Manba/2/1': 'cat', // wrong: correct dog
    'Manba/3': 'NO', // wrong: correct YES
  };
}

// ── Combined spec — whole-section (Map-shaped) reading AND list-shaped
// inline reading in the same TestSpec (3-qaror: proves both shapes coexist
// without key collisions; "Passage" here mirrors engine_smoke_test.dart's
// English whole-section "Reading" fixture pattern). ──────────────────────

Map<String, dynamic> _buildCombinedSpecJson() {
  return {
    'test_key': 'reading_combined_test_v1',
    'title': 'Combined Reading Test',
    'grade': 5,
    'version': 1,
    'parts': ['Manba', 'Passage'],
    'variants': {
      '1': {
        'Manba': _manbaSection(),
        'Passage': {
          'title': 'Whole Section Passage',
          'text': 'A whole-section reading passage.',
          'qs': [
            {'type': 'text_choice', 'q': 'W0', 'opts': ['A', 'B'], 'ans': 0},
            {'type': 'text_choice', 'q': 'W1', 'opts': ['A', 'B'], 'ans': 1},
          ],
        },
      },
    },
  };
}

// ── _buildPayload subject-bucketing mirror (Task 1.6) ───────────────────────
//
// EngineHostScreen._buildPayload lives on the library-private
// _EngineHostScreenState (engine_host_screen.dart) and cannot be called
// directly from another test file — the same constraint engine_smoke_test.dart
// already documents for _isMathSection. This mirrors the exact contract
// _buildPayload implements and must stay in sync with it:
//   subject == null    → old per-section heuristic (isMathSection)
//   subject == "math"  → whole-test totals go to math, english stays {0,0}
//   subject == "english" → whole-test totals go to english, math stays {0,0}
//   subject == anything else (e.g. "tarix") → both {0,0}

bool _isMathSection(String name) {
  final n = name.trim().toLowerCase();
  return n == 'math' || n.startsWith('matema');
}

(int, int) _mathBucket(String? subject, List<SectionScore> sections, int totalCorrect, int totalQuestions) {
  if (subject == null) {
    int cor = 0, tot = 0;
    for (final s in sections) {
      if (_isMathSection(s.name)) {
        cor += s.correct;
        tot += s.total;
      }
    }
    return (cor, tot);
  }
  return subject == 'math' ? (totalCorrect, totalQuestions) : (0, 0);
}

(int, int) _englishBucket(String? subject, List<SectionScore> sections, int totalCorrect, int totalQuestions) {
  if (subject == null) {
    int cor = 0, tot = 0;
    for (final s in sections) {
      if (!_isMathSection(s.name)) {
        cor += s.correct;
        tot += s.total;
      }
    }
    return (cor, tot);
  }
  return subject == 'english' ? (totalCorrect, totalQuestions) : (0, 0);
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('list-shaped reading — TestSpec.fromJson', () {
    test('Manba section parses as a question list, not a reading container', () {
      final spec = TestSpec.fromJson(_buildListShapedSpecJson());
      final section = spec.sectionsForVariant('1').first;
      expect(section.isReading, isFalse);
    });

    test('list index 1 parses as a reading item with 2 inner questions', () {
      final spec = TestSpec.fromJson(_buildListShapedSpecJson());
      final section = spec.sectionsForVariant('1').first;
      expect(section.questions[1].type, QuestionType.reading);
      expect(section.questions[1].reading!.qs.length, 2);
    });

    test('questionCount == 6 (1 + 2 + 2 + 1)', () {
      final spec = TestSpec.fromJson(_buildListShapedSpecJson());
      final section = spec.sectionsForVariant('1').first;
      expect(section.questionCount, 6);
    });

    test('answerSlots keys follow the documented contract, in order', () {
      final spec = TestSpec.fromJson(_buildListShapedSpecJson());
      final section = spec.sectionsForVariant('1').first;
      expect(
        section.answerSlots.map((s) => s.key).toList(),
        ['Manba/0', 'Manba/1/0', 'Manba/1/1', 'Manba/2/0', 'Manba/2/1', 'Manba/3'],
      );
    });
  });

  group('list-shaped reading — TestScorer', () {
    late TestSpec spec;

    setUp(() {
      spec = TestSpec.fromJson(_buildListShapedSpecJson());
    });

    test('6/6 when every slot (including both inline passages) is correct', () {
      final result = TestScorer.score(spec, '1', _allCorrectManba());
      expect(result.totalCorrect, 6);
      expect(result.totalQuestions, 6);
      final sc = result.sectionScores.single;
      expect(sc.correct, 6);
      expect(sc.total, 6);
    });

    test('0/6 when every slot is wrong', () {
      final result = TestScorer.score(spec, '1', _allWrongManba());
      expect(result.totalCorrect, 0);
      expect(result.totalQuestions, 6);
    });

    test('partial: only the standalone questions correct, both passages wrong', () {
      final answers = <String, dynamic>{
        'Manba/0': 0, // correct
        'Manba/1/0': 1, // wrong
        'Manba/1/1': 'NO', // wrong
        'Manba/2/0': 0, // wrong
        'Manba/2/1': 'cat', // wrong
        'Manba/3': 'YES', // correct
      };
      final result = TestScorer.score(spec, '1', answers);
      expect(result.totalCorrect, 2);
      expect(result.totalQuestions, 6);
    });

    test('unanswered leaves the passage questions counted as wrong (not skipped)', () {
      // Only the two standalone questions answered — both inline reading
      // passages left untouched.
      final answers = <String, dynamic>{'Manba/0': 0, 'Manba/3': 'YES'};
      final result = TestScorer.score(spec, '1', answers);
      expect(result.totalCorrect, 2);
      expect(result.totalQuestions, 6);
    });

    test(
        'no sibling collision: {"Manba/3":"YES"} answers only the standalone '
        'yes_no at list index 3, not any inner reading question — regression '
        'guard for the rejected flat-renumbering key scheme', () {
      final result = TestScorer.score(spec, '1', {'Manba/3': 'YES'});
      expect(result.totalCorrect, 1);
      expect(result.totalQuestions, 6);
    });

    test(
        'a stale "Manba/1" container-style key (old broken scheme) matches no '
        'current slot and is silently ignored, not mismatched onto the new '
        '"Manba/1/0"/"Manba/1/1" slots', () {
      final result = TestScorer.score(spec, '1', {'Manba/1': 0});
      expect(result.totalCorrect, 0);
      expect(result.totalQuestions, 6);
    });

    test('detail has 6 rows with unique index 0..5', () {
      final result = TestScorer.score(spec, '1', _allCorrectManba());
      expect(result.questionResults.length, 6);
      expect(
        result.questionResults.map((r) => r.index).toSet(),
        {0, 1, 2, 3, 4, 5},
      );
    });
  });

  group('mixed spec — whole-section reading + list-shaped inline reading coexist', () {
    test('both shapes score independently in the same TestSpec', () {
      final spec = TestSpec.fromJson(_buildCombinedSpecJson());
      final sections = spec.sectionsForVariant('1');
      expect(sections.map((s) => s.name).toList(), ['Manba', 'Passage']);
      expect(sections[0].isReading, isFalse); // Manba: list-shaped
      expect(sections[1].isReading, isTrue); // Passage: whole-section Map-shaped

      final answers = <String, dynamic>{
        ..._allCorrectManba(),
        'Passage/0': 0, // correct
        'Passage/1': 1, // correct
      };
      final result = TestScorer.score(spec, '1', answers);

      expect(result.totalQuestions, 8); // 6 (Manba) + 2 (Passage)
      expect(result.totalCorrect, 8);

      final manba = result.sectionScores.firstWhere((s) => s.name == 'Manba');
      final passage = result.sectionScores.firstWhere((s) => s.name == 'Passage');
      expect(manba.correct, 6);
      expect(manba.total, 6);
      expect(passage.correct, 2);
      expect(passage.total, 2);
    });
  });

  group('list-shaped reading — TestEngine widget (render + progress)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets(
        'both inline passages render and EngineQNum numbers run 1..6 unique',
        (WidgetTester tester) async {
      final spec = TestSpec.fromJson(_buildListShapedSpecJson());

      await tester.pumpWidget(MaterialApp(
        home: TestEngine(
          spec: spec,
          variant: 1,
          firstName: 'Ism',
          lastName: 'Familiya',
          school: '56',
          studentId: '', // manual-entry — never resumes a saved attempt
          duration: const Duration(minutes: 10),
          onComplete: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      // Scorer-level tests above pass even while the render path is still
      // SizedBox.shrink() (Task 1.3 doesn't touch rendering) — only this
      // widget test actually proves the passages are drawn (Task 1.5).
      expect(find.text('Passage One'), findsOneWidget);
      expect(find.text('Passage Two'), findsOneWidget);

      final numbered = tester.widgetList<EngineQNum>(find.byType(EngineQNum));
      expect(numbered.length, 6); // no duplicate rendering, no missing slot
      expect(numbered.map((w) => w.index).toSet(), {0, 1, 2, 3, 4, 5});

      // Unmount to cancel TestEngine's countdown Timer before the test ends.
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('_buildPayload subject bucketing (Task 1.6 mirror — see comment above)', () {
    test('subject "tarix": both math and english buckets stay {0,0}', () {
      const sections = [
        SectionScore(name: 'Sanalar', correct: 8, total: 8),
        SectionScore(name: 'Manba', correct: 6, total: 6),
      ];
      final math = _mathBucket('tarix', sections, 14, 14);
      final eng = _englishBucket('tarix', sections, 14, 14);
      expect(math, (0, 0));
      expect(eng, (0, 0));
    });

    test('subject "math": whole-test totals land in math, english stays {0,0}', () {
      const sections = [SectionScore(name: 'Algebra', correct: 5, total: 5)];
      final math = _mathBucket('math', sections, 5, 5);
      final eng = _englishBucket('math', sections, 5, 5);
      expect(math, (5, 5));
      expect(eng, (0, 0));
    });

    test('subject null: old per-section-name heuristic, byte-identical to before', () {
      const sections = [
        SectionScore(name: 'Math', correct: 2, total: 2),
        SectionScore(name: 'Matematika', correct: 1, total: 1),
        SectionScore(name: 'English', correct: 1, total: 1),
        SectionScore(name: 'Reading', correct: 2, total: 2),
      ];
      final math = _mathBucket(null, sections, 6, 6);
      final eng = _englishBucket(null, sections, 6, 6);
      expect(math, (3, 3)); // Math(2) + Matematika(1)
      expect(eng, (3, 3)); // English(1) + Reading(2)
    });
  });
}
