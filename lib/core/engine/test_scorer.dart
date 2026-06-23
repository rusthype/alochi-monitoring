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
      if (section.isReading) {
        final sc = _scoreReading(section, answers);
        sectionScores.add(sc);
        totalCorrect += sc.correct;
        totalQuestions += sc.total;
      } else {
        final sc = _scoreQuestionList(section, answers);
        sectionScores.add(sc);
        totalCorrect += sc.correct;
        totalQuestions += sc.total;
      }
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

    return ScoredResult(
      testKey: spec.testKey,
      sectionScores: sectionScores,
      totalCorrect: totalCorrect,
      totalQuestions: totalQuestions,
      totalPct: totalPct,
      shields: shields,
      levelLabel: levelLabel,
      levelCefr: levelCefr,
      levelBgHex: levelBgHex,
      levelColHex: levelColHex,
    );
  }

  // ── Per-section scoring ─────────────────────────────────────────────────────

  static SectionScore _scoreQuestionList(
      SectionData section, Map<String, dynamic> answers) {
    int correct = 0;
    final qs = section.questions;
    for (int i = 0; i < qs.length; i++) {
      final key = '${section.name}/$i';
      final given = answers[key];
      if (_isCorrect(qs[i], given)) correct++;
    }
    return SectionScore(name: section.name, correct: correct, total: qs.length);
  }

  static SectionScore _scoreReading(
      SectionData section, Map<String, dynamic> answers) {
    final container = section.readingContainer!;
    int correct = 0;
    final qs = container.qs;
    for (int i = 0; i < qs.length; i++) {
      final key = '${section.name}/$i';
      final given = answers[key];
      if (_isCorrect(qs[i], given)) correct++;
    }
    return SectionScore(name: section.name, correct: correct, total: qs.length);
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
        return given.trim().toLowerCase() ==
            (q.strAns ?? '').trim().toLowerCase();

      case QuestionType.sentenceOrder:
        if (given is! String) return false;
        final typed = given.trim().toLowerCase().replaceAll(_trailRe, '');
        final expected =
            (q.strAns ?? '').trim().toLowerCase().replaceAll(_trailRe, '');
        return typed == expected;

      case QuestionType.reading:
        // reading is a container — should not appear directly in scoring
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
}
