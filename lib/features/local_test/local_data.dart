// lib/features/local_test/local_data.dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

class LocalQuestion {
  final String id;
  final String subject; // 'm' | 'e'
  final String prompt;
  final List<String> options;
  final String correct; // 'a'|'b'|'c'|'d'
  final String topic;
  final String? image;
  final List<String> optionImages;
  const LocalQuestion(
      {required this.id,
      required this.subject,
      required this.prompt,
      required this.options,
      required this.correct,
      required this.topic,
      this.image,
      this.optionImages = const []});
  bool get isMath => subject == 'm';
}

class LocalQuestionsLoader {
  static Map<String, dynamic>? _cache;
  static Future<Map<String, dynamic>> _load() async {
    _cache ??= jsonDecode(await rootBundle.loadString('assets/questions.json'));
    return _cache!;
  }

  static Future<List<LocalQuestion>> get(int grade, int variant) async {
    final data = await _load();
    final raw =
        (data['$grade']['$variant'] as List).cast<Map<String, dynamic>>();
    return raw.map(_shuffleOptions).toList();
  }

  static LocalQuestion _shuffleOptions(Map<String, dynamic> q) {
    final opts = List<String>.from(q['o']);
    final origIdx = 'abcd'.indexOf(q['c'] as String);
    final rng = Random();
    final idx = [0, 1, 2, 3];
    for (int j = 3; j > 0; j--) {
      final k = rng.nextInt(j + 1);
      final tmp = idx[j];
      idx[j] = idx[k];
      idx[k] = tmp;
    }
    return LocalQuestion(
      id: q['id'] as String,
      subject: q['s'] as String,
      prompt: q['q'] as String,
      options: idx.map((i) => opts[i]).toList(),
      correct: 'abcd'[idx.indexOf(origIdx)],
      topic: q['t'] as String? ?? '',
      image: q['i'] as String?,
      optionImages: q['oi'] != null
          ? idx.map((i) => (q['oi'] as List)[i] as String).toList()
          : [],
    );
  }
}
