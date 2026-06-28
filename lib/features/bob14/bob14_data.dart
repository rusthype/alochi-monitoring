// lib/features/bob14/bob14_data.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import '../local_test/local_data.dart';
import '../../core/sync/test_catalog_service.dart';

class Bob14Loader {
  static Map<String, dynamic>? _cache;

  static Future<Map<String, dynamic>> _load() async {
    _cache ??=
        jsonDecode(await rootBundle.loadString('assets/bob1_4.json'))
            as Map<String, dynamic>;
    return _cache!;
  }

  static Future<List<LocalQuestion>> get(int variant) async {
    final data = await _load();
    final raw =
        (data['$variant'] as List).cast<Map<String, dynamic>>();
    return raw.map(_parse).toList();
  }

  static Future<List<LocalQuestion>> getResolved(int variant) async {
    final svc = TestCatalogService.instance;
    final cached = await svc.cached('bob1_4');
    unawaited(svc.ensureDownloaded('bob1_4'));
    if (cached != null) {
      final sections = cached['variants']['$variant'] as Map<String, dynamic>;
      return sections.values
          .expand((l) => (l as List).cast<Map<String, dynamic>>())
          .map(_parseUnified)
          .toList();
    }
    return get(variant);
  }

  static LocalQuestion _parseUnified(Map<String, dynamic> q) {
    final opts = List<String>.from(q['opts'] as List);
    final ansIdx = q['ans'] as int;
    final rng = Random();
    final indexed = List.generate(opts.length, (i) => MapEntry(i, opts[i]));
    indexed.shuffle(rng);
    final newOpts = indexed.map((e) => e.value).toList();
    final newIdx = indexed.indexWhere((e) => e.key == ansIdx);
    final newCorrect = 'abcd'[newIdx];
    return LocalQuestion(
      id: '',
      subject: 'm',
      prompt: q['q'] as String,
      options: newOpts,
      correct: newCorrect,
      topic: '',
    );
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
