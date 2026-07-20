// lib/core/engine/test_models.dart
// Unified test schema Dart models — JSON-driven test engine (Faza 3)
// No Flutter imports — pure Dart, safe for use in scorer/logic layers too.

import 'package:flutter/foundation.dart' show debugPrint;

// ── Question types ─────────────────────────────────────────────────────────────

enum QuestionType {
  textChoice,    // {q, opts[], ans:index}
  imageChoice,   // {img, q, opts[], ans:index}
  spelling,      // {scramble, ans:str}
  sentenceOrder, // {words, ans:str}
  reading,       // CONTAINER {img,title,text,qs:[...]}
  yesNo,         // {q, ans:"YES"|"NO"}
  fillBlank,     // {q, ans:str}
}

QuestionType? _parseType(String? raw) {
  switch (raw) {
    case 'text_choice':
      return QuestionType.textChoice;
    case 'image_choice':
      return QuestionType.imageChoice;
    case 'spelling':
      return QuestionType.spelling;
    case 'sentence_order':
      return QuestionType.sentenceOrder;
    case 'reading':
      return QuestionType.reading;
    case 'yes_no':
      return QuestionType.yesNo;
    case 'fill_blank':
      return QuestionType.fillBlank;
    default:
      return null;
  }
}

// ── Question ───────────────────────────────────────────────────────────────────

class Question {
  final QuestionType type;

  // Shared / multiple types
  final String? q;       // question text (text_choice, image_choice, yes_no, fill_blank)
  final List<String> opts; // options (text_choice, image_choice)
  final int ans;         // answer index for choice types (0-based)

  // image_choice, reading container
  final String? img;

  // spelling
  final String? scramble;

  // sentence_order
  final String? words;

  // yes_no
  final String? yesNoAns; // "YES" or "NO"

  // fill_blank / spelling / sentence_order
  final String? strAns;  // string answer

  // reading container
  final ReadingSection? reading;

  // topic (optional metadata — carried through for reporting)
  final String? topic;

  // geometry diagram (inline SVG string) + TZ reporting metadata
  final String? svg;
  final int? bob;
  final String? bobTitle; // human-readable chapter/unit title (Math World)
  final String? category;

  const Question({
    required this.type,
    this.q,
    this.opts = const [],
    this.ans = 0,
    this.img,
    this.scramble,
    this.words,
    this.yesNoAns,
    this.strAns,
    this.reading,
    this.topic,
    this.svg,
    this.bob,
    this.bobTitle,
    this.category,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString();
    final type = _parseType(rawType);

    // Metadata carried on every question type (TZ per-§ reporting + geometry SVG).
    final topic = json['topic']?.toString() ?? json['t']?.toString();
    final svg = json['svg']?.toString();
    int? parseUnit(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toInt();
      if (val is String) {
        final match = RegExp(r'\d+').firstMatch(val);
        if (match != null) return int.tryParse(match.group(0)!);
      }
      return null;
    }
    final bob = parseUnit(json['bob']) ?? parseUnit(json['unit']);
    final bobTitle = json['bob_title']?.toString();
    final category = json['category']?.toString();

    if (type == null) {
      debugPrint('[TestEngine] Unknown question type "$rawType", falling back to text_choice');
      // Safe fallback — treat as text_choice with empty opts so engine can render
      return Question(
        type: QuestionType.textChoice,
        q: json['q']?.toString(),
        opts: _parseOpts(json['opts']),
        ans: (json['ans'] as num?)?.toInt() ?? 0,
        topic: topic, svg: svg, bob: bob, bobTitle: bobTitle, category: category,
      );
    }

    switch (type) {
      case QuestionType.textChoice:
        return Question(
          type: type,
          q: json['q']?.toString(),
          opts: _parseOpts(json['opts']),
          ans: (json['ans'] as num?)?.toInt() ?? 0,
          topic: topic, svg: svg, bob: bob, bobTitle: bobTitle, category: category,
        );

      case QuestionType.imageChoice:
        return Question(
          type: type,
          img: json['img']?.toString(),
          q: json['q']?.toString(),
          opts: _parseOpts(json['opts']),
          ans: (json['ans'] as num?)?.toInt() ?? 0,
          topic: topic, svg: svg, bob: bob, bobTitle: bobTitle, category: category,
        );

      case QuestionType.spelling:
        return Question(
          type: type,
          img: json['img']?.toString(),
          scramble: json['scramble']?.toString(),
          strAns: json['ans']?.toString(),
          topic: topic, svg: svg, bob: bob, bobTitle: bobTitle, category: category,
        );

      case QuestionType.sentenceOrder:
        return Question(
          type: type,
          words: json['words']?.toString(),
          strAns: json['ans']?.toString(),
          topic: topic, svg: svg, bob: bob, bobTitle: bobTitle, category: category,
        );

      case QuestionType.reading:
        return Question(
          type: type,
          reading: ReadingSection.fromJson(json),
          topic: topic, svg: svg, bob: bob, bobTitle: bobTitle, category: category,
        );

      case QuestionType.yesNo:
        return Question(
          type: type,
          q: json['q']?.toString(),
          yesNoAns: json['ans']?.toString().toUpperCase(),
          topic: topic, svg: svg, bob: bob, bobTitle: bobTitle, category: category,
        );

      case QuestionType.fillBlank:
        return Question(
          type: type,
          q: json['q']?.toString(),
          strAns: json['ans']?.toString(),
          topic: topic, svg: svg, bob: bob, bobTitle: bobTitle, category: category,
        );
    }
  }

  static List<String> _parseOpts(dynamic raw) {
    if (raw == null) return [];
    if (raw is! List) return [];
    if (raw.isEmpty) return [];
    return raw.map((e) => e?.toString() ?? '').toList();
  }
}

// ── ReadingSection ─────────────────────────────────────────────────────────────

class ReadingSection {
  final String? img;
  final String title;
  final String text;
  final List<Question> qs;

