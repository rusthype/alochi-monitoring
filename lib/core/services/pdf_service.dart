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
    List<MapEntry<String, ({int ok, int tot})>> topicScores = const [],
    List<MapEntry<String, ({int ok, int tot})>> unitScores = const [],
    Map<String, dynamic>? aiSummary,
  }) async {
    final pdf = pw.Document();

    final fontData = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/Inter-Bold.ttf');
    final ttf = pw.Font.ttf(fontData);
    final ttfBold = pw.Font.ttf(fontBoldData);

    final dateStr = '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}';

    final totalOk = mathOk + engOk;
    final totalQ = mathTotal + engTotal;
    final totalErr = totalQ - totalOk;

    // colors
    final cBlack = PdfColor.fromHex('#111111');
    final cGrayBg = PdfColor.fromHex('#f7f7f7');
    final cRed = PdfColor.fromHex('#EF4444');
    final cGreen = PdfColor.fromHex('#10B981');
    final cOrange = PdfColor.fromHex('#FF8A00');
    final cBlue = PdfColor.fromHex('#2563EB');

    String statusText = pct < 60 ? "Qo'shimcha mashq kerak" : "Yaxshi natija";
    PdfColor pctColor = pct < 60 ? cRed : cGreen;

    List<MapEntry<String, ({int ok, int tot})>> combinedTopics = [];
    if (topicScores.isNotEmpty) {
      combinedTopics = List.from(topicScores);
    } else {
      combinedTopics = [...mathTopics, ...engTopics];
    }

    String sanitize(String raw) {
      return raw.replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}]', unicode: true), '').trim();
    }
    
    final summaryStr = aiSummary != null ? sanitize(aiSummary['summary']?.toString() ?? '') : '';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(35),
        build: (pw.Context context) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              margin: const pw.EdgeInsets.only(bottom: 16),
              decoration: pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: cBlack, width: 2.5)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "A'LOCHI — DIAGNOSTIK PASPORT",
                    style: pw.TextStyle(font: ttfBold, fontSize: 11, color: PdfColor.fromHex('#555555'), letterSpacing: 1.5),
                  ),
                  pw.Text(
                    "$dateStr · Variant $variant",
                    style: pw.TextStyle(font: ttf, fontSize: 10, color: PdfColor.fromHex('#888888')),
                  ),
                ],
              ),
            ),
            
            // Profile Card
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              margin: const pw.EdgeInsets.only(bottom: 16),
              decoration: pw.BoxDecoration(
                color: cGrayBg,
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    width: 54, height: 54,
                    decoration: pw.BoxDecoration(color: cBlack, shape: pw.BoxShape.circle),
                    child: pw.Center(
                      child: pw.Text(
                        firstName.isNotEmpty ? firstName[0].toLowerCase() : '',
                        style: pw.TextStyle(font: ttfBold, fontSize: 22, color: PdfColors.white),
                      )
                    )
                  ),
                  pw.SizedBox(width: 18),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("$firstName $lastName", style: pw.TextStyle(font: ttfBold, fontSize: 20)),
                        pw.SizedBox(height: 5),
                        pw.Row(
                          children: [
                            pw.Text("$grade-sinf", style: pw.TextStyle(font: ttf, fontSize: 12, color: PdfColor.fromHex('#555555'))),
                            pw.SizedBox(width: 16),
                            pw.Text(group, style: pw.TextStyle(font: ttf, fontSize: 12, color: PdfColor.fromHex('#555555'))),
                            pw.SizedBox(width: 16),
                            pw.Text("Variant $variant", style: pw.TextStyle(font: ttf, fontSize: 12, color: PdfColor.fromHex('#555555'))),
                          ]
                        ),
                      ]
                    )
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 22),
                    decoration: pw.BoxDecoration(
                      color: cBlack,
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text("$pct%", style: pw.TextStyle(font: ttfBold, fontSize: 32, color: pctColor)),
                        pw.SizedBox(height: 3),
                        pw.Text(statusText.toUpperCase(), style: pw.TextStyle(font: ttf, fontSize: 10, color: PdfColors.white)),
                      ]
                    )
                  )
                ]
              )
            ),

            // Stats Grid
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#eeeeee'), width: 1.5), borderRadius: pw.BorderRadius.circular(10)),
                    child: pw.Column(
                      children: [
                        pw.Text("$totalOk", style: pw.TextStyle(font: ttfBold, fontSize: 26, color: cGreen)),
                        pw.SizedBox(height: 2),
                        pw.Text("To'g'ri javob", style: pw.TextStyle(font: ttf, fontSize: 11, color: PdfColor.fromHex('#888888'))),
                      ]
                    )
                  )
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#eeeeee'), width: 1.5), borderRadius: pw.BorderRadius.circular(10)),
                    child: pw.Column(
                      children: [
                        pw.Text("$totalErr", style: pw.TextStyle(font: ttfBold, fontSize: 26, color: cRed)),
                        pw.SizedBox(height: 2),
                        pw.Text("Xato javob", style: pw.TextStyle(font: ttf, fontSize: 11, color: PdfColor.fromHex('#888888'))),
                      ]
                    )
                  )
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#eeeeee'), width: 1.5), borderRadius: pw.BorderRadius.circular(10)),
                    child: pw.Column(
                      children: [
                        pw.Text("$totalQ", style: pw.TextStyle(font: ttfBold, fontSize: 26, color: cOrange)),
                        pw.SizedBox(height: 2),
                        pw.Text("Jami savol", style: pw.TextStyle(font: ttf, fontSize: 11, color: PdfColor.fromHex('#888888'))),
                      ]
                    )
                  )
                ),
              ]
            ),
            pw.SizedBox(height: 16),

            // Topics List
            if (combinedTopics.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.only(bottom: 5),
                margin: const pw.EdgeInsets.only(bottom: 8),
                decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#eeeeee'), width: 1))),
                child: pw.Text("MAVZU BO'YICHA TAHLIL", style: pw.TextStyle(font: ttfBold, fontSize: 10, color: PdfColor.fromHex('#888888'), letterSpacing: 0.8)),
              ),
              _buildTable(combinedTopics, ttf, ttfBold, cGreen, cRed),
              pw.SizedBox(height: 18),
            ],

            if (unitScores.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.only(bottom: 5),
                margin: const pw.EdgeInsets.only(bottom: 8),
                decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#eeeeee'), width: 1))),
                child: pw.Text("UNIT BO'YICHA TAHLIL", style: pw.TextStyle(font: ttfBold, fontSize: 10, color: PdfColor.fromHex('#888888'), letterSpacing: 0.8)),
              ),
              _buildTable(unitScores, ttf, ttfBold, cGreen, cRed),
              pw.SizedBox(height: 18),
            ],

            // Footer Grid (14 Kunlik reja & AI xulosa)
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Left
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.only(bottom: 5),
                        margin: const pw.EdgeInsets.only(bottom: 10),
                        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#eeeeee'), width: 1))),
                        child: pw.Text("14 KUNLIK REJA", style: pw.TextStyle(font: ttfBold, fontSize: 10, color: PdfColor.fromHex('#888888'), letterSpacing: 0.8)),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.only(left: 14),
                        decoration: pw.BoxDecoration(border: pw.Border(left: pw.BorderSide(color: PdfColor.fromHex('#eeeeee'), width: 2.5))),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _buildPlanItem("1–3 KUN", _getTopicName(combinedTopics, 0), "Har kuni 15 daqiqa mashq", cOrange, ttf, ttfBold),
                            pw.SizedBox(height: 10),
                            _buildPlanItem("4–7 KUN", _getTopicName(combinedTopics, 1), "Har kuni 5 ta misol yechish", cBlue, ttf, ttfBold),
                            pw.SizedBox(height: 10),
                            _buildPlanItem("8–11 KUN", "Aralash mashqlar", "Barcha mavzularni takrorlash", cGreen, ttf, ttfBold),
                            pw.SizedBox(height: 10),
                            _buildPlanItem("12–14 KUN", "Nazorat testi", "Natijalarni solishtirish", PdfColor.fromHex('#888888'), ttf, ttfBold),
                          ]
                        )
                      )
                    ]
                  )
                ),
                pw.SizedBox(width: 14),
                // Right
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.only(bottom: 5),
                        margin: const pw.EdgeInsets.only(bottom: 10),
                        decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#eeeeee'), width: 1))),
                        child: pw.Text("AI XULOSA", style: pw.TextStyle(font: ttfBold, fontSize: 10, color: PdfColor.fromHex('#888888'), letterSpacing: 0.8)),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 13, horizontal: 15),
                        margin: const pw.EdgeInsets.only(bottom: 12),
                        decoration: pw.BoxDecoration(color: cBlack, borderRadius: pw.BorderRadius.circular(10)),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text("A'LOCHI AI", style: pw.TextStyle(font: ttfBold, fontSize: 9, color: PdfColor.fromHex('#888888'), letterSpacing: 0.6)),
                            pw.SizedBox(height: 6),
                            pw.Text(
                              summaryStr.isNotEmpty ? summaryStr : "$firstName $pct% natija ko'rsatdi. O'zlashtirish darajasiga qarab 14 kunlik reja bilan ishlash tavsiya etiladi.",
                              style: pw.TextStyle(font: ttf, fontSize: 12, color: PdfColors.white, lineSpacing: 1.75)
                            ),
                          ]
                        )
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                        decoration: pw.BoxDecoration(color: cGrayBg, borderRadius: pw.BorderRadius.circular(10)),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text("Ota-onaga", style: pw.TextStyle(font: ttfBold, fontSize: 11, color: cBlack)),
                            pw.SizedBox(height: 5),
                            pw.Text("• Har kuni 20–30 daqiqa o'qish vaqti\n• Zaif mavzularni birgalikda takrorlang\n• Rag'batlantiring va sabr bilan o'rgating",
                              style: pw.TextStyle(font: ttf, fontSize: 11, color: PdfColor.fromHex('#444444'), lineSpacing: 1.8)),
                          ]
                        )
                      )
                    ]
                  )
                )
              ]
            ),
            
            pw.SizedBox(height: 18),
            // Bottom most
            pw.Container(
              padding: const pw.EdgeInsets.only(top: 8),
              decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColor.fromHex('#eeeeee'), width: 1))),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("A'lochi Ta'lim · alochi.uz", style: pw.TextStyle(font: ttf, fontSize: 10, color: PdfColor.fromHex('#bbbbbb'))),
                  pw.Text("$group · $grade-sinf · $dateStr", style: pw.TextStyle(font: ttf, fontSize: 10, color: PdfColor.fromHex('#bbbbbb'))),
                ]
              )
            )
          ];
        }
      )
    );

    return pdf.save();
  }

  static String _getTopicName(List<MapEntry<String, ({int ok, int tot})>> topics, int index) {
    if (topics.isEmpty) return "Zaif mavzu";
    // Sort to find the weakest
    final sorted = List<MapEntry<String, ({int ok, int tot})>>.from(topics)
      ..sort((a, b) {
        final pa = a.value.tot > 0 ? a.value.ok / a.value.tot : 0.0;
        final pb = b.value.tot > 0 ? b.value.ok / b.value.tot : 0.0;
        return pa.compareTo(pb);
      });
    if (index < sorted.length) return sorted[index].key;
    return sorted.last.key;
  }

  static pw.Widget _buildTable(
    List<MapEntry<String, ({int ok, int tot})>> items,
    pw.Font ttf, pw.Font ttfBold, PdfColor green, PdfColor red
  ) {
    return pw.Column(
      children: items.map((e) {
        final pctVal = e.value.tot > 0 ? (e.value.ok * 100 ~/ e.value.tot) : 0;
        final isGood = pctVal >= 60;
        final color = isGood ? green : red;
        final bgColor = isGood ? PdfColor(green.red, green.green, green.blue, 0.13) : PdfColor(red.red, red.green, red.blue, 0.13);
        final badgeText = isGood ? "Yaxshi o'zlashtirilgan" : "Qayta o'rganish";

        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#f3f3f3'), width: 1))),
          child: pw.Row(
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Text(e.key, style: pw.TextStyle(font: ttf, fontSize: 13, color: PdfColor.fromHex('#111111')))
              ),
              pw.Container(
                width: 130,
                height: 7,
                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#eeeeee'), borderRadius: pw.BorderRadius.circular(20)),
                child: pw.Row(
                  children: [
                    if (pctVal > 0)
                      pw.Expanded(
                        flex: pctVal,
                        child: pw.Container(
                          decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(20))
                        )
                      ),
                    if (pctVal < 100)
                      pw.Expanded(flex: 100 - pctVal, child: pw.SizedBox()),
                  ]
                )
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  "${e.value.ok}/${e.value.tot} — $pctVal%", 
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(font: ttfBold, fontSize: 12, color: color)
                )
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Container(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 9),
                    decoration: pw.BoxDecoration(color: bgColor, borderRadius: pw.BorderRadius.circular(20)),
                    child: pw.Text(badgeText, style: pw.TextStyle(font: ttfBold, fontSize: 10, color: color))
                  )
                )
              ),
            ]
          )
        );
      }).toList()
    );
  }

  static pw.Widget _buildPlanItem(String title, String topic, String desc, PdfColor titleColor, pw.Font ttf, pw.Font ttfBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(font: ttfBold, fontSize: 9, color: titleColor)),
        pw.SizedBox(height: 2),
        pw.Text(topic, style: pw.TextStyle(font: ttfBold, fontSize: 12, color: PdfColor.fromHex('#111111'))),
        pw.Text(desc, style: pw.TextStyle(font: ttf, fontSize: 11, color: PdfColor.fromHex('#888888'))),
      ]
    );
  }
}
