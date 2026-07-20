import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/services/html_service.dart';

void main() {
  test('generate dummy html', () async {
    final htmlString = HtmlService.generateResultHtml(
      firstName: 'Alixon',
      lastName: 'Valiyev',
      group: '56-maktab',
      grade: 4,
      variant: 20,
      mathOk: 6,
      mathTotal: 25,
      engOk: 6,
      engTotal: 26,
      pct: 23,
      mathTopics: [],
      engTopics: [],
      topicScores: [
        const MapEntry('1-bob: Bir xonali sonlar', (ok: 0, tot: 7)),
        const MapEntry('2-bob: Ikki xonali sonlar', (ok: 0, tot: 12)),
        const MapEntry('PART 1 — Vocabulary', (ok: 0, tot: 12)),
      ],
      unitScores: [
        const MapEntry('Unit 1', (ok: 0, tot: 4)),
        const MapEntry('Unit 2', (ok: 0, tot: 2)),
      ],
      aiSummary: {
        'summary': 'Alixon 23% natija ko\'rsatdi. O\'zlashtirish biroz past, zaif mavzularga ko\'proq e\'tibor qaratish kerak.',
      }
    );
    
    final file = File('/Users/max/Downloads/Sinov_Pasport_Alixon_4sinf.html');
    await file.writeAsString(htmlString);
    debugPrint('HTML saved to: \${file.path}');
  });

  test('renders math/english subject split row when totals are present', () async {
    final htmlString = HtmlService.generateResultHtml(
      firstName: 'Alixon',
      lastName: 'Valiyev',
      group: '56-maktab',
      grade: 4,
      variant: 20,
      mathOk: 8,
      mathTotal: 10,
      engOk: 15,
      engTotal: 20,
      pct: 66,
      mathTopics: const [],
      engTopics: const [],
    );

    expect(htmlString.contains('8/10'), isTrue);
    expect(htmlString.contains('15/20'), isTrue);
  });

  test('skips subject split row when both math and english totals are zero', () async {
    final htmlString = HtmlService.generateResultHtml(
      firstName: 'Alixon',
      lastName: 'Valiyev',
      group: '56-maktab',
      grade: 4,
      variant: 20,
      mathOk: 0,
      mathTotal: 0,
      engOk: 0,
      engTotal: 0,
      pct: 0,
      mathTopics: const [],
      engTopics: const [],
    );

    expect(htmlString.contains('0/0'), isFalse);
  });
}
