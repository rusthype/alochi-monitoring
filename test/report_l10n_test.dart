// Result reports (PDF tips, HTML result report, offline diagnostic passport)
// follow the app locale: the Uzbek output is the pre-existing text, Russian is
// a real translation, and data that comes from the server is never translated.
import 'dart:io';

import 'package:alochi_monitoring/core/services/diagnostic_export_service.dart';
import 'package:alochi_monitoring/core/services/html_service.dart';
import 'package:alochi_monitoring/core/services/pdf_service.dart';
import 'package:alochi_monitoring/core/services/pdf_tips.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

const _golden = 'test/fixtures/uz_report_goldens';

String _g(String name) => File('$_golden/$name.html').readAsStringSync();

/// Today's date as the HTML report prints it, replaced by a stable token.
String _noDate(String s) {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return s.replaceAll('${two(n.day)}/${two(n.month)}/${n.year}', '@DATE@');
}

/// The reports print a few headings in CSS `text-transform: uppercase`; the
/// ARB keys shared with the PDF store them already upper-cased, so the
/// comparison with the old HTML ignores case (the rendered text is the same).
void _expectSameAsOld(String actual, String golden, {String? reason}) {
  expect(actual.toLowerCase(), golden.toLowerCase(), reason: reason);
}

const _uzMarkers = [
  'Matematika',
  'Ingliz',
  'sinf',
  'Variant',
  'Har kuni',
  'Ota-onaga',
  'Pasport',
  'Xato javob',
  "To'g'ri",
  'Jami savol',
  'Zaif',
  'Qayta',
  'Aralash',
  'Nazorat',
  'Natija',
  'Taxminiy',
  'KUN',
  'tahlil',
  'reja',
  'Diagnostik',
];

