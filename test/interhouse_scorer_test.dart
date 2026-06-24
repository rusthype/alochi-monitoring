// test/interhouse_scorer_test.dart
// Tests for IhScorer — pure Dart, no Flutter binding required.
// Uses flutter_test (available in dev_dependencies) because this is a Flutter project.

import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/features/interhouse/interhouse_data.dart';
import 'package:alochi_monitoring/features/interhouse/interhouse_scorer.dart';

// ── Fixture helpers ───────────────────────────────────────────────────────────

IhQuestion _mcImgQ(int ans) => IhQuestion(
    type: 'mc_img',
    ans: ans,
    opts: ['A', 'B', 'C', 'D'],
    q: 'q',
    img: 'lamp.png');

IhQuestion _mcQ(int ans) =>
    IhQuestion(type: 'mc', ans: ans, opts: ['a', 'b', 'c', 'd'], q: 'q');

IhQuestion _wordQ(String ans) =>
    IhQuestion(type: 'word', ans: ans, scramble: 't a c', opts: []);

IhQuestion _ynQ(String ans, String qText) =>
    IhQuestion(type: 'yn', ans: ans, q: qText, opts: []);

IhQuestion _fillQ(String ans) =>
    IhQuestion(type: 'fill', ans: ans, q: 'fill?', opts: []);

IhQuestion _sentenceQ(String ans, String words) =>
    IhQuestion(type: 'sentence', ans: ans, words: words, opts: []);

/// Standard fixture variant:
///   vocab   — 6 mc_img, ans=0
///   grammar — 6 mc,     ans=1
///   spelling— 6 word,   ans='cat'
///   reading — 2 yn + 2 mc + 2 fill
///   sentences — 6 sentence, ans='It is not a car.'
IhVariant buildFixtureVariant() {
  final vocab = List.generate(6, (_) => _mcImgQ(0));
  final grammar = List.generate(6, (_) => _mcQ(1));
  final spelling = List.generate(6, (_) => _wordQ('cat'));

  final readingQs = [
    _ynQ('YES', 'Is it?'),
    _ynQ('NO', 'Not?'),
    IhQuestion(type: 'mc', ans: 0, opts: ['A', 'B', 'C'], q: 'mc?'),
    IhQuestion(type: 'mc', ans: 2, opts: ['A', 'B', 'C'], q: 'mc2?'),
    _fillQ('cat'),
    _fillQ('Dog'), // upper-case answer — matching must be case-insensitive
  ];
  final reading =
      IhReading(img: 'r07.png', title: 'T', text: 'tx', qs: readingQs);

  final sentences = List.generate(
    6,
    (_) => _sentenceQ('It is not a car.', 'not/a/is/It/car'),
  );

  return IhVariant(
    vocab: vocab,
    grammar: grammar,
    spelling: spelling,
    reading: reading,
    sentences: sentences,
  );
}

