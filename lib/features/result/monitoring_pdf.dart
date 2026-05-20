// lib/features/result/monitoring_pdf.dart
// Monitoring test natijasi uchun PDF generator

import 'dart:io';
import 'package:flutter/material.dart' show BuildContext;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class MonitoringPdf {
  static const _orange = PdfColor.fromInt(0xFFF97316);
  static const _blue   = PdfColor.fromInt(0xFF2563EB);
  static const _purple = PdfColor.fromInt(0xFF7C3AED);
  static const _green  = PdfColor.fromInt(0xFF16A34A);
  static const _ink1   = PdfColor.fromInt(0xFF18181B);
  static const _ink2   = PdfColor.fromInt(0xFF71717A);
  static const _bg     = PdfColor.fromInt(0xFFFAFAFA);
  static const _border = PdfColor.fromInt(0xFFE4E4E7);

  static Future<File> generate({
    required String studentName,
    required int grade,
    required String variant,
    required int pct,
    required int vocabCor,
    required int vocabTot,
    required int engCor,
    required int engTot,
    required int mathCor,
    required int mathTot,
    required String timeTaken,
  }) async {
    final doc  = pw.Document(title: 'Monitoring Natijasi');
    final date = _fmt(DateTime.now());

    final totalCor = vocabCor + engCor + mathCor;
    final totalTot = vocabTot + engTot + mathTot;

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Header
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            decoration: pw.BoxDecoration(
              color: _orange,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('MONITORING TEST NATIJASI',
                      style: pw.TextStyle(color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.SizedBox(height: 4),
                  pw.Text(studentName,
                      style: pw.TextStyle(color: PdfColors.white, fontSize: 20,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text('$grade-sinf · Variant $variant · $date',
                      style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
                ]),
                // Big score
                pw.Container(
                  width: 80, height: 80,
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    shape: pw.BoxShape.circle,
                  ),
                  child: pw.Center(child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text('$pct%', style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold,
                          color: _orange)),
                      pw.Text('$totalCor/$totalTot',
                          style: const pw.TextStyle(fontSize: 10, color: _ink2)),
                    ],
                  )),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),

          // Section scores
          pw.Text("Bo'lim natijalari",
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink1)),
          pw.SizedBox(height: 12),
          pw.Row(children: [
            _ScoreCard(label: "Lug'at", cor: vocabCor, tot: vocabTot, color: _orange),
            pw.SizedBox(width: 12),
            _ScoreCard(label: 'Ingliz tili', cor: engCor, tot: engTot, color: _blue),
            if (mathTot > 0) ...[
              pw.SizedBox(width: 12),
              _ScoreCard(label: 'Matematika', cor: mathCor, tot: mathTot, color: _purple),
            ],
          ]),
          pw.SizedBox(height: 24),

          // Progress bars
          pw.Text('Batafsil',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink1)),
          pw.SizedBox(height: 10),
          _ProgressBar(label: "Lug'at",   cor: vocabCor, tot: vocabTot, color: _orange),
          pw.SizedBox(height: 8),
          _ProgressBar(label: 'Ingliz',   cor: engCor,   tot: engTot,   color: _blue),
          if (mathTot > 0) ...[
            pw.SizedBox(height: 8),
            _ProgressBar(label: 'Matematika', cor: mathCor, tot: mathTot, color: _purple),
          ],
          pw.SizedBox(height: 24),

          // Summary box
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: _bg,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: _border),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _StatItem(label: 'Jami savol', value: '$totalTot'),
                _StatItem(label: "To'g'ri", value: '$totalCor'),
                _StatItem(label: "Xato", value: '${totalTot - totalCor}'),
                if (timeTaken.isNotEmpty)
                  _StatItem(label: 'Vaqt', value: timeTaken),
              ],
            ),
          ),
          pw.Spacer(),

          // Footer
          pw.Divider(color: _border),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('alochi.org', style: const pw.TextStyle(color: _ink2, fontSize: 9)),
              pw.Text(_pctLabel(pct),
                  style: pw.TextStyle(
                      color: pct >= 70 ? _green : _orange,
                      fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Text(date, style: const pw.TextStyle(color: _ink2, fontSize: 9)),
            ],
          ),
        ],
      ),
    ));

    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/monitoring_natija.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static String _pctLabel(int p) =>
      p >= 90 ? "A'lo" : p >= 70 ? 'Yaxshi' : p >= 50 ? "Qoniqarli" : "Kam";

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')}.${d.year}';

  static pw.Widget _ScoreCard({
    required String label, required int cor, required int tot, required PdfColor color,
  }) {
    final pct = tot > 0 ? (cor * 100 ~/ tot) : 0;
    return pw.Expanded(child: pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(children: [
        pw.Text(label, style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
        pw.SizedBox(height: 6),
        pw.Text('$pct%', style: pw.TextStyle(
            color: PdfColors.white, fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.Text('$cor / $tot', style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
      ]),
    ));
  }

  static pw.Widget _ProgressBar({
    required String label, required int cor, required int tot, required PdfColor color,
  }) {
    final pct = tot > 0 ? cor / tot : 0.0;
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 11, color: _ink1)),
        pw.Text('$cor/$tot (${(pct*100).toInt()}%)',
            style: const pw.TextStyle(fontSize: 10, color: _ink2)),
      ]),
      pw.SizedBox(height: 4),
      pw.Container(height: 8, decoration: pw.BoxDecoration(
        color: _border, borderRadius: pw.BorderRadius.circular(4))),
      pw.Transform.translate(
        offset: const PdfPoint(0, -8),
        child: pw.Container(
          height: 8,
          width: double.infinity * pct,
          decoration: pw.BoxDecoration(
            color: color, borderRadius: pw.BorderRadius.circular(4)),
        ),
      ),
    ]);
  }

  static pw.Widget _StatItem({required String label, required String value}) =>
      pw.Column(children: [
        pw.Text(value, style: pw.TextStyle(
            fontSize: 16, fontWeight: pw.FontWeight.bold, color: _ink1)),
        pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _ink2)),
      ]);

  /// Celebration screen dan chaqirish
  static Future<void> shareOrSave({
    required BuildContext context,
    required String studentName,
    required int grade,
    required String variant,
    required int pct,
    required int vocabCor, required int vocabTot,
    required int engCor,   required int engTot,
    required int mathCor,  required int mathTot,
    required String timeTaken,
  }) async {
    final file = await generate(
      studentName: studentName, grade: grade, variant: variant, pct: pct,
      vocabCor: vocabCor, vocabTot: vocabTot,
      engCor: engCor, engTot: engTot,
      mathCor: mathCor, mathTot: mathTot,
      timeTaken: timeTaken,
    );
    await Printing.sharePdf(bytes: await file.readAsBytes(),
        filename: 'monitoring_${studentName.replaceAll(' ', '_')}.pdf');
  }
}