void expectNoUzbek(String s, {String? reason}) {
  for (final m in _uzMarkers) {
    expect(s.contains(m), isFalse, reason: '${reason ?? ''} still has "$m"');
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final uz = await AppLocalizations.delegate.load(const Locale('uz'));
  final ru = await AppLocalizations.delegate.load(const Locale('ru'));

  group('PdfTips', () {
    test('uz equals the old hardcoded Uzbek text', () {
      expect(PdfTips.mathTips(0.4, uz), [
        "Asosiy amallar (qo'shish, ayirish, ko'paytirish, bo'lish)ni qayta o'rganing.",
        'Har kuni 20 daqiqa misollar yeching.',
        '2-sinf dasturidan boshlang.',
      ]);
      expect(PdfTips.mathTips(0.6, uz), [
        'Jadval va kasr sonlarni mustahkamlang.',
        "Xato qilgan savollar turini aniqlang va shu mavzuga e'tibor bering.",
        'Har kuni 2-3 ta test masala yeching.',
      ]);
      expect(PdfTips.mathTips(0.8, uz), [
        'Qiyin masalalar (muammo masalalar) ustida ishlang.',
        'Vaqtni boshqarishni mashq qiling.',
        'Har savolga 1-2 daqiqa ajrating.',
      ]);
      expect(PdfTips.mathTips(0.95, uz), [
        'Ajoyib!',
        "Murakkab olimpiada masalalarini hal qilishga o'ting.",
        'Natijani barqaror saqlash uchun muntazam mashq qiling.',
      ]);
      expect(PdfTips.englishTips(0.4, uz), [
        "Kunlik 10 ta yangi so'z yodlang (flashcard usuli).",
        'Asosiy grammatika: to be, present simple, plural nouns.',
        'BBC Learning English, Duolingo ilovalaridan foydalaning.',
      ]);
      expect(PdfTips.englishTips(0.6, uz), [
        "Past simple va present continuous grammatikasini o'rganing.",
        "Har kuni inglizcha 1 ta qisqa matn o'qing.",
        "So'z boyligini mavzu bo'yicha guruhlab yodlang.",
      ]);
      expect(PdfTips.englishTips(0.8, uz), [
        "Tinglash ko'nikmalarini rivojlantiring.",
        'YouTube ingliz kontentidan foydalaning.',
        'Esselar va qisqa hikoyalar yozing.',
      ]);
      expect(PdfTips.englishTips(0.95, uz), [
        'Ajoyib!',
        'IELTS/Cambridge sertifikati uchun tayyorlaning.',
        "Murakkab matnlarni o'qish va tinglashni davom ettiring.",
      ]);
      expect(
          PdfTips.overallStatus(95, uz), 'Oltin medal darajasi! Davom eting!');
      expect(PdfTips.overallStatus(80, uz),
          'Yaxshi natija! Yana bir oz harakat kerak.');
      expect(PdfTips.overallStatus(65, uz),
          "Qoniqarli. Tavsiyalarga amal qiling va qayta sinab ko'ring.");
      expect(PdfTips.overallStatus(10, uz),
          "Xafa bo'lmang! Har bir muvaffaqiyatsizlik yangi boshlang'ich.");
    });

    test('band boundaries are unchanged', () {
      expect(PdfTips.mathTips(0.5, uz), PdfTips.mathTips(0.6, uz));
      expect(PdfTips.mathTips(0.75, uz), PdfTips.mathTips(0.8, uz));
      expect(PdfTips.mathTips(0.9, uz), PdfTips.mathTips(1.0, uz));
      expect(PdfTips.overallStatus(90, uz), PdfTips.overallStatus(100, uz));
      expect(PdfTips.overallStatus(75, uz), PdfTips.overallStatus(89, uz));
      expect(PdfTips.overallStatus(60, uz), PdfTips.overallStatus(74, uz));
    });

    test('ru is Russian, with 3 tips per band and a different text per band',
        () {
      final seen = <String>{};
      for (final p in [0.4, 0.6, 0.8, 0.95]) {
        for (final tips in [
          PdfTips.mathTips(p, ru),
          PdfTips.englishTips(p, ru)
        ]) {
          expect(tips, hasLength(3));
          for (final t in tips) {
            expect(RegExp(r'[А-Яа-я]').hasMatch(t), isTrue, reason: t);
            expectNoUzbek(t);
          }
          seen.add(tips.join('|'));
        }
      }
      expect(seen, hasLength(8));
      for (final s in [95, 80, 65, 10]) {
        final t = PdfTips.overallStatus(s, ru);
        expect(RegExp(r'[А-Яа-я]').hasMatch(t), isTrue, reason: t);
        expect(t, isNot(PdfTips.overallStatus(s, uz)));
      }
    });
  });

  group('HtmlService', () {
    final topics = [
      const MapEntry('1-bob: Bir xonali sonlar', (ok: 0, tot: 7)),
      const MapEntry('2-bob: Ikki xonali sonlar', (ok: 9, tot: 12)),
    ];
    final units = [const MapEntry('Unit 1', (ok: 3, tot: 4))];

    String full(AppLocalizations l10n) =>
        _noDate(HtmlService.generateResultHtml(
          l10n: l10n,
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
          mathTopics: const [],
          engTopics: const [],
          topicScores: topics,
          unitScores: units,
          aiSummary: {'summary': 'Matn xulosa.'},
        ));
    String fallbackGood(AppLocalizations l10n) =>
        _noDate(HtmlService.generateResultHtml(
          l10n: l10n,
          firstName: 'Ali',
          lastName: 'Karimov',
          group: '5-A',
          grade: 5,
          variant: 3,
          mathOk: 20,
          mathTotal: 25,
          engOk: 22,
          engTotal: 26,
          pct: 82,
          mathTopics: const [],
          engTopics: const [],
        ));
    String zero(AppLocalizations l10n) =>
        _noDate(HtmlService.generateResultHtml(
          l10n: l10n,
          firstName: '',
          lastName: 'X',
          group: 'g',
          grade: 1,
          variant: 1,
          mathOk: 0,
          mathTotal: 0,
          engOk: 0,
          engTotal: 0,
          pct: 0,
          mathTopics: const [],
          engTopics: const [],
        ));

    test('uz output is the old Uzbek report (data + topics + server summary)',
        () {
      _expectSameAsOld(full(uz), _g('html_full'));
    });
    test('uz output is the old Uzbek report (fallback summary, good result)',
        () {
      _expectSameAsOld(fallbackGood(uz), _g('html_fallback_good'));
    });
    test('uz output is the old Uzbek report (no totals, weak-topic fallback)',
        () {
      _expectSameAsOld(zero(uz), _g('html_zero_totals_nofallbacktopic'));
      expect(zero(uz), contains('Zaif mavzu'));
    });
    test('uz keeps lang=uz', () {
      expect(full(uz), contains("<html lang='uz'>"));
    });

    test('ru has no Uzbek text, keeps server data, and lang=ru', () {
      final h = HtmlService.generateResultHtml(
        l10n: ru,
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
        mathTopics: const [],
        engTopics: const [],
        topicScores: const [
          MapEntry('Topic A', (ok: 0, tot: 7)),
          MapEntry('Topic B', (ok: 9, tot: 12)),
        ],
        unitScores: const [MapEntry('Unit 1', (ok: 3, tot: 4))],
        aiSummary: {'summary': 'Summary from the server.'},
      );
      expect(h, contains("<html lang='ru'>"));
      expectNoUzbek(h);
      expect(h, contains('Alixon Valiyev'));
      expect(h, contains('56-maktab'));
      expect(h, contains('Topic A'));
      expect(h, contains('Summary from the server.'));
      expect(h, contains('Математика'));
      expect(h, contains('Английский язык'));
      expect(h, contains('Вариант 20'));
      expect(h, contains('4-класс'));
      expect(h, contains('6/25'));
      // the student's own fallback summary is also Russian
      final f = HtmlService.generateResultHtml(
        l10n: ru,
        firstName: 'Ali',
        lastName: 'K',
        group: 'g',
        grade: 5,
        variant: 3,
        mathOk: 1,
        mathTotal: 2,
        engOk: 1,
        engTotal: 2,
        pct: 82,
        mathTopics: const [],
        engTopics: const [],
      );
      expectNoUzbek(f);
      expect(f, contains('Ali показал(а) результат 82%'));
      expect(f, contains('Слабая тема'));
    });
  });

  group('DiagnosticExportService', () {
    Map<String, dynamic> rec(String name, int? m, int? e, {bool est = false}) =>
        {
          'attempt_id': 'a1',
          'student_name': name,
          'class_label': '4-A',
          'school': '56-maktab',
          'math_score': m,
          'english_score': e,
          'status': 'sent',
          'date_taken': 1735732800000,
          if (est) '_local_estimate': true,
        };
    final cases = <String, Map<String, dynamic>>{
      'diag_high': rec('Aliyev Ali', 25, 28),
      'diag_mid': rec('Valiyev Vali', 20, 18),
      'diag_low_mathweaker': rec('Karimov Karim', 5, 9),
      'diag_low_engweaker': rec('Karimova Zilola', 9, 5),
      'diag_pending': rec('Pending Kid', null, null),
      'diag_estimate': rec('Estimated Student', 20, 22, est: true),
    };

    for (final e in cases.entries) {
      test('uz ${e.key} is the old Uzbek passport', () {
        _expectSameAsOld(
          DiagnosticExportService.generateStudentPassportHtml(e.value,
              l10n: uz),
          _g(e.key),
        );
      });
      test('ru ${e.key} has no Uzbek text and keeps the record data', () {
        final h = DiagnosticExportService.generateStudentPassportHtml(e.value,
            l10n: ru);
        expect(h, contains("<html lang='ru'>"));
        expectNoUzbek(h, reason: e.key);
        expect(h, contains(e.value['student_name'] as String));
        expect(h, contains('56-maktab'));
        expect(h, contains('4-A'));
      });
    }

    test('zip export renders every passport with the given locale', () {
      final bytes = DiagnosticExportService.buildZipBytes(
          [rec('Aliyev Ali', 25, 28)],
          l10n: ru);
      expect(bytes, isNotEmpty);
    });
  });

  group('PDF font + Russian', () {
    test('bundled PDF fonts carry every glyph the Russian report uses',
        () async {
      final regular =
          TtfParser((await rootBundle.load('assets/fonts/Inter-Regular.ttf')));
      final bold =
          TtfParser((await rootBundle.load('assets/fonts/Inter-Bold.ttf')));
      final texts = <String>[
        ru.diagnosticPassportHeader,
        ru.variantBadge(20),
        ru.gradeShort,
        ru.gradeNeedsPractice,
        ru.goodResultLabel,
        ru.correctAnswerLabelPdf,
        ru.wrongAnswerLabelPdf,
        ru.totalQuestionsCountLabel,
        ru.topicAnalysisHeader,
        ru.unitAnalysisHeader,
        ru.fourteenDayPlanHeader,
        ru.dayRange1_3,
        ru.dayRange4_7,
        ru.dayRange8_11,
        ru.dayRange12_14,
        ru.dailyPractice15MinMsg,
        ru.dailyExamples5Msg,
        ru.mixedExercisesTopic,
        ru.reviewAllTopicsMsg,
        ru.controlTestTopic,
        ru.compareResultsMsg,
        ru.aiSummaryHeader,
        ru.alochiAiLabel,
        ru.aiSummaryFallbackMsg('Ali', 50),
        ru.forParentsLabel,
        ru.parentTipsText,
        ru.footerBrandTagline,
        ru.weakTopicFallback,
        ru.wellMasteredBadge,
        ru.needsReviewBadge,
        ru.subjectsResultTitle,
        ru.pdfTitle('x'),
        ru.pdfCertificateTitle('x'),
        ru.pdfPassportTitle,
        for (final p in [0.4, 0.6, 0.8, 0.95]) ...[
          ...PdfTips.mathTips(p, ru),
          ...PdfTips.englishTips(p, ru),
        ],
        for (final s in [95, 80, 65, 10]) PdfTips.overallStatus(s, ru),
      ];
      for (final t in texts) {
        for (final r in t.runes) {
          if (r == 0x0A || r == 0x20) continue;
          expect(regular.charToGlyphIndexMap.containsKey(r), isTrue,
              reason: 'Inter-Regular lacks U+${r.toRadixString(16)} in "$t"');
          expect(bold.charToGlyphIndexMap.containsKey(r), isTrue,
              reason: 'Inter-Bold lacks U+${r.toRadixString(16)} in "$t"');
        }
      }
    });

    test('PdfService builds a Russian PDF', () async {
      final bytes = await PdfService.generateResultPdf(
        firstName: 'Ali',
        lastName: 'Valiyev',
        group: '5-A',
        grade: 5,
        variant: 3,
        mathOk: 1,
        mathTotal: 2,
        engOk: 1,
        engTotal: 2,
        pct: 50,
        mathTopics: const [],
        engTopics: const [],
        l10n: ru,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
