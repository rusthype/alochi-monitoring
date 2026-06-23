// lib/features/unit1/unit1_data.dart
// 1-sinf Ingliz tili Unit 1 — test data loader (offline)
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ── Models ────────────────────────────────────────────────────────────────────

/// Vocabulary or Grammar question (has image optional, options list, answer index).
class Unit1Q {
  final String? img;
  final String q;
  final List<String> opts;
  final int ans;

  const Unit1Q({
    this.img,
    required this.q,
    required this.opts,
    required this.ans,
  });

  factory Unit1Q.fromJson(Map<String, dynamic> json) {
    final opts = json['opts'];
    final optsList = (opts is List && opts.isNotEmpty)
        ? opts.map((e) => e?.toString() ?? '').toList()
        : <String>[];
    return Unit1Q(
      img: json['img']?.toString(),
      q: json['q']?.toString() ?? '',
      opts: optsList,
      ans: (json['ans'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Spelling question — unscramble letters to form a word.
class Unit1Spelling {
  final String scramble;
  final String ans;

  const Unit1Spelling({required this.scramble, required this.ans});

  factory Unit1Spelling.fromJson(Map<String, dynamic> json) {
    return Unit1Spelling(
      scramble: json['scramble']?.toString() ?? '',
      ans: json['ans']?.toString() ?? '',
    );
  }
}

/// Sentence ordering question — reorder words into correct sentence.
class Unit1Sentence {
  final String words;
  final String ans;

  const Unit1Sentence({required this.words, required this.ans});

  factory Unit1Sentence.fromJson(Map<String, dynamic> json) {
    return Unit1Sentence(
      words: json['words']?.toString() ?? '',
      ans: json['ans']?.toString() ?? '',
    );
  }
}

/// A single reading comprehension question.
/// [type] is one of: "yn" (yes/no), "mc" (multiple choice), "fill" (fill in blank).
/// [ans] is String for yn/fill, int index for mc.
class Unit1ReadingQ {
  final String type;
  final String q;
  final List<String>? opts;
  final dynamic ans; // String or int

  const Unit1ReadingQ({
    required this.type,
    required this.q,
    this.opts,
    required this.ans,
  });

  factory Unit1ReadingQ.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? 'yn';
    final optsRaw = json['opts'];
    List<String>? opts;
    if (optsRaw is List && optsRaw.isNotEmpty) {
      opts = optsRaw.map((e) => e?.toString() ?? '').toList();
    }
    // ans is int for mc, String otherwise
    dynamic ans;
    if (type == 'mc') {
      ans = (json['ans'] as num?)?.toInt() ?? 0;
    } else {
      ans = json['ans']?.toString() ?? '';
    }
    return Unit1ReadingQ(
      type: type,
      q: json['q']?.toString() ?? '',
      opts: opts,
      ans: ans,
    );
  }
}

/// Reading passage with questions.
class Unit1Reading {
  final String img;
  final String title;
  final String text;
  final List<Unit1ReadingQ> qs;

  const Unit1Reading({
    required this.img,
    required this.title,
    required this.text,
    required this.qs,
  });

  factory Unit1Reading.fromJson(Map<String, dynamic> json) {
    final qsRaw = json['qs'];
    final qsList = (qsRaw is List && qsRaw.isNotEmpty)
        ? qsRaw
            .whereType<Map<String, dynamic>>()
            .map(Unit1ReadingQ.fromJson)
            .toList()
        : <Unit1ReadingQ>[];
    return Unit1Reading(
      img: json['img']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      qs: qsList,
    );
  }
}

/// One test variant: 25 vocab + 6 grammar + 6 spelling + 6 sentences + reading (6 qs) = 49.
class Unit1Variant {
  final List<Unit1Q> vocab;
  final List<Unit1Q> grammar;
  final List<Unit1Spelling> spelling;
  final List<Unit1Sentence> sentences;
  final Unit1Reading reading;

  const Unit1Variant({
    required this.vocab,
    required this.grammar,
    required this.spelling,
    required this.sentences,
    required this.reading,
  });

  factory Unit1Variant.fromJson(Map<String, dynamic> json) {
    List<Unit1Q> parseQList(dynamic raw) {
      if (raw is! List || raw.isEmpty) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Unit1Q.fromJson)
          .toList();
    }

    List<Unit1Spelling> parseSpelling(dynamic raw) {
      if (raw is! List || raw.isEmpty) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Unit1Spelling.fromJson)
          .toList();
    }

    List<Unit1Sentence> parseSentences(dynamic raw) {
      if (raw is! List || raw.isEmpty) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Unit1Sentence.fromJson)
          .toList();
    }

    Unit1Reading parseReading(dynamic raw) {
      if (raw is Map<String, dynamic>) {
        return Unit1Reading.fromJson(raw);
      }
      return const Unit1Reading(img: '', title: '', text: '', qs: []);
    }

    return Unit1Variant(
      vocab: parseQList(json['vocab']),
      grammar: parseQList(json['grammar']),
      spelling: parseSpelling(json['spelling']),
      sentences: parseSentences(json['sentences']),
      reading: parseReading(json['reading']),
    );
  }
}

/// Top-level test data: metadata + all variants.
class Unit1TestData {
  final String testKey;
  final int grade;
  final String title;
  final List<String> parts;
  final Map<String, Unit1Variant> variants;

  const Unit1TestData({
    required this.testKey,
    required this.grade,
    required this.title,
    required this.parts,
    required this.variants,
  });

  factory Unit1TestData.fromJson(Map<String, dynamic> json) {
    final partsRaw = json['parts'];
    final partsList = (partsRaw is List && partsRaw.isNotEmpty)
        ? partsRaw.map((e) => e?.toString() ?? '').toList()
        : <String>[];

    final variantsRaw = json['variants'];
    final variantsMap = <String, Unit1Variant>{};
    if (variantsRaw is Map) {
      variantsRaw.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          variantsMap[key.toString()] = Unit1Variant.fromJson(value);
        }
      });
    }

    return Unit1TestData(
      testKey: json['test_key']?.toString() ?? '',
      grade: (json['grade'] as num?)?.toInt() ?? 1,
      title: json['title']?.toString() ?? '',
      parts: partsList,
      variants: variantsMap,
    );
  }
}

// ── Loader ────────────────────────────────────────────────────────────────────

class Unit1Loader {
  static Unit1TestData? _cache;

  static Future<Unit1TestData> load() async {
    if (_cache != null) return _cache!;
    try {
      final raw = await rootBundle.loadString('assets/unit1/unit1_eng.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _cache = Unit1TestData.fromJson(json);
      return _cache!;
    } catch (e, st) {
      // ignore: avoid_print
      debugPrint('Unit1Loader.load error: $e\n$st');
      rethrow;
    }
  }
}
