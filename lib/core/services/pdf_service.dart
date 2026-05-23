import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfService {
  static Future<Uint8List> generateResultPdf({
    required String firstName,
    required String lastName,
    required String group,
    required int grade,
    required int variant,
    required int mathOk,
    required int mathTotal,
    required int engOk,
    required int engTotal,
    required int pct,
    required List<MapEntry<String, ({int ok, int tot})>> mathTopics,
    required List<MapEntry<String, ({int ok, int tot})>> engTopics,
  }) async {
    final pdf = pw.Document();

    // Load fonts for correct Uzbek/Cyrillic rendering
    final fontData = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/Inter-Bold.ttf');
    final ttf = pw.Font.ttf(fontData);
    final ttfBold = pw.Font.ttf(fontBoldData);

    // Load logo
    pw.MemoryImage? logoImage;
    try {
      final logoBytes = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {}

    final dateStr = '${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')}.${DateTime.now().year}';

    final isPass = pct >= 60;
    final primaryColor = PdfColor.fromHex('#F97316');
    final passColor = PdfColor.fromHex('#10B981');
    final failColor = PdfColor.fromHex('#EF4444');
    final textColor = PdfColor.fromHex('#1A1A1A');
    final subTextColor = PdfColor.fromHex('#6B7280');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // HEADER
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      if (logoImage != null)
                        pw.Image(logoImage, width: 50, height: 50),
                      pw.SizedBox(width: 10),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Alochi Monitoring', style: pw.TextStyle(font: ttfBold, fontSize: 24, color: primaryColor)),
                          pw.Text('Oflayn Test Natijasi', style: pw.TextStyle(font: ttf, fontSize: 14, color: subTextColor)),
                        ],
                      )
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Sana:', style: pw.TextStyle(font: ttf, fontSize: 10, color: subTextColor)),
                      pw.Text(dateStr, style: pw.TextStyle(font: ttfBold, fontSize: 12, color: textColor)),
                    ],
                  )
                ],
              ),
              pw.SizedBox(height: 30),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 20),

              // STUDENT INFO
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('O\'quvchi', style: pw.TextStyle(font: ttf, fontSize: 12, color: subTextColor)),
                        pw.Text('$lastName $firstName', style: pw.TextStyle(font: ttfBold, fontSize: 18, color: textColor)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Sinf va Variant', style: pw.TextStyle(font: ttf, fontSize: 12, color: subTextColor)),
                        pw.Text('$grade-sinf | V$variant | $group', style: pw.TextStyle(font: ttfBold, fontSize: 14, color: textColor)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // SCORE SUMMARY
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildScoreCard('Umumiy Natija', '$pct%', isPass ? passColor : failColor, ttf, ttfBold),
                  _buildScoreCard('Matematika', '$mathOk / $mathTotal', PdfColor.fromHex('#0EA5E9'), ttf, ttfBold),
                  _buildScoreCard('Ingliz tili', '$engOk / $engTotal', PdfColor.fromHex('#8B5CF6'), ttf, ttfBold),
                ],
              ),
              pw.SizedBox(height: 40),

              // TOPICS BREAKDOWN
              pw.Text('Mavzular bo\'yicha tahlil', style: pw.TextStyle(font: ttfBold, fontSize: 16, color: textColor)),
              pw.SizedBox(height: 15),

              if (mathTopics.isNotEmpty) ...[
                pw.Text('Matematika', style: pw.TextStyle(font: ttfBold, fontSize: 14, color: PdfColor.fromHex('#0EA5E9'))),
                pw.SizedBox(height: 5),
                _buildTopicsTable(mathTopics, ttf, ttfBold),
                pw.SizedBox(height: 20),
              ],

              if (engTopics.isNotEmpty) ...[
                pw.Text('Ingliz tili', style: pw.TextStyle(font: ttfBold, fontSize: 14, color: PdfColor.fromHex('#8B5CF6'))),
                pw.SizedBox(height: 5),
                _buildTopicsTable(engTopics, ttf, ttfBold),
              ],
              
              pw.Spacer(),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text('Alochi Education | www.alochi.uz', style: pw.TextStyle(font: ttf, fontSize: 10, color: subTextColor)),
              )
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildScoreCard(String title, String value, PdfColor color, pw.Font ttf, pw.Font ttfBold) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: color, width: 2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(title, style: pw.TextStyle(font: ttf, fontSize: 12, color: color)),
          pw.SizedBox(height: 8),
          pw.Text(value, style: pw.TextStyle(font: ttfBold, fontSize: 22, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _buildTopicsTable(List<MapEntry<String, ({int ok, int tot})>> topics, pw.Font ttf, pw.Font ttfBold) {
    return pw.TableHelper.fromTextArray(
      context: null,
      border: pw.TableBorder.all(color: PdfColors.grey300),
      headerStyle: pw.TextStyle(font: ttfBold, fontSize: 11, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey700),
      cellStyle: pw.TextStyle(font: ttf, fontSize: 10, color: PdfColor.fromHex('#1A1A1A')),
      cellAlignment: pw.Alignment.centerLeft,
      headers: ['Mavzu nomi', 'To\'g\'ri javoblar', 'Foiz'],
      data: topics.map((e) {
        final p = e.value.tot > 0 ? (e.value.ok * 100 ~/ e.value.tot) : 0;
        return [
          e.key,
          '${e.value.ok} / ${e.value.tot}',
          '$p%'
        ];
      }).toList(),
    );
  }
}
