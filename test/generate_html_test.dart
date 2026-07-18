import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/core/services/html_service.dart';

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
        MapEntry('1-bob: Bir xonali sonlar', (ok: 0, tot: 7)),
        MapEntry('2-bob: Ikki xonali sonlar', (ok: 0, tot: 12)),
        MapEntry('PART 1 — Vocabulary', (ok: 0, tot: 12)),
      ],
      unitScores: [
        MapEntry('Unit 1', (ok: 0, tot: 4)),
        MapEntry('Unit 2', (ok: 0, tot: 2)),
      ],
      aiSummary: {
        'summary': 'Alixon 23% natija ko\'rsatdi. O\'zlashtirish biroz past, zaif mavzularga ko\'proq e\'tibor qaratish kerak.',
      }
    );
    
    final file = File('/Users/max/Downloads/Sinov_Pasport_Alixon_4sinf.html');
    await file.writeAsString(htmlString);
    print('HTML saved to: \${file.path}');
  });
}
