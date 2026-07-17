// lib/core/engine/test_scorer.dart
// Generic scorer for JSON-driven test engine (Faza 3)
// Pure Dart — no Flutter imports.

import 'test_models.dart';

// ── SectionScore ──────────────────────────────────────────────────────────────

class SectionScore {
  final String name;
  final int correct;
  final int total;

  const SectionScore({
    required this.name,
    required this.correct,
    required this.total,
  });

  /// 0.0–100.0
  double get pct => total > 0 ? correct * 100.0 / total : 0.0;
}

// ── Per-question / per-topic detail (TZ §10 result analysis) ────────────────────

/// One answered question's outcome — feeds the per-§ accordion.
class QuestionResult {
  final String section;      // chapter/section name
  final int index;           // 0-based within its section
  final String questionText;
  final String? topic;       // e.g. "§17 Matnli masala"
  final String? category;    // e.g. "matnli"
  final int? bob;            // unit/chapter
  final bool correct;
  final Question question;
  final dynamic userAnswer;

  const QuestionResult({
    required this.section,
    required this.index,
    required this.questionText,
    required this.correct,
    required this.question,
    this.userAnswer,
    this.topic,
    this.category,
    this.bob,
  });
}

/// Aggregated score for one topic — feeds strong/weak + the 14-day plan.
class TopicScore {
  final String topic;
  final int correct;
  final int total;

  const TopicScore({required this.topic, required this.correct, required this.total});

  double get pct => total > 0 ? correct * 100.0 / total : 0.0;
}

// ── ScoredResult ──────────────────────────────────────────────────────────────

/// Unified result object returned by [TestScorer.score].
///
/// Faza 4 note — offline_queue.enqueueLocal payload mapping:
///   testKey        → "test_key"
///   totalCorrect   → "correct"
///   totalQuestions → "total"
///   totalPct       → "score_pct"
///   shields        → "shields"  (null if scoring absent)
///   levelLabel     → "level"    (null if scoring absent)
///   sectionScores  → "sections": [{"name":…,"correct":…,"total":…,"pct":…}]
class ScoredResult {
  final String testKey;
  final List<SectionScore> sectionScores;
  final int totalCorrect;
  final int totalQuestions;
  final double totalPct;

  // Per-§ analysis (TZ §10)
  final List<QuestionResult> questionResults;
  final List<TopicScore> topicScores;
  final List<TopicScore> unitScores;

  // Shield / level (only populated when TestSpec.scoring != null)
  final int? shields;
  final String? levelLabel;
  final String? levelCefr;
  final String? levelBgHex;
  final String? levelColHex;

  const ScoredResult({
    required this.testKey,
    required this.sectionScores,
    required this.totalCorrect,
    required this.totalQuestions,
    required this.totalPct,
    this.questionResults = const [],
    this.topicScores = const [],
    this.unitScores = const [],
    this.shields,
    this.levelLabel,
    this.levelCefr,
    this.levelBgHex,
    this.levelColHex,
  });
}

// ── TestScorer ────────────────────────────────────────────────────────────────

class TestScorer {
  // Trailing punctuation / whitespace pattern for sentence_order comparison
  static final _trailRe = RegExp(r'[.!?\s]+$');

  // Collapses runs of whitespace to a single space.
  static final _multiSpaceRe = RegExp(r'\s+');

  /// Normalizes a typed/expected string before comparison: trims, lowercases,
  /// maps curly apostrophe (’) and the Uzbek modifier-letter apostrophes
  /// ʻ (U+02BB, turned comma — used in "oʻ"/"gʻ") and ʼ (U+02BC, apostrophe
  /// letter) to straight ('), and collapses multiple whitespace to one.
  /// Applies to spelling, sentence_order and fill_blank. Without this, an
  /// AI-authored "oʻqituvchi" and a student-typed "o'qituvchi" compare as
  /// different strings even though they're the same word (Ona tili §2/§3).
  static String _normalize(String s) {
    return s
        .trim()
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll('ʻ', "'")
        .replaceAll('ʼ', "'")
        .replaceAll(_multiSpaceRe, ' ');
  }

