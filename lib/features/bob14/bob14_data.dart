// lib/features/bob14/bob14_data.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import '../local_test/local_data.dart';

class Bob14Loader {
  static Map<String, dynamic>? _cache;

  static Future<Map<String, dynamic>> _load() async {
    _cache ??= jsonDecode(await rootBundle.loadString('assets/bob1_4.json'))
        as Map<String, dynamic>;
    return _cache!;
  }

  static Future<List<LocalQuestion>> get(int variant) async {
    final data = await _load();
    final raw = (data['$variant'] as List).cast<Map<String, dynamic>>();
    return raw.map(_parse).toList();
  }

  static LocalQuestion _parse(Map<String, dynamic> q) {
    final opts = List<String>.from(q['o'] as List);
    final correct = (q['c'] as String).toLowerCase();
    // Shuffle options and remap correct letter
    final rng = Random();
    final indexed = List.generate(opts.length, (i) => MapEntry(i, opts[i]));
    indexed.shuffle(rng);
    final newOpts = indexed.map((e) => e.value).toList();
    final origIdx = 'abcd'.indexOf(correct);
    final newIdx = indexed.indexWhere((e) => e.key == origIdx);
    final newCorrect = 'abcd'[newIdx];
    return LocalQuestion(
      id: q['id'] as String,
      subject: (q['s'] as String?) ?? 'm',
      prompt: q['q'] as String,
      options: newOpts,
      correct: newCorrect,
      topic: (q['t'] as String?) ?? '',
    );
  }
}
