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
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString();
    final type = _parseType(rawType);

    if (type == null) {
      debugPrint('[TestEngine] Unknown question type "$rawType", falling back to text_choice');
      // Safe fallback — treat as text_choice with empty opts so engine can render
      return Question(
        type: QuestionType.textChoice,
        q: json['q']?.toString(),
        opts: _parseOpts(json['opts']),
        ans: (json['ans'] as num?)?.toInt() ?? 0,
        topic: json['topic']?.toString(),
      );
    }

    switch (type) {
      case QuestionType.textChoice:
        return Question(
          type: type,
          q: json['q']?.toString(),
          opts: _parseOpts(json['opts']),
          ans: (json['ans'] as num?)?.toInt() ?? 0,
          topic: json['topic']?.toString(),
        );

      case QuestionType.imageChoice:
        return Question(
          type: type,
          img: json['img']?.toString(),
          q: json['q']?.toString(),
          opts: _parseOpts(json['opts']),
          ans: (json['ans'] as num?)?.toInt() ?? 0,
          topic: json['topic']?.toString(),
        );

      case QuestionType.spelling:
        return Question(
          type: type,
          scramble: json['scramble']?.toString(),
          strAns: json['ans']?.toString(),
          topic: json['topic']?.toString(),
        );

      case QuestionType.sentenceOrder:
        return Question(
          type: type,
          words: json['words']?.toString(),
          strAns: json['ans']?.toString(),
          topic: json['topic']?.toString(),
        );

      case QuestionType.reading:
        return Question(
          type: type,
          reading: ReadingSection.fromJson(json),
          topic: json['topic']?.toString(),
        );

      case QuestionType.yesNo:
        return Question(
          type: type,
          q: json['q']?.toString(),
          yesNoAns: json['ans']?.toString().toUpperCase(),
          topic: json['topic']?.toString(),
        );

      case QuestionType.fillBlank:
        return Question(
          type: type,
          q: json['q']?.toString(),
          strAns: json['ans']?.toString(),
          topic: json['topic']?.toString(),
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

  /// Non-reading questions (text_choice, image_choice, spelling, sentence_order,
  /// yes_no, fill_blank). Empty when this section is a reading container.
  final List<Question> questions;

  /// Non-null when the whole section is a reading passage container.
  final ReadingSection? readingContainer;

  const SectionData({
    required this.name,
    this.questions = const [],
    this.readingContainer,
  });

  bool get isReading => readingContainer != null;

  /// Total answerable question count in this section.
  int get questionCount {
    if (isReading) return readingContainer!.qs.length;
    return questions.length;
  }
}

// ── TestSpec ──────────────────────────────────────────────────────────────────

class TestSpec {
  final String testKey;
  final String title;
  final int grade;
  final int version;
  final List<String> parts;
  final ScoringSpec? scoring;

  /// variant key → section name → SectionData
  final Map<String, Map<String, SectionData>> variants;

  const TestSpec({
    required this.testKey,
    required this.title,
    required this.grade,
    required this.version,
    required this.parts,
    this.scoring,
    required this.variants,
  });

  factory TestSpec.fromJson(Map<String, dynamic> json) {
    final testKey = json['test_key']?.toString() ?? '';
    final title = json['title']?.toString() ?? '';
    final grade = (json['grade'] as num?)?.toInt() ?? 0;
    final version = (json['version'] as num?)?.toInt() ?? 1;

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