  const ReadingSection({
    this.img,
    required this.title,
    required this.text,
    required this.qs,
  });

  factory ReadingSection.fromJson(Map<String, dynamic> json) {
    final rawQs = json['qs'];
    final List<Question> qs = [];
    if (rawQs is List && rawQs.isNotEmpty) {
      for (final item in rawQs) {
        if (item is Map<String, dynamic>) {
          try {
            qs.add(Question.fromJson(item));
          } catch (e) {
            debugPrint('[TestEngine] ReadingSection.qs parse error: $e');
          }
        }
      }
    }
    return ReadingSection(
      img: json['img']?.toString(),
      title: json['title']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      qs: qs,
    );
  }
}

// ── AnswerSlot ────────────────────────────────────────────────────────────────

/// One answerable question within a section, flattened out of whichever
/// shape it actually lives in (a plain list item, or a question nested
/// inside an inline `type:"reading"` list item). This is the single
/// definition of the answers-map key scheme — everything that used to
/// hand-roll `'${section.name}/$i'` (scorer, engine progress tracking,
/// section body builders) now reads it from [SectionData.answerSlots]
/// instead of re-deriving it.
class AnswerSlot {
  /// Answers-map key.
  ///   `'$sectionName/$i'`     — direct list item / whole-section reading qs
  ///   `'$sectionName/$i/$j'`  — question `j` inside an inline reading
  ///                             passage that is list item `i`
  /// The two shapes can never collide: a sibling key always has exactly 2
  /// segments, an inline-reading key always has exactly 3.
  final String key;

  final Question question;

  /// Running position of this slot within the section (0-based), independent
  /// of the underlying list index. Feeds question numbering (EngineQNum) and
  /// per-§ detail rows so an inline reading passage's inner questions don't
  /// disrupt the numbering of the questions around it.
  final int displayIndex;

  const AnswerSlot({
    required this.key,
    required this.question,
    required this.displayIndex,
  });
}

// ── ScoringLevel ──────────────────────────────────────────────────────────────

class ScoringLevel {
  final int min;
  final String label;
  final String? cefr;
  final String? bgHex;   // e.g. "#E6F4EA"
  final String? colHex;  // e.g. "#1E6B3A"

  const ScoringLevel({
    required this.min,
    required this.label,
    this.cefr,
    this.bgHex,
    this.colHex,
  });