List<IhLevel> buildLevels() => [
      IhLevel(
          min: 23,
          label: 'Outstanding',
          cambridge: 'A2 Flyers',
          cefr: 'A1 to A2',
          bg: '#E6F4EA',
          col: '#1E6B3A'),
      IhLevel(
          min: 18,
          label: 'Very Good',
          cambridge: 'A1 Movers',
          cefr: 'A1',
          bg: '#D6E4F0',
          col: '#0C447C'),
      IhLevel(
          min: 13,
          label: 'Good',
          cambridge: 'A1 Movers',
          cefr: 'A1',
          bg: '#FFF3CD',
          col: '#856404'),
      IhLevel(
          min: 8,
          label: 'Satisfactory',
          cambridge: 'Pre-A1 to A1',
          cefr: 'Pre-A1',
          bg: '#FDE8EF',
          col: '#7B2041'),
      IhLevel(
          min: 0,
          label: 'Needs Practice',
          cambridge: 'Pre-A1 Starters',
          cefr: 'Pre-A1',
          bg: '#F1EFE8',
          col: '#555'),
    ];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ════════════════════════════════════════════════════════
  // shields()
  // ════════════════════════════════════════════════════════
  group('IhScorer.shields', () {
    test('score 0 → 1 (floor-1 rule, not 0)',
        () => expect(IhScorer.shields(0), 1));
    test('score 1 → 1', () => expect(IhScorer.shields(1), 1));
    test('score 2 → 1', () => expect(IhScorer.shields(2), 1));
    test('score 3 → 2', () => expect(IhScorer.shields(3), 2));
    test('score 4 → 3', () => expect(IhScorer.shields(4), 3));
    test('score 5 → 4', () => expect(IhScorer.shields(5), 4));
    test('score 6 → 5', () => expect(IhScorer.shields(6), 5));
  });

  // ════════════════════════════════════════════════════════
  // score() — all correct
  // ════════════════════════════════════════════════════════
  group('IhScorer.score — all correct', () {
    test(
        'all correct → [6,6,6,6,6], total=30, totalShields=25, level=Outstanding',
        () {
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': [0, 0, 0, 0, 0, 0],
        'grammar': [1, 1, 1, 1, 1, 1],
        'spelling': ['cat', 'cat', 'cat', 'cat', 'cat', 'cat'],
        // reading: yn(YES), yn(NO), mc(0), mc(2), fill(cat), fill(dog) — case-insensitive
        'reading': ['YES', 'NO', 0, 2, 'cat', 'dog'],
        'sentences': [
          'It is not a car.',
          'It is not a car.',
          'It is not a car.',
          'It is not a car.',
          'It is not a car.',
          'It is not a car.',
        ],
      };
      final result = IhScorer.score(v, answers, buildLevels());

      expect(result.parts.map((p) => p.score).toList(), [6, 6, 6, 6, 6]);
      expect(result.parts.map((p) => p.shields).toList(), [5, 5, 5, 5, 5]);
      expect(result.total, 30);
      expect(result.totalShields, 25);
      expect(result.level.label, 'Outstanding');
      expect(result.totalPct, 100);
    });
  });

  // ════════════════════════════════════════════════════════
  // score() — all blank / wrong
  // ════════════════════════════════════════════════════════
  group('IhScorer.score — all blank/wrong', () {
    test(
        'all unanswered → scores [0,0,0,0,0], shields [1,1,1,1,1], Needs Practice',
        () {
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': List<int?>.filled(6, null),
        'grammar': List<int?>.filled(6, null),
        'spelling': List<String>.filled(6, ''),
        'reading': List<dynamic>.filled(6, null),
        'sentences': List<String>.filled(6, ''),
      };
      final result = IhScorer.score(v, answers, buildLevels());

      expect(result.parts.every((p) => p.score == 0), isTrue);
      expect(
        result.parts.every((p) => p.shields == 1),
        isTrue,
        reason: 'floor-1 rule: blank still gives 1 shield per part',
      );
      expect(result.totalShields, 5);
      expect(result.total, 0);
      expect(result.level.label, 'Needs Practice');
      expect(result.totalPct, 0);
    });

    test('wrong MC indices → 0 score on vocab and grammar', () {
      final v = buildFixtureVariant();
      // vocab ans=0 → wrong answer 1; grammar ans=1 → wrong answer 0
      final answers = <String, dynamic>{
        'vocab': [1, 1, 1, 1, 1, 1],
        'grammar': [0, 0, 0, 0, 0, 0],
        'spelling': List<String>.filled(6, ''),
        'reading': List<dynamic>.filled(6, null),
        'sentences': List<String>.filled(6, ''),
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts[0].score, 0, reason: 'vocab: all wrong index');
      expect(result.parts[1].score, 0, reason: 'grammar: all wrong index');
    });
  });

  // ════════════════════════════════════════════════════════
  // score() — answer normalisation
  // ════════════════════════════════════════════════════════
  group('IhScorer.score — answer normalisation', () {
    test('spelling is case-insensitive (CAT matches cat)', () {
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': List<int?>.filled(6, null),
        'grammar': List<int?>.filled(6, null),
        'spelling': ['CAT', 'CAT', 'CAT', 'CAT', 'CAT', 'CAT'],
        'reading': List<dynamic>.filled(6, null),
        'sentences': List<String>.filled(6, ''),
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts[2].score, 6,
          reason: 'uppercase spelling should still match');
    });

    test('spelling trims whitespace (  cat  matches cat)', () {
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': List<int?>.filled(6, null),
        'grammar': List<int?>.filled(6, null),
        'spelling': ['  cat  ', ' cat', 'cat ', '  cat', 'cat  ', ' CAT '],
        'reading': List<dynamic>.filled(6, null),
        'sentences': List<String>.filled(6, ''),
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts[2].score, 6,
          reason: 'whitespace-padded spelling should match');
    });

    test(
        'sentence strips trailing period (no period still matches answer with period)',
        () {
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': List<int?>.filled(6, null),
        'grammar': List<int?>.filled(6, null),
        'spelling': List<String>.filled(6, ''),
        'reading': List<dynamic>.filled(6, null),
        'sentences':
            List<String>.filled(6, 'It is not a car'), // no trailing period
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts[4].score, 6,
          reason:
              'sentence without trailing period should match answer ending with period');
    });

    test('sentence strips trailing exclamation mark', () {
      // Build a variant where sentence ans ends with !
      final sentenceWithBang = List.generate(
        6,
        (_) => _sentenceQ('It is not a car!', 'not/a/is/It/car'),
      );
      final v = IhVariant(
        vocab: buildFixtureVariant().vocab,
        grammar: buildFixtureVariant().grammar,
        spelling: buildFixtureVariant().spelling,
        reading: buildFixtureVariant().reading,
        sentences: sentenceWithBang,
      );
      final answers = <String, dynamic>{
        'vocab': List<int?>.filled(6, null),
        'grammar': List<int?>.filled(6, null),
        'spelling': List<String>.filled(6, ''),
        'reading': List<dynamic>.filled(6, null),
        'sentences': List<String>.filled(6, 'It is not a car'), // no trailing !
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts[4].score, 6,
          reason: 'trailing ! should be stripped before comparison');
    });

    test(
        'yn answer is case-sensitive (YES matches YES, yes does NOT match YES)',
        () {
      final v = buildFixtureVariant();
      // reading[0] is yn with ans='YES', reading[1] is yn with ans='NO'
      final answersCorrect = <String, dynamic>{
        'vocab': List<int?>.filled(6, null),
        'grammar': List<int?>.filled(6, null),
        'spelling': List<String>.filled(6, ''),
        'reading': ['YES', 'NO', null, null, null, null],
        'sentences': List<String>.filled(6, ''),
      };
      final resultCorrect = IhScorer.score(v, answersCorrect, buildLevels());
      expect(resultCorrect.parts[3].score, 2,
          reason: 'uppercase YES/NO should match');

      final answersLower = <String, dynamic>{
        'vocab': List<int?>.filled(6, null),
        'grammar': List<int?>.filled(6, null),
        'spelling': List<String>.filled(6, ''),
        'reading': [
          'yes',
          'no',
          null,
          null,
          null,
          null
        ], // lowercase should NOT match
        'sentences': List<String>.filled(6, ''),
      };
      final resultLower = IhScorer.score(v, answersLower, buildLevels());
      expect(resultLower.parts[3].score, 0,
          reason: 'lowercase yes/no should NOT match (yn is exact-match)');
    });

    test('reading fill is case-insensitive (dog matches Dog)', () {
      final v = buildFixtureVariant();
      // reading[4]=fill(cat), reading[5]=fill(Dog) — 'dog' should match 'Dog'
      final answers = <String, dynamic>{
        'vocab': List<int?>.filled(6, null),
        'grammar': List<int?>.filled(6, null),
        'spelling': List<String>.filled(6, ''),
        'reading': [null, null, null, null, 'CAT', 'DOG'],
        'sentences': List<String>.filled(6, ''),
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts[3].score, 2,
          reason: 'case-insensitive fill: CAT=cat, DOG=Dog');
    });
  });

  // ════════════════════════════════════════════════════════
  // score() — level thresholds (based on totalShields)
  // ════════════════════════════════════════════════════════
  group('IhScorer.score — level thresholds', () {
    // Helper: build answers that yield a specific number of correct answers
    // across all 5 parts (each part has 6 questions).
    // We'll use vocab (mc_img, ans=0) to control score exactly.
    // For N total correct out of 30: put N in vocab+grammar slots (each 0-6),
    // rest blank.

    IhResult scoreWithTotalCorrect(int totalCorrect) {
      assert(totalCorrect >= 0 && totalCorrect <= 30);
      // Distribute correct answers: fill vocab first (0-6), then grammar (0-6), etc.
      int remaining = totalCorrect;

      int vocabCorrect = remaining.clamp(0, 6);
      remaining -= vocabCorrect;
      int grammarCorrect = remaining.clamp(0, 6);
      remaining -= grammarCorrect;
      int spellingCorrect = remaining.clamp(0, 6);
      remaining -= spellingCorrect;
      int readingCorrect = remaining.clamp(0, 6);
      remaining -= readingCorrect;
      int sentenceCorrect = remaining.clamp(0, 6);

      final v = buildFixtureVariant();

      // Build vocab answers: first vocabCorrect are correct (0), rest null
      final vocabAns =
          List<int?>.generate(6, (i) => i < vocabCorrect ? 0 : null);
      final grammarAns =
          List<int?>.generate(6, (i) => i < grammarCorrect ? 1 : null);
      final spellingAns =
          List<String>.generate(6, (i) => i < spellingCorrect ? 'cat' : '');

      // Reading: yn(YES), yn(NO), mc(0), mc(2), fill(cat), fill(dog)
      final readingAns = <dynamic>[null, null, null, null, null, null];
      final correctReadingAns = ['YES', 'NO', 0, 2, 'cat', 'dog'];
      for (int i = 0; i < readingCorrect; i++) {
        readingAns[i] = correctReadingAns[i];
      }

      final sentenceAns = List<String>.generate(
          6, (i) => i < sentenceCorrect ? 'It is not a car.' : '');

      return IhScorer.score(
          v,
          {
            'vocab': vocabAns,
            'grammar': grammarAns,
            'spelling': spellingAns,
            'reading': readingAns,
            'sentences': sentenceAns,
          },
          buildLevels());
    }

    // Levels use totalShields (not total correct):
    //   Outstanding:   shields >= 23
    //   Very Good:     shields >= 18
    //   Good:          shields >= 13
    //   Satisfactory:  shields >= 8
    //   Needs Practice: shields >= 0

    test('all 30 correct → Outstanding (totalShields=25)', () {
      final result = scoreWithTotalCorrect(30);
      expect(result.totalShields, 25);
      expect(result.level.label, 'Outstanding');
    });

    test('all 0 correct → Needs Practice (totalShields=5)', () {
      final result = scoreWithTotalCorrect(0);
      expect(result.totalShields, 5);
      expect(result.level.label, 'Needs Practice');
    });

    test('5 correct (1 per part) → shields=[1,1,1,1,1]=5 → Needs Practice', () {
      // 5 parts, 1 correct each → shields=1 each → totalShields=5 → Needs Practice
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': [0, null, null, null, null, null],
        'grammar': [1, null, null, null, null, null],
        'spelling': ['cat', '', '', '', '', ''],
        'reading': ['YES', null, null, null, null, null],
        'sentences': ['It is not a car.', '', '', '', '', ''],
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.total, 5);
      expect(result.totalShields, 5);
      expect(result.level.label, 'Needs Practice');
    });

    test(
        '6 correct per part (all 6s) → shields=5 each → totalShields=25 → Outstanding',
        () {
      final result = scoreWithTotalCorrect(30);
      expect(result.parts.map((p) => p.shields).toList(), [5, 5, 5, 5, 5]);
      expect(result.totalShields, 25);
      expect(result.level.label, 'Outstanding');
    });

    test('3 correct per part → shields=2 each → totalShields=10 → Satisfactory',
        () {
      // 3 per part = 15 total, shields: 2 each → totalShields=10 → Good (>=13? no, 10>=8 → Satisfactory)
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': [0, 0, 0, null, null, null],
        'grammar': [1, 1, 1, null, null, null],
        'spelling': ['cat', 'cat', 'cat', '', '', ''],
        'reading': ['YES', 'NO', 0, null, null, null],
        'sentences': [
          'It is not a car.',
          'It is not a car.',
          'It is not a car.',
          '',
          '',
          ''
        ],
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts.every((p) => p.score == 3), isTrue);
      expect(result.parts.every((p) => p.shields == 2), isTrue);
      expect(result.totalShields, 10);
      expect(result.level.label, 'Satisfactory');
    });

    test('4 correct per part → shields=3 each → totalShields=15 → Good', () {
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': [0, 0, 0, 0, null, null],
        'grammar': [1, 1, 1, 1, null, null],
        'spelling': ['cat', 'cat', 'cat', 'cat', '', ''],
        'reading': ['YES', 'NO', 0, 2, null, null],
        'sentences': [
          'It is not a car.',
          'It is not a car.',
          'It is not a car.',
          'It is not a car.',
          '',
          ''
        ],
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts.every((p) => p.score == 4), isTrue);
      expect(result.parts.every((p) => p.shields == 3), isTrue);
      expect(result.totalShields, 15);
      expect(result.level.label, 'Good');
    });

    test('5 correct per part → shields=4 each → totalShields=20 → Very Good',
        () {
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': [0, 0, 0, 0, 0, null],
        'grammar': [1, 1, 1, 1, 1, null],
        'spelling': ['cat', 'cat', 'cat', 'cat', 'cat', ''],
        'reading': ['YES', 'NO', 0, 2, 'cat', null],
        'sentences': [
          'It is not a car.',
          'It is not a car.',
          'It is not a car.',
          'It is not a car.',
          'It is not a car.',
          ''
        ],
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts.every((p) => p.score == 5), isTrue);
      expect(result.parts.every((p) => p.shields == 4), isTrue);
      expect(result.totalShields, 20);
      expect(result.level.label, 'Very Good');
    });
  });

  // ════════════════════════════════════════════════════════
  // score() — partial / edge cases
  // ════════════════════════════════════════════════════════
  group('IhScorer.score — edge cases', () {
    test('totalPct = total * 100 ~/ 30 (integer division)', () {
      final v = buildFixtureVariant();
      // 15 correct = 50%
      final answers = <String, dynamic>{
        'vocab': [0, 0, 0, 0, 0, 0], // 6
        'grammar': [1, 1, 1, 1, 1, 1], // 6
        'spelling': ['cat', 'cat', 'cat', '', '', ''], // 3
        'reading': List<dynamic>.filled(6, null), // 0
        'sentences': List<String>.filled(6, ''), // 0
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.total, 15);
      expect(result.totalPct, 15 * 100 ~/ 30); // 50
    });

    test('parts list has exactly 5 elements', () {
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': List<int?>.filled(6, null),
        'grammar': List<int?>.filled(6, null),
        'spelling': List<String>.filled(6, ''),
        'reading': List<dynamic>.filled(6, null),
        'sentences': List<String>.filled(6, ''),
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts.length, 5);
    });

    test(
        'parts are named in order: Vocabulary, Grammar, Spelling, Reading, Writing',
        () {
      final v = buildFixtureVariant();
      final answers = <String, dynamic>{
        'vocab': List<int?>.filled(6, null),
        'grammar': List<int?>.filled(6, null),
        'spelling': List<String>.filled(6, ''),
        'reading': List<dynamic>.filled(6, null),
        'sentences': List<String>.filled(6, ''),
      };
      final result = IhScorer.score(v, answers, buildLevels());
      expect(result.parts[0].partName, 'Vocabulary');
      expect(result.parts[1].partName, 'Grammar');
      expect(result.parts[2].partName, 'Spelling');
      expect(result.parts[3].partName, 'Reading');
      expect(result.parts[4].partName, 'Writing');
    });
  });
}
