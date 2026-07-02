// lib/features/unit1/unit1_spec_adapter.dart
// Converts the raw unit1_eng.json asset into the engine's TestSpec JSON shape.
// Confirmed against lib/core/engine/test_models.dart:
//   - Top-level keys: test_key, title, grade, version, parts, variants
//   - Per-variant section names: Vocabulary, Grammar, Spelling, Sentences, Reading
//   - Reading section shape: {img, title, text, qs: [...]}
//   - Question keys: type, q, opts, ans, scramble, words, img

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class Unit1SpecAdapter {
  static const String _imgBase = 'assets/unit1/img/';

  static Future<Map<String, dynamic>> loadSpec() async {
    final raw = await rootBundle.loadString('assets/unit1/unit1_eng.json');
    final src = jsonDecode(raw) as Map<String, dynamic>;
    return convert(src);
  }

  static String _img(dynamic img) {
    final s = (img ?? '').toString();
    if (s.isEmpty) return s;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    return '$_imgBase$s';
  }

  static Map<String, dynamic> _q(Map<dynamic, dynamic> q, String type) {
    final out = <String, dynamic>{'type': type};
    if (q.containsKey('q')) out['q'] = q['q'];
    if (q.containsKey('opts')) out['opts'] = q['opts'];
    if (q.containsKey('ans')) out['ans'] = q['ans']; // int or string — copied verbatim
    if (q.containsKey('scramble')) out['scramble'] = q['scramble'];
    if (q.containsKey('words')) out['words'] = q['words'];
    if (q.containsKey('img')) out['img'] = _img(q['img']);
    return out;
  }

  static const Map<String, String> _readingType = {
    'yn': 'yes_no',
    'mc': 'text_choice',
    'fill': 'fill_blank',
  };

  static Map<String, dynamic> convert(Map<String, dynamic> src) {
    final variantsOut = <String, dynamic>{};
    final variants = src['variants'] as Map;
    variants.forEach((vk, vv) {
      final v = vv as Map;
      final vocab = (v['vocab'] as List? ?? [])
          .map((e) => _q(e as Map, 'image_choice'))
          .toList();
      final grammar = (v['grammar'] as List? ?? [])
          .map((e) => _q(e as Map, 'text_choice'))
          .toList();
      final spelling = (v['spelling'] as List? ?? [])
          .map((e) => _q(e as Map, 'spelling'))
          .toList();
      final sentences = (v['sentences'] as List? ?? [])
          .map((e) => _q(e as Map, 'sentence_order'))
          .toList();
      final reading = v['reading'] as Map?;
      Map<String, dynamic>? readingOut;
      if (reading != null) {
        final qs = (reading['qs'] as List? ?? []).map((e) {
          final rq = e as Map;
          final t = _readingType[(rq['type'] ?? '').toString()] ?? 'text_choice';
          return _q(rq, t);
        }).toList();
        readingOut = {
          'img': _img(reading['img']),
          'title': reading['title'],
          'text': reading['text'],
          'qs': qs,
        };
      }
      variantsOut[vk.toString()] = {
        'Vocabulary': vocab,
        'Grammar': grammar,
        'Spelling': spelling,
        'Sentences': sentences,
        if (readingOut != null) 'Reading': readingOut,
      };
    });
    return {
      'test_key': src['test_key'] ?? 'unit1_eng',
      'title': src['title'] ?? '',
      'grade': src['grade'] ?? 1,
      'version': 1,
      'parts': const ['Vocabulary', 'Grammar', 'Spelling', 'Sentences', 'Reading'],
      'variants': variantsOut,
    };
  }
}