  factory ScoringLevel.fromJson(Map<String, dynamic> json) {
    return ScoringLevel(
      min: (json['min'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString() ?? '',
      cefr: json['cefr']?.toString(),
      bgHex: json['bg']?.toString(),
      colHex: json['col']?.toString(),
    );
  }
}

// ── ScoringSpec ───────────────────────────────────────────────────────────────

class ScoringSpec {
  /// Per-section shields thresholds (highest-first), e.g. [6, 5, 4, 3]
  final List<int> shieldsThresholds;
  final List<ScoringLevel> levels;

  const ScoringSpec({
    required this.shieldsThresholds,
    required this.levels,
  });

  factory ScoringSpec.fromJson(Map<String, dynamic> json) {
    final rawTh = json['shields_thresholds'];
    final List<int> thresholds = [];
    if (rawTh is List && rawTh.isNotEmpty) {
      for (final t in rawTh) {
        if (t is num) thresholds.add(t.toInt());
      }
    }

    final rawLvl = json['levels'];
    final List<ScoringLevel> levels = [];
    if (rawLvl is List && rawLvl.isNotEmpty) {
      for (final l in rawLvl) {
        if (l is Map<String, dynamic>) {
          levels.add(ScoringLevel.fromJson(l));
        }
      }
    }

    return ScoringSpec(shieldsThresholds: thresholds, levels: levels);
  }
}

// ── SectionData ───────────────────────────────────────────────────────────────

/// A named section: either a list of questions OR a reading container.
class SectionData {
  final String name;

  /// Human-facing label for this section. Math World's raw part name is
  /// literally "Questions" (kept as-is on [name] since it's load-bearing
  /// for answer-map keys — see [_buildAnswerSlots]) — this reads as
  /// "Matematika" in the UI instead. Every other section name (English
  /// World skill sections, etc.) passes through unchanged.
  String get displayName => name == 'Questions' ? 'Matematika' : name;

  /// Non-reading questions (text_choice, image_choice, spelling, sentence_order,
  /// yes_no, fill_blank). Empty when this section is a reading container.
  /// May also contain `type:"reading"` items — an inline reading passage
  /// living alongside sibling questions in the same list (see [answerSlots]).
  final List<Question> questions;

  /// Non-null when the whole section is a reading passage container.
  final ReadingSection? readingContainer;

  /// Flat, ordered list of answerable slots for this section — the single
  /// source of truth for answer-map keys, question counts, and display
  /// numbering (see [AnswerSlot]).
  ///
  /// Built once here, NOT a getter: `_BottomNav` rebuilds one SectionData
  /// per section on every frame via `List.generate(sections.length, ...)`
  /// (test_engine.dart) — an allocating getter would reallocate a new List
  /// every frame for every section instead of once at parse time.
  late final List<AnswerSlot> answerSlots;

  SectionData({
    required this.name,
    this.questions = const [],
    this.readingContainer,
  }) {
    answerSlots = _buildAnswerSlots();
  }

  List<AnswerSlot> _buildAnswerSlots() {
    final slots = <AnswerSlot>[];

    if (readingContainer != null) {
      // Whole-section (Map-shaped) reading container — unchanged 2-segment
      // key scheme, one slot per inner question, in order.
      final qs = readingContainer!.qs;
      for (var j = 0; j < qs.length; j++) {
        slots.add(AnswerSlot(key: '$name/$j', question: qs[j], displayIndex: j));
      }
      return slots;
    }

    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      if (q.type == QuestionType.reading && q.reading != null) {
        // Inline reading passage — a list item whose own answerable
        // questions live inside it. 3-segment key so it can never collide
        // with a sibling's 2-segment key.
        final inner = q.reading!.qs;
        for (var j = 0; j < inner.length; j++) {
          slots.add(AnswerSlot(
            key: '$name/$i/$j',
            question: inner[j],
            displayIndex: slots.length,
          ));
        }
      } else {
        slots.add(AnswerSlot(
          key: '$name/$i',
          question: q,
          displayIndex: slots.length,
        ));
      }
    }
    return slots;
  }

  bool get isReading => readingContainer != null;

  /// Total answerable question count in this section.
  int get questionCount => answerSlots.length;
}

// ── TestSpec ──────────────────────────────────────────────────────────────────

class TestSpec {
  final String testKey;
  final String title;
  final int grade;
  final int version;
  final List<String> parts;
  final ScoringSpec? scoring;