  /// Score a completed test variant.
  ///
  /// [spec]       — the parsed TestSpec
  /// [variantKey] — e.g. "1", "2"
  /// [answers]    — flat map keyed by "$sectionName/$index"
  ///               Values:
  ///                 choice types    → int (selected index)
  ///                 yes_no          → String "YES" or "NO"
  ///                 spelling        → String (typed value)
  ///                 sentence_order  → String (typed value)
  ///                 fill_blank      → String (typed value)
  ///               Missing key = unanswered.
  static ScoredResult score(
    TestSpec spec,
    String variantKey,
    Map<String, dynamic> answers,
  ) {
    final sections = spec.sectionsForVariant(variantKey);
    final List<SectionScore> sectionScores = [];
    int totalCorrect = 0;
    int totalQuestions = 0;

    for (final section in sections) {
      final sc = _scoreSection(section, answers);
      sectionScores.add(sc);
      totalCorrect += sc.correct;
      totalQuestions += sc.total;
    }

    final totalPct = totalQuestions > 0
        ? totalCorrect * 100.0 / totalQuestions
        : 0.0;

    // Shield / level calculation (only if ScoringSpec present)
    int? shields;
    String? levelLabel;
    String? levelCefr;
    String? levelBgHex;
    String? levelColHex;

    if (spec.scoring != null) {
      final scoring = spec.scoring!;

      // Compute total shields from per-section correct counts
      // shieldsThresholds are highest-to-lowest: [6, 5, 4, 3] means
      // ≥6→5shields, ≥5→4shields, ≥4→3shields, ≥3→2shields, else 1shield
      int totalShields = 0;
      for (final sc in sectionScores) {
        totalShields += _correctToShields(sc.correct, scoring.shieldsThresholds);
      }
      shields = totalShields;

      // Find matching level (levels sorted highest-min first)
      if (scoring.levels.isNotEmpty) {
        final sortedLevels = List<ScoringLevel>.from(scoring.levels)
          ..sort((a, b) => b.min.compareTo(a.min));

        ScoringLevel? matched;
        for (final lvl in sortedLevels) {
          if (totalShields >= lvl.min) {
            matched = lvl;
            break;
          }
        }
        matched ??= sortedLevels.last;

        levelLabel = matched.label;
        levelCefr = matched.cefr;
        levelBgHex = matched.bgHex;
        levelColHex = matched.colHex;
      }
    }

    final detail = _buildDetail(spec, sections, answers);

    return ScoredResult(
      testKey: spec.testKey,
      sectionScores: sectionScores,
      totalCorrect: totalCorrect,
      totalQuestions: totalQuestions,
      totalPct: totalPct,
      questionResults: detail.$1,
      topicScores: detail.$2,
      unitScores: detail.$3,
      shields: shields,
      levelLabel: levelLabel,
      levelCefr: levelCefr,
      levelBgHex: levelBgHex,
      levelColHex: levelColHex,
    );
  }

  // ── Per-section scoring ─────────────────────────────────────────────────────

  /// Scores one section over its [SectionData.answerSlots] — the single
  /// definition of the key scheme, covering whole-section (Map-shaped)
  /// reading containers, plain question lists, AND list items that are
  /// themselves inline reading passages (Task 1.1).
  static SectionScore _scoreSection(
      SectionData section, Map<String, dynamic> answers) {
    int correct = 0;
    final slots = section.answerSlots;
    for (final slot in slots) {
      if (_isCorrect(slot.question, answers[slot.key])) correct++;
    }
    return SectionScore(name: section.name, correct: correct, total: slots.length);
  }

  // ── Answer correctness ──────────────────────────────────────────────────────

  static bool _isCorrect(Question q, dynamic given) {
    if (given == null) return false;

    switch (q.type) {
      case QuestionType.textChoice:
      case QuestionType.imageChoice:
        return given is int && given == q.ans;

      case QuestionType.yesNo:
        if (given is! String) return false;
        return given.trim().toUpperCase() == (q.yesNoAns ?? '').toUpperCase();

      case QuestionType.spelling:
      case QuestionType.fillBlank:
        if (given is! String) return false;
        return _normalize(given) == _normalize(q.strAns ?? '');

      case QuestionType.sentenceOrder:
        if (given is! String) return false;
        final typed = _normalize(given).replaceAll(_trailRe, '');
        final expected = _normalize(q.strAns ?? '').replaceAll(_trailRe, '');
        return typed == expected;

      case QuestionType.reading:
        // reading is a container, never an answerable slot itself —
        // SectionData.answerSlots (Task 1.1) expands its inner questions
        // into their own slots before scoring ever sees them, so this case
        // is unreachable in practice. Kept as a defensive fallback.
        return false;
    }
  }

