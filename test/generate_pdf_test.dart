import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/services/pdf_service.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate dummy pdf', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('uz'));
    final bytes = await PdfService.generateResultPdf(
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
        l10n: l10n,
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
          'summary':
              'Alixon 23% natija ko\'rsatdi. O\'zlashtirish biroz past, zaif mavzularga ko\'proq e\'tibor qaratish kerak.',
        });

    final file = File('/Users/max/Downloads/Sinov_Pasport_Alixon_4sinf.pdf');
    await file.writeAsBytes(bytes);
    debugPrint('PDF saved to: \${file.path}');
  });
}
