// lib/features/interhouse/interhouse_data.dart
// Models + loader for interhouse_g2.json
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show Color;

// ── IhLevel ──────────────────────────────────────────────────────────────────

class IhLevel {
  final int min;
  final String label;
  final String cambridge;
  final String cefr;
  final String bg;
  final String col;

  const IhLevel({
    required this.min,
    required this.label,
    required this.cambridge,
    required this.cefr,
    required this.bg,
    required this.col,
  });

  factory IhLevel.fromJson(Map<String, dynamic> j) => IhLevel(
        min: (j['min'] as num).toInt(),
        label: j['label'] as String,
        cambridge: j['cambridge'] as String,
        cefr: j['cefr'] as String,
        bg: j['bg'] as String,
        col: j['col'] as String,
      );

  Color get bgColor => _hexColor(bg);
  Color get colColor => _hexColor(col);
}

Color _hexColor(String hex) {
  final h = hex.replaceFirst('#', '');
  final full = h.length == 6 ? 'FF$h' : h;
  return Color(int.parse(full, radix: 16));
}

// ── IhQuestion ───────────────────────────────────────────────────────────────

class IhQuestion {
  final String type; // mc_img | mc | word | yn | fill | sentence
  final String? img; // asset filename only e.g. "lamp.png"
  final String? q;
  final String? scramble;
  final String? words;
  final List<String> opts;
  final dynamic ans; // int for mc/mc_img, String for others

  const IhQuestion({
    required this.type,
    this.img,
    this.q,
    this.scramble,
    this.words,
    required this.opts,
    required this.ans,
  });

  factory IhQuestion.fromJson(Map<String, dynamic> j) => IhQuestion(
        type: j['type'] as String,
        img: j['img'] as String?,
        q: j['q'] as String?,
        scramble: j['scramble'] as String?,
        words: j['words'] as String?,
        opts:
            j['opts'] != null ? List<String>.from(j['opts'] as List) : const [],
        ans: j['ans'],
      );
}

// ── IhReading ─────────────────────────────────────────────────────────────────

class IhReading {
  final String img; // e.g. "r07.png"
  final String title;
  final String text;
  final List<IhQuestion> qs;

  const IhReading({
    required this.img,
    required this.title,
    required this.text,
    required this.qs,
  });

  factory IhReading.fromJson(Map<String, dynamic> j) => IhReading(
        img: j['img'] as String,
        title: j['title'] as String,
        text: j['text'] as String,
        qs: (j['qs'] as List)
            .map((q) => IhQuestion.fromJson(q as Map<String, dynamic>))
            .toList(),
      );
}

// ── IhVariant ─────────────────────────────────────────────────────────────────

class IhVariant {
  final List<IhQuestion> vocab;
  final List<IhQuestion> grammar;
  final List<IhQuestion> spelling;
  final IhReading reading;
  final List<IhQuestion> sentences;

  const IhVariant({
    required this.vocab,
    required this.grammar,
    required this.spelling,
    required this.reading,
    required this.sentences,
  });

  factory IhVariant.fromJson(Map<String, dynamic> j) => IhVariant(
        vocab: (j['vocab'] as List)
            .map((q) => IhQuestion.fromJson(q as Map<String, dynamic>))
            .toList(),
        grammar: (j['grammar'] as List)
            .map((q) => IhQuestion.fromJson(q as Map<String, dynamic>))
            .toList(),
        spelling: (j['spelling'] as List)
            .map((q) => IhQuestion.fromJson(q as Map<String, dynamic>))
            .toList(),
        reading: IhReading.fromJson(j['reading'] as Map<String, dynamic>),
        sentences: (j['sentences'] as List)
            .map((q) => IhQuestion.fromJson(q as Map<String, dynamic>))
            .toList(),
      );
}

// ── IhTestData ────────────────────────────────────────────────────────────────

class IhTestData {
  final String testKey;
  final List<String> parts;
  final List<int> shieldsThresholds;
  final List<IhLevel> levels;
  final Map<String, IhVariant> variants;

  const IhTestData({
    required this.testKey,
    required this.parts,
    required this.shieldsThresholds,
    required this.levels,
    required this.variants,
  });

  factory IhTestData.fromJson(Map<String, dynamic> j) {
    final scoring = j['scoring'] as Map<String, dynamic>;
    return IhTestData(
      testKey: j['test_key'] as String,
      parts: List<String>.from(j['parts'] as List),
      shieldsThresholds: List<int>.from((scoring['shields_thresholds'] as List)
          .map((e) => (e as num).toInt())),
      levels: (scoring['levels'] as List)
          .map((l) => IhLevel.fromJson(l as Map<String, dynamic>))
          .toList(),
      variants: (j['variants'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, IhVariant.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}

// ── IhLoader ──────────────────────────────────────────────────────────────────

class IhLoader {
  static IhTestData? _cache;

  static Future<IhTestData> load() async {
    if (_cache != null) return _cache!;
    final raw =
        await rootBundle.loadString('assets/interhouse/interhouse_g2.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    _cache = IhTestData.fromJson(j);
    return _cache!;
  }
}
