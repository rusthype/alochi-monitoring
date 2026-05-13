// lib/features/result/pdf_report.dart
// PDF hisobot generatsiyasi — namuna: Natija_muhammadjonov_akramjon.pdf formatida

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../core/models/models.dart';

class PdfReport {
  static const _orange = PdfColor.fromInt(0xFFF97316);
  static const _blue   = PdfColor.fromInt(0xFF3B82F6);
  static const _teal   = PdfColor.fromInt(0xFF0D9488);
  static const _green  = PdfColor.fromInt(0xFF16A34A);
  static const _red    = PdfColor.fromInt(0xFFDC2626);
  static const _ink1   = PdfColor.fromInt(0xFF18181B);
  static const _ink2   = PdfColor.fromInt(0xFF52525B);
  static const _ink3   = PdfColor.fromInt(0xFFA1A1AA);
  static const _border = PdfColor.fromInt(0xFFE4E4E7);
  static const _bg     = PdfColor.fromInt(0xFFFAFAFA);
  static const _bgCard = PdfColors.white;

  static Future<File> generate({
    required StudentSession session,
    required TestPackage package,
    required TestResult result,
    required List<dynamic> wrongAnswers,
  }) async {
    final pdf  = pw.Document();
    final date = _formatDate(DateTime.now());

    // Font
    final fontData   = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf').catchError((_) async {
      // Fallback: system font yo'q bo'lsa default ishlatamiz
      return ByteData(0);
    });
    pw.Font? customFont;
    try {
      if (fontData.lengthInBytes > 0) {
        customFont = pw.Font.ttf(fontData);
      }
    } catch (_) {}

    final baseStyle = customFont != null
        ? pw.TextStyle(font: customFont)
        : const pw.TextStyle();

    // ── Page 1: Umumiy natija ─────────────────────────────────────
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => _buildPage1(ctx, session, package, result, date, baseStyle),
    ));

    // ── Page 2: Xato javoblar ─────────────────────────────────────
    if (wrongAnswers.isNotEmpty) {
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => _buildPage2(ctx, session, wrongAnswers, baseStyle),
      ));
    }

    // Faylga saqlash
    final dir      = await getApplicationDocumentsDirectory();
    final namePart = session.studentName.toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll("'", '')
        .replaceAll(RegExp(r"[^a-z0-9_]"), '');
    final dateTag  = DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '_');
    final file     = File('${dir.path}/Natija_${namePart}_$dateTag.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _buildPage1(
    pw.Context ctx,
    StudentSession session,
    TestPackage package,
    TestResult result,
    String date,
    pw.TextStyle base,
  ) {
    final passed   = result.passed;
    final mainClr  = passed ? _green : _red;
    final totalQ   = package.totalCount;

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [

      // ── Header ─────────────────────────────────────────────────
      pw.Container(
        padding: const pw.EdgeInsets.all(20),
        decoration: pw.BoxDecoration(
          color: _orange,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(14)),
        ),
        child: pw.Row(children: [
          // Logo circle
          pw.Container(
            width: 52, height: 52,
            decoration: const pw.BoxDecoration(
              color: PdfColors.white, shape: pw.BoxShape.circle),
            child: pw.Center(child: pw.Text('A',
              style: base.copyWith(fontSize: 26, fontWeight: pw.FontWeight.bold,
                color: _orange))),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Alochi Monitoring', style: base.copyWith(
              fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
            pw.Text('Monitoring test natijasi', style: base.copyWith(
              fontSize: 12, color: const PdfColor(1, 1, 1, 0.7))),
          ])),
          pw.Text(date, style: base.copyWith(fontSize: 11, color: const PdfColor(1, 1, 1, 0.7))),
        ]),
      ),
      pw.SizedBox(height: 20),

      // ── Student info + verdict ──────────────────────────────────
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [

        // Student card
        pw.Expanded(flex: 3, child: pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: _bgCard, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            border: pw.Border.all(color: _border),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text("O'quvchi", style: base.copyWith(fontSize: 10, color: _ink3)),
            pw.SizedBox(height: 4),
            pw.Text(session.studentName, style: base.copyWith(
              fontSize: 16, fontWeight: pw.FontWeight.bold, color: _ink1)),
            pw.SizedBox(height: 12),
            _infoRow(base, "🏫", '${session.grade}-sinf'),
            pw.SizedBox(height: 6),
            _infoRow(base, "#", 'Variant ${session.variant}'),
            if (session.groupName != null) ...[
              pw.SizedBox(height: 6),
              _infoRow(base, "👥", session.groupName!),
            ],
            pw.SizedBox(height: 6),
            _infoRow(base, "📅", date),
          ]),
        )),
        pw.SizedBox(width: 12),

        // Score ring + verdict
        pw.Expanded(flex: 2, child: pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: passed ? const PdfColor.fromInt(0xFFF0FDF4) : const PdfColor.fromInt(0xFFFFF1F2),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
            border: pw.Border.all(color: PdfColor(mainClr.red/255, mainClr.green/255, mainClr.blue/255, 0.3)),
          ),
          child: pw.Column(children: [
            // Big score
            pw.Container(
              width: 80, height: 80,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: PdfColor(mainClr.red/255, mainClr.green/255, mainClr.blue/255, 0.1),
                border: pw.Border.all(color: mainClr, width: 3),
              ),
              child: pw.Center(child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                pw.Text('${result.totalPct}%', style: base.copyWith(
                  fontSize: 22, fontWeight: pw.FontWeight.bold, color: mainClr)),
                pw.Text('ball', style: base.copyWith(fontSize: 9, color: mainClr)),
              ])),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: pw.BoxDecoration(
                color: mainClr, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
              ),
              child: pw.Text(
                passed ? "✓  O'tdi" : "✗  O'tmadi",
                style: base.copyWith(fontSize: 12, fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              passed ? "Tabriklaymiz!" : "Harakat qiling!",
              style: base.copyWith(fontSize: 11, color: mainClr),
            ),
          ]),
        )),
      ]),
      pw.SizedBox(height: 16),

      // ── Subject bars ───────────────────────────────────────────
      pw.Text('Fanlar bo\'yicha natija', style: base.copyWith(
        fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink1)),
      pw.SizedBox(height: 10),
      pw.Row(children: [
        pw.Expanded(child: _subjectCard(base, 'Matematika',
          result.mathScore, package.mathCount, _blue)),
        pw.SizedBox(width: 12),
        pw.Expanded(child: _subjectCard(base, 'Ingliz tili',
          result.engScore, package.engCount, _teal)),
      ]),
      pw.SizedBox(height: 16),

      // ── Jami ───────────────────────────────────────────────────
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: pw.BoxDecoration(
          color: _bg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          border: pw.Border.all(color: _border),
        ),
        child: pw.Row(children: [
          pw.Text('Jami to\'g\'ri javoblar:', style: base.copyWith(fontSize: 12, color: _ink2)),
          pw.Spacer(),
          pw.Text('${result.mathScore + result.engScore} / $totalQ',
            style: base.copyWith(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _ink1)),
        ]),
      ),
      pw.SizedBox(height: 16),

      // ── Tavsiyalar ─────────────────────────────────────────────
      _recommendationBox(base, result, package),

      pw.Spacer(),
      // Footer
      pw.Divider(color: _border),
      pw.SizedBox(height: 6),
      pw.Row(children: [
        pw.Text('Alochi Monitoring tizimi', style: base.copyWith(fontSize: 9, color: _ink3)),
        pw.Spacer(),
        pw.Text('alochi.org', style: base.copyWith(fontSize: 9, color: _orange)),
      ]),
    ]);
  }

  static List<pw.Widget> _buildPage2(
    pw.Context ctx,
    StudentSession session,
    List<dynamic> wrongAnswers,
    pw.TextStyle base,
  ) {
    final mathWrong = wrongAnswers.where((w) => w['subject'] == 'math').toList();
    final engWrong  = wrongAnswers.where((w) => w['subject'] == 'english').toList();

    return [
      // Header
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0x14F97316),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          border: pw.Border.all(color: const PdfColor.fromInt(0x4DF97316)),
        ),
        child: pw.Row(children: [
          pw.Text('Xato javoblar tahlili', style: base.copyWith(
            fontSize: 14, fontWeight: pw.FontWeight.bold, color: _orange)),
          pw.Spacer(),
          pw.Text(session.studentName, style: base.copyWith(fontSize: 11, color: _ink2)),
        ]),
      ),
      pw.SizedBox(height: 16),

      // Wrong answers stats row
      pw.Row(children: [
        pw.Expanded(child: _wrongStatCard(base, 'Matematika xatolari', mathWrong.length, _blue)),
        pw.SizedBox(width: 12),
        pw.Expanded(child: _wrongStatCard(base, 'Ingliz tili xatolari', engWrong.length, _teal)),
        pw.SizedBox(width: 12),
        pw.Expanded(child: _wrongStatCard(base, 'Jami xatolari', wrongAnswers.length, _red)),
      ]),
      pw.SizedBox(height: 16),

      // Wrong answer list
      if (mathWrong.isNotEmpty) ...[
        _sectionHeader(base, 'Matematika', _blue),
        pw.SizedBox(height: 8),
        ...mathWrong.map((w) => _wrongItem(base, w)),
        pw.SizedBox(height: 14),
      ],
      if (engWrong.isNotEmpty) ...[
        _sectionHeader(base, 'Ingliz tili', _teal),
        pw.SizedBox(height: 8),
        ...engWrong.map((w) => _wrongItem(base, w)),
      ],
    ];
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static pw.Widget _infoRow(pw.TextStyle base, String icon, String text) =>
    pw.Text("$icon $text", style: base.copyWith(fontSize: 12, color: _ink2));

  static pw.Widget _subjectCard(pw.TextStyle base, String label, int score, int total, PdfColor color) {
    final pct = total > 0 ? score / total : 0.0;
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _bgCard,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: base.copyWith(fontSize: 11, color: _ink3)),
        pw.SizedBox(height: 8),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('$score', style: base.copyWith(
            fontSize: 28, fontWeight: pw.FontWeight.bold, color: _ink1)),
          pw.SizedBox(width: 4),
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text('/ $total', style: base.copyWith(fontSize: 12, color: _ink3)),
          ),
        ]),
        pw.SizedBox(height: 8),
        // Progress bar
        pw.ClipRRect(
          horizontalRadius: 4, verticalRadius: 4,
          child: pw.Stack(children: [
            pw.Container(height: 8, color: PdfColor(color.red/255, color.green/255, color.blue/255, 0.1)),
            pw.Container(width: pct * 400, height: 8, color: color),
          ]),
        ),
        pw.SizedBox(height: 4),
        pw.Text('${(pct * 100).round()}%', style: base.copyWith(
          fontSize: 11, color: color, fontWeight: pw.FontWeight.bold)),
      ]),
    );
  }

  static pw.Widget _recommendationBox(pw.TextStyle base, TestResult result, TestPackage package) {
    final mathPct = package.mathCount > 0 ? result.mathScore / package.mathCount : 0.0;
    final engPct  = package.engCount  > 0 ? result.engScore  / package.engCount  : 0.0;

    final recs = <String>[];
    if (mathPct < 0.6) recs.add("Matematika: ko'proq mashq kerak (${(mathPct * 100).round()}%)");
    if (engPct  < 0.6) recs.add("Ingliz tili: grammatika va lug'at ustida ishlang (${(engPct * 100).round()}%)");
    if (mathPct >= 0.8 && engPct >= 0.8) recs.add("Ajoyib natija! Shu saviyani saqlang.");
    else if (result.totalPct >= 60) recs.add("Yaxshi natija! Zaif tomonlarni mustahkamlang.");

    if (recs.isEmpty) return pw.SizedBox.shrink();

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFFFFBEB),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFFDE68A)),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Tavsiyalar', style: base.copyWith(
          fontSize: 12, fontWeight: pw.FontWeight.bold,
          color: const PdfColor.fromInt(0xFF92400E))),
        pw.SizedBox(height: 8),
        ...recs.map((r) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Row(children: [
            pw.Container(width: 5, height: 5, decoration: const pw.BoxDecoration(
              shape: pw.BoxShape.circle, color: PdfColor.fromInt(0xFFF59E0B))),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Text(r, style: base.copyWith(
              fontSize: 11, color: const PdfColor.fromInt(0xFF78350F)))),
          ]),
        )),
      ]),
    );
  }

  static pw.Widget _wrongStatCard(pw.TextStyle base, String label, int count, PdfColor color) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColor(color.red/255, color.green/255, color.blue/255, 0.06),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: PdfColor(color.red/255, color.green/255, color.blue/255, 0.2)),
      ),
      child: pw.Column(children: [
        pw.Text('$count', style: base.copyWith(
          fontSize: 24, fontWeight: pw.FontWeight.bold, color: color)),
        pw.Text(label, style: base.copyWith(fontSize: 10, color: _ink3),
          textAlign: pw.TextAlign.center),
      ]),
    );

  static pw.Widget _sectionHeader(pw.TextStyle base, String label, PdfColor color) =>
    pw.Row(children: [
      pw.Container(width: 4, height: 18,
        decoration: pw.BoxDecoration(
          color: color, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)))),
      pw.SizedBox(width: 8),
      pw.Text(label, style: base.copyWith(
        fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
    ]);

  static pw.Widget _wrongItem(pw.TextStyle base, Map<String, dynamic> w) {
    final pos   = w['position'] as int? ?? 0;
    final sAns  = (w['student_answer'] as String? ?? '').toUpperCase();
    final cAns  = (w['correct_answer'] as String? ?? '').toUpperCase();
    final sText = w['student_text'] as String? ?? '';
    final cText = w['correct_text'] as String? ?? '';
    final prompt = w['prompt'] as String? ?? '';

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _bgCard,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: pw.BoxDecoration(
              color: _bg, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              border: pw.Border.all(color: _border),
            ),
            child: pw.Text('$pos', style: base.copyWith(
              fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink2)),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(child: pw.Text(prompt, style: base.copyWith(
            fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink1))),
        ]),
        pw.SizedBox(height: 8),
        pw.Row(children: [
          pw.Expanded(child: _answerBadge(base, sAns, sText, isCorrect: false)),
          pw.SizedBox(width: 8),
          pw.Expanded(child: _answerBadge(base, cAns, cText, isCorrect: true)),
        ]),
      ]),
    );
  }

  static pw.Widget _answerBadge(pw.TextStyle base, String label, String text, {required bool isCorrect}) {
    final color = isCorrect ? _green : _red;
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        color: PdfColor(color.red/255, color.green/255, color.blue/255, 0.07),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: PdfColor(color.red/255, color.green/255, color.blue/255, 0.25)),
      ),
      child: pw.Row(children: [
        pw.Container(
          width: 18, height: 18,
          decoration: pw.BoxDecoration(
            color: PdfColor(color.red/255, color.green/255, color.blue/255, 0.15),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            border: pw.Border.all(color: PdfColor(color.red/255, color.green/255, color.blue/255, 0.4)),
          ),
          child: pw.Center(child: pw.Text(label, style: base.copyWith(
            fontSize: 9, fontWeight: pw.FontWeight.bold, color: color))),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(child: pw.Text(text, style: base.copyWith(
          fontSize: 10, color: color),
          maxLines: 2, overflow: pw.TextOverflow.clip)),
      ]),
    );
  }

  static String _formatDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
}
