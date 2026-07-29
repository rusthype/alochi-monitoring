// lib/features/interhouse/interhouse_scorer.dart
// Pure Dart scorer — no Flutter imports
import '../../core/engine/answer_normalization.dart';
import 'interhouse_data.dart';

// ── IhPartScore ──────────────────────────────────────────────────────────────

class IhPartScore {
  final String partName;
  final int score; // 0–6
  final int shields; // 1–5

  const IhPartScore({
    required this.partName,
    required this.score,
    required this.shields,
  });
}

// ── IhResult ─────────────────────────────────────────────────────────────────

class IhResult {
  final List<IhPartScore> parts; // 5 items
  final int total; // 0–30
  final int totalShields; // 5–25
  final IhLevel level;

  const IhResult({
    required this.parts,
    required this.total,
    required this.totalShields,
    required this.level,
  });

  int get totalPct => (total * 100 ~/ 30);
}

// ── IhScorer ─────────────────────────────────────────────────────────────────

class IhScorer {
  /// Converts a part score (0–6) → shields (1–5). MINIMUM 1 even at 0.
  static int shields(int s) =>
      s >= 6 ? 5 : s >= 5 ? 4 : s >= 4 ? 3 : s >= 3 ? 2 : 1;

  /// Scores all 5 parts.
  ///
  /// [answers] map keys:
  ///   'vocab'    → List<int?>   selected indices (null = unanswered)
  ///   'grammar'  → List<int?>   selected indices
  ///   'spelling' → List<String> typed values
  ///   'reading'  → List<dynamic> mixed: int? for mc, String for yn/fill
  ///   'sentences'→ List<String> typed values
  static IhResult score(
    IhVariant variant,
    Map<String, dynamic> answers,
    List<IhLevel> levels,
  ) {
    final vAns = (answers['vocab'] as List).cast<int?>();
    final gAns = (answers['grammar'] as List).cast<int?>();
    final spAns = (answers['spelling'] as List).cast<String>();
    final rAns = answers['reading'] as List<dynamic>;
    final senAns = (answers['sentences'] as List).cast<String>();

    // ── Vocabulary ──────────────────────────────────────────────────
    int cntV = 0;
    for (int i = 0; i < variant.vocab.length; i++) {
      if (i < vAns.length && vAns[i] == (variant.vocab[i].ans as int)) cntV++;
    }

    // ── Grammar ─────────────────────────────────────────────────────
    int cntG = 0;
    for (int i = 0; i < variant.grammar.length; i++) {
      if (i < gAns.length && gAns[i] == (variant.grammar[i].ans as int)) cntG++;
    }

    // ── Spelling ────────────────────────────────────────────────────
    int cntSp = 0;
    for (int i = 0; i < variant.spelling.length; i++) {
      final typed =
          i < spAns.length ? spAns[i].trim().toLowerCase() : '';
      final expected =
          (variant.spelling[i].ans as String).toLowerCase();
      if (typed == expected) cntSp++;
    }

    // ── Reading ─────────────────────────────────────────────────────
    int cntR = 0;
    final rQs = variant.reading.qs;
    for (int i = 0; i < rQs.length; i++) {
      final q = rQs[i];
      final a = i < rAns.length ? rAns[i] : null;
      if (q.type == 'yn') {
        if (a is String && a == (q.ans as String)) cntR++;
      } else if (q.type == 'mc') {
        if (a is int && a == (q.ans as int)) cntR++;
      } else if (q.type == 'fill') {
        final typed = (a is String) ? a.trim().toLowerCase() : '';
        final expected = (q.ans as String).toLowerCase();
        if (typed == expected) cntR++;
      }
    }

    // ── Writing / Sentences ─────────────────────────────────────────
    int cntSen = 0;
    final trailRe = RegExp(r'[.!?\s]+$');
    for (int i = 0; i < variant.sentences.length; i++) {
      final typed = expandContractions((i < senAns.length ? senAns[i] : '')
          .trim()
          .toLowerCase()
          .replaceAll(trailRe, ''));
      final expected = expandContractions((variant.sentences[i].ans as String)
          .toLowerCase()
          .replaceAll(trailRe, ''));
      if (typed == expected) cntSen++;
    }

    // ── Assemble ────────────────────────────────────────────────────
    final partScores = [cntV, cntG, cntSp, cntR, cntSen];
    final partNames = ['Vocabulary', 'Grammar', 'Spelling', 'Reading', 'Writing'];
    final partShields = partScores.map(shields).toList();
    final total = partScores.fold(0, (a, b) => a + b);
    final totalShields = partShields.fold(0, (a, b) => a + b);

    final level = levels.firstWhere(
      (l) => totalShields >= l.min,
      orElse: () => levels.last,
    );

    return IhResult(
      parts: List.generate(
        5,
        (i) => IhPartScore(
          partName: partNames[i],
          score: partScores[i],
          shields: partShields[i],
        ),
      ),
      total: total,
      totalShields: totalShields,
      level: level,
    );
  }
}