  // ── Shields helper ──────────────────────────────────────────────────────────

  /// Convert a per-section correct count to shields using thresholds.
  /// thresholds: [6, 5, 4, 3] → ≥6:5sh, ≥5:4sh, ≥4:3sh, ≥3:2sh, else:1sh
  static int _correctToShields(int correct, List<int> thresholds) {
    if (thresholds.isEmpty) return 0;
    final sorted = List<int>.from(thresholds)..sort((a, b) => b.compareTo(a));
    for (int i = 0; i < sorted.length; i++) {
      if (correct >= sorted[i]) return sorted.length - i + 1;
    }
    return 1; // minimum 1 shield
  }

  // ── Per-§ detail builder (TZ §10) ───────────────────────────────────────────

  static (List<QuestionResult>, List<TopicScore>, List<TopicScore>) _buildDetail(
      TestSpec spec, List<SectionData> sections, Map<String, dynamic> answers) {
    final List<QuestionResult> results = [];
    for (final section in sections) {
      for (final slot in section.answerSlots) {
        results.add(QuestionResult(
          section: section.name,
          index: slot.displayIndex, // unique within the section
          questionText: slot.question.q ?? slot.question.strAns ?? '',
          topic: slot.question.topic,
          category: slot.question.category,
          bob: slot.question.bob,
          correct: _isCorrect(slot.question, answers[slot.key]),
          question: slot.question,
          userAnswer: answers[slot.key],
        ));
      }
    }

    final Map<String, List<QuestionResult>> byTopic = {};
    final Map<String, List<QuestionResult>> byUnit = {};
    for (final r in results) {
      final key = r.topic ?? r.category ?? r.section;
      (byTopic[key] ??= []).add(r);
      int? unitNum = r.bob;
      if (unitNum == null) {
        final searchStr = r.topic ?? r.category ?? r.section;
        final bobMatch = RegExp(r'(\d+)\s*-bob', caseSensitive: false).firstMatch(searchStr);
        final unitMatch = RegExp(r'Unit\s*(\d+)', caseSensitive: false).firstMatch(searchStr);
        if (bobMatch != null) {
          unitNum = int.tryParse(bobMatch.group(1)!);
        } else if (unitMatch != null) {
          unitNum = int.tryParse(unitMatch.group(1)!);
        }
      }
      
      // Fallback to TestSpec title if unit still null
      if (unitNum == null) {
        final title = spec.title;
        final bobMatch = RegExp(r'(\d+)\s*-bob', caseSensitive: false).firstMatch(title);
        final unitMatch = RegExp(r'Unit\s*(\d+)', caseSensitive: false).firstMatch(title);
        if (bobMatch != null) {
          unitNum = int.tryParse(bobMatch.group(1)!);
        } else if (unitMatch != null) {
          unitNum = int.tryParse(unitMatch.group(1)!);
        }
      }
      
      if (unitNum != null) {
        final unitKey = 'Unit $unitNum';
        (byUnit[unitKey] ??= []).add(r);
      }
    }
    
    final topics = byTopic.entries
        .map((e) => TopicScore(
              topic: e.key,
              correct: e.value.where((r) => r.correct).length,
              total: e.value.length,
            ))
        .toList()
      ..sort((a, b) => a.pct.compareTo(b.pct)); // weakest first
      
    final units = byUnit.entries
        .map((e) => TopicScore(
              topic: e.key,
              correct: e.value.where((r) => r.correct).length,
              total: e.value.length,
            ))
        .toList()
      ..sort((a, b) {
        final matchA = RegExp(r'\d+').firstMatch(a.topic);
        final matchB = RegExp(r'\d+').firstMatch(b.topic);
        final numA = matchA != null ? int.parse(matchA.group(0)!) : 0;
        final numB = matchB != null ? int.parse(matchB.group(0)!) : 0;
        return numA.compareTo(numB);
      });
      
    return (results, topics, units);
  }
}