  /// Optional timer override from the test JSON (`duration_minutes`).
  /// When set and > 0, engine_host_screen._effectiveDuration uses it
  /// (clamped to [1, 180] minutes) instead of the per-question estimate.
  final int? durationMinutes;

  /// Optional subject tag from the test JSON (`subject`), e.g. "math",
  /// "english", "tarix", "onatili". Null for legacy tests that predate this
  /// field — engine_host_screen._buildPayload falls back to the old
  /// per-section name heuristic in that case.
  final String? subject;

  /// variant key → section name → SectionData
  final Map<String, Map<String, SectionData>> variants;

  const TestSpec({
    required this.testKey,
    required this.title,
    required this.grade,
    required this.version,
    required this.parts,
    this.scoring,
    this.durationMinutes,
    this.subject,
    required this.variants,
  });

  factory TestSpec.fromJson(Map<String, dynamic> json) {
    final testKey = json['test_key']?.toString() ?? '';
    final title = json['title']?.toString() ?? '';
    final grade = (json['grade'] as num?)?.toInt() ?? 0;
    final version = (json['version'] as num?)?.toInt() ?? 1;
    final durationMinutes = (json['duration_minutes'] as num?)?.toInt();
    final subject = json['subject']?.toString();

    // parts
    final rawParts = json['parts'];
    final List<String> parts = [];
    if (rawParts is List && rawParts.isNotEmpty) {
      for (final p in rawParts) {
        if (p != null) parts.add(p.toString());
      }
    }

    // scoring (optional)
    ScoringSpec? scoring;
    if (json['scoring'] is Map<String, dynamic>) {
      try {
        scoring = ScoringSpec.fromJson(json['scoring'] as Map<String, dynamic>);
      } catch (e) {
        debugPrint('[TestEngine] scoring parse error: $e');
      }
    }

    // variants
    final rawVariants = json['variants'];
    final Map<String, Map<String, SectionData>> variants = {};
    if (rawVariants is Map) {
      for (final variantEntry in rawVariants.entries) {
        final variantKey = variantEntry.key.toString();
        final variantData = variantEntry.value;
        if (variantData is! Map) continue;

        final Map<String, SectionData> sections = {};
        for (final sectionEntry in variantData.entries) {
          final sectionName = sectionEntry.key.toString();
          final sectionRaw = sectionEntry.value;

          final section = _parseSection(sectionName, sectionRaw);
          if (section != null) {
            sections[sectionName] = section;
          }
        }
        variants[variantKey] = sections;
      }
    }

    return TestSpec(
      testKey: testKey,
      title: title,
      grade: grade,
      version: version,
      parts: parts,
      scoring: scoring,
      durationMinutes: durationMinutes,
      subject: subject,
      variants: variants,
    );
  }

  static SectionData? _parseSection(String name, dynamic raw) {
    // Reading container: object with img/title/text/qs keys
    if (raw is Map<String, dynamic> && raw.containsKey('qs')) {
      try {
        final container = ReadingSection.fromJson(raw);
        return SectionData(name: name, readingContainer: container);
      } catch (e) {
        debugPrint('[TestEngine] reading container parse error in "$name": $e');
        return null;
      }
    }

    // Array of question objects
    if (raw is List) {
      if (raw.isEmpty) return SectionData(name: name);
      final List<Question> qs = [];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          try {
            qs.add(Question.fromJson(item));
          } catch (e) {
            debugPrint('[TestEngine] question parse error in section "$name": $e');
          }
        }
      }
      return SectionData(name: name, questions: qs);
    }

    debugPrint('[TestEngine] Unrecognised section format for "$name", skipping');
    return null;
  }

  /// Convenience: get sections for a specific variant key, in parts order.
  List<SectionData> sectionsForVariant(String variantKey) {
    final sectionMap = variants[variantKey] ?? {};
    // Return in parts order; missing sections are skipped
    return parts
        .map((p) => sectionMap[p])
        .whereType<SectionData>()
        .toList();
  }
}
