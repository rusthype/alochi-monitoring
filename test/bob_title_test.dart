// test/bob_title_test.dart
// Math World `bob_title` labeling (2026-07-20) — backend now sends an
// optional `bob_title` string alongside the existing per-question `bob`
// (chapter number). When both are present, TestScorer._buildDetail groups
// unitScores under "N-BOB — <title>" instead of the generic "Unit N" label.
// English World questions only ever carry `unit` (never `bob_title`), so
// their grouping must stay byte-identical to before ("Unit N").
//
// Covers:
//   1. A Math-shaped test (single 'Questions' part, like the real Math World
//      engine payload) with bob + bob_title on every question → unitScores
//      labeled "N-BOB — <title>", never "Unit N".
//   2. A Combined-shaped test (Math bob-questions + English unit-questions
//      in the same variant) → both label formats present simultaneously,
//      with no key collision and no dropped questions, even though the
//      underlying chapter/unit numbers overlap (Math bob=2 vs English
//      unit=2).

import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_scorer.dart';

// ── Math-shaped fixture (single 'Questions' part) ──────────────────────────

Map<String, dynamic> _mathSpecJson() {
  return {
    'test_key': 'math_world_smoke',
    'title': 'Math World',
    'grade': 3,
    'version': 1,
    'parts': ['Questions'],
    'variants': {
      '1': {
        'Questions': [
          {
            'type': 'text_choice',
            'q': 'Q1',
            'opts': ['A', 'B'],
            'ans': 0,
            'bob': 1,
            'bob_title': "Bir xonali sonlar",
          },
          {
            'type': 'text_choice',
            'q': 'Q2',
            'opts': ['A', 'B'],
            'ans': 0,
            'bob': 1,
            'bob_title': "Bir xonali sonlar",
          },
          {
            'type': 'text_choice',
            'q': 'Q3',
            'opts': ['A', 'B'],
            'ans': 1,
            'bob': 2,
            'bob_title':
                "Ikki xonali sonlar ustida qo'shish va ayirish amallari",
          },
        ],
      },
    },
  };
}

// ── Combined-shaped fixture (Math bob-questions + English unit-questions) ──

Map<String, dynamic> _combinedSpecJson() {
  return {
    'test_key': 'combined_smoke',
    'title': 'Combined Test',
    'grade': 5,
    'version': 1,
    'parts': ['Math', 'English'],
    'variants': {
      '1': {
        'Math': [
          {
            'type': 'text_choice',
            'q': 'M1',
            'opts': ['A', 'B'],
            'ans': 0,
            'bob': 1,
            'bob_title': "Bir xonali sonlar",
          },
          {
            'type': 'text_choice',
            'q': 'M2',
            'opts': ['A', 'B'],
            'ans': 0,
            'bob': 2,
            'bob_title': "Ikki xonali sonlar",
          },
        ],
        'English': [
          // No 'bob' / 'bob_title' — English World questions carry 'unit'
          // only, and fold into QuestionResult.bob via the fromJson
          // `unit` fallback, but bobTitle stays null.
          {
            'type': 'text_choice',
            'q': 'E1',
            'opts': ['A', 'B'],
            'ans': 0,
            'unit': 1,
          },
          {
            'type': 'text_choice',
            'q': 'E2',
            'opts': ['A', 'B'],
            'ans': 0,
            // Deliberately overlaps Math's bob=2 to prove no key collision.
            'unit': 2,
          },
        ],
      },
    },
  };
}

void main() {
  group('Math World bob_title labeling', () {
    late ScoredResult result;

    setUp(() {
      final spec = TestSpec.fromJson(_mathSpecJson());
      result = TestScorer.score(spec, '1', {
        'Questions/0': 0, // correct
        'Questions/1': 1, // wrong
        'Questions/2': 1, // correct
      });
    });

    test('unitScores is non-empty', () {
      expect(result.unitScores, isNotEmpty);
    });

    test('groups use "N-BOB — <title>" labels, not "Unit N"', () {
      final labels = result.unitScores.map((u) => u.topic).toList();
      expect(labels, contains("1-BOB — Bir xonali sonlar"));
      expect(
        labels,
        contains(
          "2-BOB — Ikki xonali sonlar ustida qo'shish va ayirish amallari",
        ),
      );
      expect(labels.any((l) => l.startsWith('Unit ')), isFalse);
    });

    test('bob=1 group aggregates both questions (1 correct / 2 total)', () {
      final g =
          result.unitScores.firstWhere((u) => u.topic.startsWith('1-BOB'));
      expect(g.correct, 1);
      expect(g.total, 2);
    });

    test('bob=2 group has the single question (1 correct / 1 total)', () {
      final g =
          result.unitScores.firstWhere((u) => u.topic.startsWith('2-BOB'));
      expect(g.correct, 1);
      expect(g.total, 1);
    });

    test('units sorted ascending by leading chapter number', () {
      final nums = result.unitScores
          .map((u) => int.parse(RegExp(r'\d+').firstMatch(u.topic)!.group(0)!))
          .toList();
      expect(nums, [1, 2]);
    });

    test('QuestionResult carries bobTitle through from Question', () {
      final qr = result.questionResults.firstWhere((r) => r.index == 0);
      expect(qr.bob, 1);
      expect(qr.bobTitle, "Bir xonali sonlar");
    });
  });

  group('Combined test — Math (bob) + English (unit) coexist', () {
    late ScoredResult result;

    setUp(() {
      final spec = TestSpec.fromJson(_combinedSpecJson());
      result = TestScorer.score(spec, '1', {
        'Math/0': 0, // correct
        'Math/1': 0, // correct
        'English/0': 0, // correct
        'English/1': 0, // correct
      });
    });

    test('produces both label formats simultaneously', () {
      final labels = result.unitScores.map((u) => u.topic).toSet();
      expect(labels, {
        "1-BOB — Bir xonali sonlar",
        "2-BOB — Ikki xonali sonlar",
        'Unit 1',
        'Unit 2',
      });
    });

    test('no collision even though bob=2 and unit=2 overlap numerically',
        () {
      // Four distinct groups, not merged into two.
      expect(result.unitScores.length, 4);
    });

    test('no dropped questions — every group has exactly 1 question', () {
      for (final u in result.unitScores) {
        expect(u.total, 1);
      }
    });

    test('English groups stay in the plain "Unit N" format (unchanged)', () {
      final englishGroups =
          result.unitScores.where((u) => u.topic.startsWith('Unit'));
      expect(englishGroups.length, 2);
      for (final u in englishGroups) {
        expect(u.topic, anyOf('Unit 1', 'Unit 2'));
      }
    });

    test('Math groups carry the richer bob_title label', () {
      final mathGroups =
          result.unitScores.where((u) => u.topic.contains('-BOB — '));
      expect(mathGroups.length, 2);
    });
  });
}
