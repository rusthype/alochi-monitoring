// lib/features/result/pdf_report.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import '../../core/models/models.dart';
import '../../core/services/pdf_tips.dart';

class PdfReport {
  static const _orange = PdfColor.fromInt(0xFFF97316);
  static const _blue = PdfColor.fromInt(0xFF3B82F6);
  static const _teal = PdfColor.fromInt(0xFF0D9488);
  static const _green = PdfColor.fromInt(0xFF16A34A);
  static const _red = PdfColor.fromInt(0xFFDC2626);
  static const _ink1 = PdfColor.fromInt(0xFF18181B);
  static const _ink2 = PdfColor.fromInt(0xFF52525B);
  static const _ink3 = PdfColor.fromInt(0xFFA1A1AA);
  static const _border = PdfColor.fromInt(0xFFE4E4E7);
  static const _bgLight = PdfColor.fromInt(0xFFFAFAFA);

  static Future<File> generate({
    required StudentSession session,
    required TestPackage package,
    required TestResult result,
    required List<dynamic> wrongAnswers,
  }) async {
    final doc = pw.Document(title: 'Natija - ${session.studentName}');
    final date = _date(DateTime.now());

    final mathPct =
        package.mathCount > 0 ? result.mathScore / package.mathCount : 0.0;
    final engPct =
        package.engCount > 0 ? result.engScore / package.engCount : 0.0;
    final passed = result.passed;
    final mainClr = passed ? _green : _red;

    final baseFontData =
        await rootBundle.load('assets/fonts/Inter-Regular.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/Inter-Bold.ttf');

    final baseFont = pw.Font.ttf(baseFontData);
    final boldFont = pw.Font.ttf(boldFontData);

    final theme = pw.ThemeData.withFont(
      base: baseFont,
      bold: boldFont,
    );

    pw.MemoryImage? logo;
    try {
      final logoBytes = await rootBundle.load('assets/logo.png');
      logo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    // Asinxron rasmlarni yuklab olish (Xato javoblar uchun)
    final wrongItemsWithImages = <pw.Widget>[];
    for (var w in wrongAnswers) {
      pw.MemoryImage? img;
      final map = w as Map<String, dynamic>;
      final url = map['image'] as String?;
      if (url != null && url.isNotEmpty) {
        try {
          final res = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            img = pw.MemoryImage(res.bodyBytes);
          }
        } catch (_) {}
      }
      wrongItemsWithImages.add(_wrongItem(map, img));
    }

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      theme: theme,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(date, logo),
          pw.SizedBox(height: 24),
          _studentRow(session, result, mainClr, passed),
          pw.SizedBox(height: 24),
          pw.Text("Fanlar bo'yicha natija",
              style: pw.TextStyle(
                  fontSize: 16, fontWeight: pw.FontWeight.bold, color: _ink1)),
          pw.SizedBox(height: 14),
          pw.Row(children: [
            pw.Expanded(
                child: _subjectCard('Matematika', result.mathScore,
                    package.mathCount, mathPct, _blue)),
            pw.SizedBox(width: 16),
            pw.Expanded(
                child: _subjectCard('Ingliz tili', result.engScore,
                    package.engCount, engPct, _teal)),
          ]),
          pw.SizedBox(height: 16),
          _totalRow(result, package),
          pw.SizedBox(height: 16),
          _recommendations(mathPct, engPct, result.totalPct),
          if (wrongAnswers.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _wrongSummary(wrongAnswers),
          ],
          pw.Spacer(),
          _footer(),
        ],
      ),
    ));

    if (wrongAnswers.isNotEmpty) {
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        theme: theme,
        build: (_) => [
          _wrongHeader(session.studentName),
          pw.SizedBox(height: 20),
          ...wrongItemsWithImages,
        ],
      ));
    }

    final dir = await getApplicationDocumentsDirectory();
    final name = session.studentName
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll("'", '')
        .replaceAll(RegExp(r"[^\w]"), '');
    final tag = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/Natija_${name}_$tag.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static pw.Widget _header(String date, pw.MemoryImage? logo) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const pw.BoxDecoration(
          color: _orange,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(16))),
      child: pw.Row(children: [
        pw.Container(
            width: 54,
            height: 54,
            padding: const pw.EdgeInsets.all(4),
            decoration: const pw.BoxDecoration(
                color: PdfColors.white, shape: pw.BoxShape.circle),
            child: logo != null
                ? pw.ClipOval(child: pw.Image(logo, fit: pw.BoxFit.cover))
                : pw.Center(
                    child: pw.Text('A',
                        style: pw.TextStyle(
                            fontSize: 28,
                            fontWeight: pw.FontWeight.bold,
                            color: _orange)))),
        pw.SizedBox(width: 18),
        pw.Expanded(
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
              pw.Text('Alochi Monitoring',
                  style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white)),
              pw.SizedBox(height: 2),
              pw.Text('Monitoring test natijasi',
                  style:
                      const pw.TextStyle(fontSize: 13, color: PdfColors.white)),
            ])),
        pw.Text(date,
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.white)),
      ]));

  static pw.Widget _studentRow(
      StudentSession s, TestResult r, PdfColor clr, bool passed) {
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(
          flex: 3,
          child: pw.Container(
              padding: const pw.EdgeInsets.all(18),
              decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: _border, width: 1.5),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(12))),
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("O'quvchi",
                        style: const pw.TextStyle(fontSize: 11, color: _ink3)),
                    pw.SizedBox(height: 4),
                    pw.Text(s.studentName,
                        style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: _ink1)),
                    pw.SizedBox(height: 12),
                    pw.Text('${s.grade}-sinf',
                        style: const pw.TextStyle(fontSize: 13, color: _ink2)),
                    pw.SizedBox(height: 6),
                    pw.Text('Variant ${s.variant}',
                        style: const pw.TextStyle(fontSize: 13, color: _ink2)),
                    if (s.groupName != null) ...[
                      pw.SizedBox(height: 6),
                      pw.Text(s.groupName!,
                          style:
                              const pw.TextStyle(fontSize: 13, color: _ink2)),
                    ],
                  ]))),
      pw.SizedBox(width: 16),
      pw.Expanded(
          flex: 2,
          child: pw.Container(
              padding: const pw.EdgeInsets.all(18),
              decoration: pw.BoxDecoration(
                  color: passed
                      ? const PdfColor.fromInt(0xFFF0FDF4)
                      : const PdfColor.fromInt(0xFFFFF1F2),
                  border: pw.Border.all(color: clr, width: 1.5),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(12))),
              child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Container(
                        width: 86,
                        height: 86,
                        decoration: pw.BoxDecoration(
                            shape: pw.BoxShape.circle,
                            border: pw.Border.all(color: clr, width: 4)),
                        child: pw.Center(
                            child: pw.Column(
                                mainAxisAlignment: pw.MainAxisAlignment.center,
                                children: [
                              pw.Text('${r.totalPct}%',
                                  style: pw.TextStyle(
                                      fontSize: 24,
                                      fontWeight: pw.FontWeight.bold,
                                      color: clr)),
                              pw.Text('ball',
                                  style: pw.TextStyle(fontSize: 10, color: clr)),
                            ]))),
                    pw.SizedBox(height: 14),
                    pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: pw.BoxDecoration(
                            color: clr,
                            borderRadius: const pw.BorderRadius.all(
                                pw.Radius.circular(20))),
                        child: pw.Text(passed ? "O'tdi" : "O'tmadi",
                            style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white))),
                    pw.SizedBox(height: 8),
                    pw.Text(passed ? 'Tabriklaymiz!' : 'Harakat qiling!',
                        style: pw.TextStyle(fontSize: 12, color: clr)),
                  ]))),
    ]);
  }

  static pw.Widget _subjectCard(
      String label, int score, int total, double pct, PdfColor color) {
    return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: _border, width: 1.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12))),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(fontSize: 12, color: _ink3)),
              pw.SizedBox(height: 8),
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('$score',
                    style: pw.TextStyle(
                        fontSize: 32,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink1)),
                pw.SizedBox(width: 4),
                pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Text('/ $total',
                        style: const pw.TextStyle(fontSize: 13, color: _ink3))),
              ]),
              pw.SizedBox(height: 12),
              pw.SizedBox(
                height: 10,
                child: pw.Row(children: [
                  pw.Expanded(
                      flex: (pct * 100).round().clamp(0, 100),
                      child: pw.Container(
                          decoration: pw.BoxDecoration(
                              color: color,
                              borderRadius: const pw.BorderRadius.all(
                                  pw.Radius.circular(5))))),
                  if (pct < 1.0)
                    pw.Expanded(
                        flex: ((1 - pct) * 100).round().clamp(0, 100),
                        child: pw.Container(
                            decoration: pw.BoxDecoration(
                                color: PdfColor(color.red / 255,
                                    color.green / 255, color.blue / 255, 0.12),
                                borderRadius: const pw.BorderRadius.all(
                                    pw.Radius.circular(5))))),
                ]),
              ),
              pw.SizedBox(height: 6),
              pw.Text('${(pct * 100).round()}%',
                  style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: color)),
            ]));
  }

  static pw.Widget _totalRow(TestResult r, TestPackage p) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: pw.BoxDecoration(
          color: _bgLight,
          border: pw.Border.all(color: _border, width: 1.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10))),
      child: pw.Row(children: [
        pw.Text("Jami to'g'ri javoblar:",
            style: const pw.TextStyle(fontSize: 14, color: _ink2)),
        pw.Spacer(),
        pw.Text('${r.mathScore + r.engScore} / ${p.totalCount}',
            style: pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold, color: _ink1)),
      ]));

  static pw.Widget _recommendations(
      double mathPct, double engPct, int totalPct) {
    final mathTips = PdfTips.mathTips(mathPct);
    final engTips = PdfTips.englishTips(engPct);
    final status = PdfTips.overallStatus(totalPct);

    return pw.Container(
        padding: const pw.EdgeInsets.all(18),
        decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: _border, width: 1.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12))),
        child: pw
            .Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Qanday yaxshilash mumkin?',
              style: pw.TextStyle(
                  fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink1)),
          pw.SizedBox(height: 12),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
                child: _recommendationColumn(
              title: 'Matematika tavsiyalari',
              pct: mathPct,
              color: _blue,
              tips: mathTips,
            )),
            pw.SizedBox(width: 14),
            pw.Expanded(
                child: _recommendationColumn(
              title: 'Ingliz tili tavsiyalari',
              pct: engPct,
              color: _teal,
              tips: engTips,
            )),
          ]),
          pw.SizedBox(height: 12),
          pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: pw.BoxDecoration(
                  color: totalPct >= 75
                      ? const PdfColor.fromInt(0xFFF0FDF4)
                      : const PdfColor.fromInt(0xFFFFFBEB),
                  border: pw.Border.all(
                      color: totalPct >= 75
                          ? _green
                          : const PdfColor.fromInt(0xFFFDE68A),
                      width: 1.5),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(10))),
              child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(totalPct >= 75 ? '\u2713' : '\u2191',
                        style: pw.TextStyle(
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                            color: totalPct >= 75
                                ? _green
                                : const PdfColor.fromInt(0xFFF59E0B))),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                        child: pw.Text(status,
                            style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                                color: _ink1))),
                  ])),
        ]));
  }

  static pw.Widget _recommendationColumn({
    required String title,
    required double pct,
    required PdfColor color,
    required List<String> tips,
  }) {
    final score = (pct * 100).round();

    return pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
            color: PdfColor(
                color.red / 255, color.green / 255, color.blue / 255, 0.06),
            border: pw.Border.all(
                color: PdfColor(color.red / 255, color.green / 255,
                    color.blue / 255, 0.35)),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10))),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: color)),
              pw.SizedBox(height: 8),
              pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: pw.BoxDecoration(
                      color: color,
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(14))),
                  child: pw.Text(
                      '$score%  ${score >= 75 ? '\u2713' : '\u2191'}',
                      style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white))),
              pw.SizedBox(height: 10),
              ...tips.asMap().entries.map((entry) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('${entry.key + 1}.',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: color)),
                        pw.SizedBox(width: 6),
                        pw.Expanded(
                            child: pw.Text(entry.value,
                                style: const pw.TextStyle(
                                    fontSize: 10,
                                    color: _ink2,
                                    lineSpacing: 3))),
                      ]))),
            ]));
  }

  static pw.Widget _wrongSummary(List<dynamic> wrong) {
    final math = wrong.where((w) => w['subject'] == 'math').length;
    final eng = wrong.where((w) => w['subject'] == 'english').length;
    return pw.Container(
        padding: const pw.EdgeInsets.all(18),
        decoration: pw.BoxDecoration(
            color: const PdfColor.fromInt(0xFFFFF1F2),
            border: pw.Border.all(color: const PdfColor.fromInt(0xFFFCA5A5), width: 1.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12))),
        child: pw.Row(children: [
          pw.Expanded(
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Text('Xato javoblar',
                    style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: _red)),
                pw.SizedBox(height: 6),
                pw.Text('Matematika: $math ta  Ingliz tili: $eng ta',
                    style: const pw.TextStyle(fontSize: 12, color: _ink2)),
              ])),
          pw.Text('${wrong.length}',
              style: pw.TextStyle(
                  fontSize: 34, fontWeight: pw.FontWeight.bold, color: _red)),
        ]));
  }

  static pw.Widget _wrongHeader(String name) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFFFF7ED),
          border: pw.Border.all(color: _orange, width: 1.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12))),
      child: pw.Row(children: [
        pw.Text('Xato javoblar tahlili',
            style: pw.TextStyle(
                fontSize: 16, fontWeight: pw.FontWeight.bold, color: _orange)),
        pw.Spacer(),
        pw.Text(name, style: const pw.TextStyle(fontSize: 12, color: _ink2)),
      ]));

  static pw.Widget _wrongItem(Map<String, dynamic> w, pw.MemoryImage? img) {
    final pos = w['position'] as int? ?? 0;
    final subj = w['subject'] == 'math' ? 'Matematika' : 'Ingliz tili';
    final subjClr = w['subject'] == 'math' ? _blue : _teal;
    final prompt = w['prompt'] as String? ?? '';
    final sAns = (w['student_answer'] as String? ?? '').toUpperCase();
    final cAns = (w['correct_answer'] as String? ?? '').toUpperCase();
    final sText = w['student_text'] as String? ?? '';
    final cText = w['correct_text'] as String? ?? '';

    return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(color: _border, width: 1.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10))),
        child: pw
            .Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Row(children: [
            pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: pw.BoxDecoration(
                    color: _bgLight,
                    border: pw.Border.all(color: _border),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(6))),
                child: pw.Text('$pos',
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink2))),
            pw.SizedBox(width: 10),
            pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: pw.BoxDecoration(
                    color: PdfColor(subjClr.red / 255, subjClr.green / 255,
                        subjClr.blue / 255, 0.1),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(12))),
                child: pw.Text(subj,
                    style: pw.TextStyle(fontSize: 11, color: subjClr))),
          ]),
          pw.SizedBox(height: 10),
          pw.Text(prompt,
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold, color: _ink1, lineSpacing: 2)),
          
          if (img != null) ...[
            pw.SizedBox(height: 10),
            pw.ClipRRect(
              horizontalRadius: 6,
              verticalRadius: 6,
              child: pw.Image(img, height: 120, fit: pw.BoxFit.contain),
            ),
          ],
          
          pw.SizedBox(height: 12),
          pw.Row(children: [
            pw.Expanded(child: _answerBadge(sAns, sText, false)),
            pw.SizedBox(width: 10),
            pw.Expanded(child: _answerBadge(cAns, cText, true)),
          ]),
        ]));
  }

  static pw.Widget _answerBadge(String label, String text, bool ok) {
    final c = ok ? _green : _red;
    return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
            color: PdfColor(c.red / 255, c.green / 255, c.blue / 255, 0.07),
            border: pw.Border.all(
                color: PdfColor(c.red / 255, c.green / 255, c.blue / 255, 0.3)),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
        child: pw.Row(children: [
          pw.Container(
              width: 20,
              height: 20,
              decoration: pw.BoxDecoration(
                  color:
                      PdfColor(c.red / 255, c.green / 255, c.blue / 255, 0.15),
                  border: pw.Border.all(
                      color: PdfColor(
                          c.red / 255, c.green / 255, c.blue / 255, 0.4)),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(6))),
              child: pw.Center(
                  child: pw.Text(label,
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: c)))),
          pw.SizedBox(width: 8),
          pw.Expanded(
              child: pw.Text(text,
                  style: pw.TextStyle(fontSize: 11, color: c, lineSpacing: 2))),
        ]));
  }

  static pw.Widget _footer() => pw.Column(children: [
        pw.Divider(color: _border),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          pw.Text('Alochi Monitoring tizimi',
              style: const pw.TextStyle(fontSize: 10, color: _ink3)),
          pw.Spacer(),
          pw.Text('alochi.org',
              style: const pw.TextStyle(fontSize: 10, color: _orange)),
        ]),
      ]);

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, "0")}.${d.month.toString().padLeft(2, "0")}.${d.year}';
}
