import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:alochi_monitoring/l10n/app_localizations.dart';

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
    required AppLocalizations l10n,
    List<MapEntry<String, ({int ok, int tot})>> topicScores = const [],
    List<MapEntry<String, ({int ok, int tot})>> unitScores = const [],
    Map<String, dynamic>? aiSummary,
  }) async {
    final pdf = pw.Document();

    final fontData = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/Inter-Bold.ttf');
    final ttf = pw.Font.ttf(fontData);
    final ttfBold = pw.Font.ttf(fontBoldData);

    final dateStr =
        '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}';

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

    String statusText =
        pct < 60 ? l10n.gradeNeedsPractice : l10n.goodResultLabel;
    PdfColor pctColor = pct < 60 ? cRed : cGreen;

    List<MapEntry<String, ({int ok, int tot})>> combinedTopics = [];
    if (topicScores.isNotEmpty) {
      combinedTopics = List.from(topicScores);
    } else {
      combinedTopics = [...mathTopics, ...engTopics];
    }

    String sanitize(String raw) {
      return raw
          .replaceAll(
              RegExp(r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}]', unicode: true),
              '')
          .trim();
    }

    final summaryStr = aiSummary != null
        ? sanitize(aiSummary['summary']?.toString() ?? '')
        : '';

    pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(35),
        build: (pw.Context context) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              margin: const pw.EdgeInsets.only(bottom: 16),
              decoration: pw.BoxDecoration(
                border:
                    pw.Border(bottom: pw.BorderSide(color: cBlack, width: 2.5)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    l10n.diagnosticPassportHeader,
                    style: pw.TextStyle(
                        font: ttfBold,
                        fontSize: 11,
                        color: PdfColor.fromHex('#555555'),
                        letterSpacing: 1.5),
                  ),
                  pw.Text(
                    "$dateStr · ${l10n.variantBadge(variant)}",
                    style: pw.TextStyle(
                        font: ttf,
                        fontSize: 10,
                        color: PdfColor.fromHex('#888888')),
                  ),
                ],
              ),
            ),

            // Profile Card
            pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                margin: const pw.EdgeInsets.only(bottom: 16),
                decoration: pw.BoxDecoration(
                  color: cGrayBg,
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                          width: 54,
                          height: 54,
                          decoration: pw.BoxDecoration(
                              color: cBlack, shape: pw.BoxShape.circle),
                          child: pw.Center(
                              child: pw.Text(
                            firstName.isNotEmpty
                                ? firstName[0].toLowerCase()
                                : '',
                            style: pw.TextStyle(
                                font: ttfBold,
                                fontSize: 22,
                                color: PdfColors.white),
                          ))),
                      pw.SizedBox(width: 18),
                      pw.Expanded(
                          child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                            pw.Text("$firstName $lastName",
                                style:
                                    pw.TextStyle(font: ttfBold, fontSize: 20)),
                            pw.SizedBox(height: 5),
                            pw.Row(children: [
                              pw.Text("$grade-${l10n.gradeShort}",
                                  style: pw.TextStyle(
                                      font: ttf,
                                      fontSize: 12,
                                      color: PdfColor.fromHex('#555555'))),
                              pw.SizedBox(width: 16),
                              pw.Text(group,
                                  style: pw.TextStyle(
                                      font: ttf,
                                      fontSize: 12,
                                      color: PdfColor.fromHex('#555555'))),
                              pw.SizedBox(width: 16),
                              pw.Text(l10n.variantBadge(variant),
                                  style: pw.TextStyle(
                                      font: ttf,
                                      fontSize: 12,
                                      color: PdfColor.fromHex('#555555'))),
                            ]),
                          ])),
                      pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              vertical: 14, horizontal: 22),
                          decoration: pw.BoxDecoration(
                            color: cBlack,
                            borderRadius: pw.BorderRadius.circular(12),
                          ),
                          child: pw.Column(children: [
                            pw.Text("$pct%",
                                style: pw.TextStyle(
                                    font: ttfBold,
                                    fontSize: 32,
                                    color: pctColor)),
                            pw.SizedBox(height: 3),
                            pw.Text(statusText.toUpperCase(),
                                style: pw.TextStyle(
                                    font: ttf,
                                    fontSize: 10,
                                    color: PdfColors.white)),
                          ]))
                    ])),

            // Stats Grid
            pw.Row(children: [
              pw.Expanded(
                  child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: PdfColor.fromHex('#eeeeee'), width: 1.5),
                          borderRadius: pw.BorderRadius.circular(10)),
                      child: pw.Column(children: [
                        pw.Text("$totalOk",
                            style: pw.TextStyle(
                                font: ttfBold, fontSize: 26, color: cGreen)),
                        pw.SizedBox(height: 2),
                        pw.Text(l10n.correctAnswerLabelPdf,
                            style: pw.TextStyle(
                                font: ttf,
                                fontSize: 11,
                                color: PdfColor.fromHex('#888888'))),
                      ]))),
              pw.SizedBox(width: 12),
              pw.Expanded(
                  child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: PdfColor.fromHex('#eeeeee'), width: 1.5),
                          borderRadius: pw.BorderRadius.circular(10)),
                      child: pw.Column(children: [
                        pw.Text("$totalErr",
                            style: pw.TextStyle(
                                font: ttfBold, fontSize: 26, color: cRed)),
                        pw.SizedBox(height: 2),
                        pw.Text(l10n.wrongAnswerLabelPdf,
                            style: pw.TextStyle(
                                font: ttf,
                                fontSize: 11,
                                color: PdfColor.fromHex('#888888'))),
                      ]))),
              pw.SizedBox(width: 12),
              pw.Expanded(
                  child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                              color: PdfColor.fromHex('#eeeeee'), width: 1.5),
                          borderRadius: pw.BorderRadius.circular(10)),
                      child: pw.Column(children: [
                        pw.Text("$totalQ",
                            style: pw.TextStyle(
                                font: ttfBold, fontSize: 26, color: cOrange)),
                        pw.SizedBox(height: 2),
                        pw.Text(l10n.totalQuestionsCountLabel,
                            style: pw.TextStyle(
                                font: ttf,
                                fontSize: 11,
                                color: PdfColor.fromHex('#888888'))),
                      ]))),
            ]),
            pw.SizedBox(height: 16),

            // Topics List
            if (combinedTopics.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.only(bottom: 5),
                margin: const pw.EdgeInsets.only(bottom: 8),
                decoration: pw.BoxDecoration(
                    border: pw.Border(
                        bottom: pw.BorderSide(
                            color: PdfColor.fromHex('#eeeeee'), width: 1))),
                child: pw.Text(l10n.topicAnalysisHeader,
                    style: pw.TextStyle(
                        font: ttfBold,
                        fontSize: 10,
                        color: PdfColor.fromHex('#888888'),
                        letterSpacing: 0.8)),
              ),
              _buildTable(combinedTopics, ttf, ttfBold, cGreen, cRed, l10n),
              pw.SizedBox(height: 18),
            ],

            if (unitScores.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.only(bottom: 5),
                margin: const pw.EdgeInsets.only(bottom: 8),
                decoration: pw.BoxDecoration(
                    border: pw.Border(
                        bottom: pw.BorderSide(
                            color: PdfColor.fromHex('#eeeeee'), width: 1))),
                child: pw.Text(l10n.unitAnalysisHeader,
                    style: pw.TextStyle(
                        font: ttfBold,
                        fontSize: 10,
                        color: PdfColor.fromHex('#888888'),
                        letterSpacing: 0.8)),
              ),
              _buildTable(unitScores, ttf, ttfBold, cGreen, cRed, l10n),
              pw.SizedBox(height: 18),
            ],

            // Footer Grid (14 Kunlik reja & AI xulosa)
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              // Left
              pw.Expanded(
                  child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.only(bottom: 5),
                      margin: const pw.EdgeInsets.only(bottom: 10),
                      decoration: pw.BoxDecoration(
                          border: pw.Border(
                              bottom: pw.BorderSide(
                                  color: PdfColor.fromHex('#eeeeee'),
                                  width: 1))),
                      child: pw.Text(l10n.fourteenDayPlanHeader,
                          style: pw.TextStyle(
                              font: ttfBold,
                              fontSize: 10,
                              color: PdfColor.fromHex('#888888'),
                              letterSpacing: 0.8)),
                    ),
                    pw.Container(
                        padding: const pw.EdgeInsets.only(left: 14),
                        decoration: pw.BoxDecoration(
                            border: pw.Border(
                                left: pw.BorderSide(
                                    color: PdfColor.fromHex('#eeeeee'),
                                    width: 2.5))),
                        child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              _buildPlanItem(
                                  l10n.dayRange1_3,
                                  _getTopicName(combinedTopics, 0, l10n),
                                  l10n.dailyPractice15MinMsg,
                                  cOrange,
                                  ttf,
                                  ttfBold),
                              pw.SizedBox(height: 10),
                              _buildPlanItem(
                                  l10n.dayRange4_7,
                                  _getTopicName(combinedTopics, 1, l10n),
                                  l10n.dailyExamples5Msg,
                                  cBlue,
                                  ttf,
                                  ttfBold),
                              pw.SizedBox(height: 10),
                              _buildPlanItem(
                                  l10n.dayRange8_11,
                                  l10n.mixedExercisesTopic,
                                  l10n.reviewAllTopicsMsg,
                                  cGreen,
                                  ttf,
                                  ttfBold),
                              pw.SizedBox(height: 10),
                              _buildPlanItem(
                                  l10n.dayRange12_14,
                                  l10n.controlTestTopic,
                                  l10n.compareResultsMsg,
                                  PdfColor.fromHex('#888888'),
                                  ttf,
                                  ttfBold),
                            ]))
                  ])),
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
                      decoration: pw.BoxDecoration(
                          border: pw.Border(
                              bottom: pw.BorderSide(
                                  color: PdfColor.fromHex('#eeeeee'),
                                  width: 1))),
                      child: pw.Text(l10n.aiSummaryHeader,
                          style: pw.TextStyle(
                              font: ttfBold,
                              fontSize: 10,
                              color: PdfColor.fromHex('#888888'),
                              letterSpacing: 0.8)),
                    ),
                    pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            vertical: 13, horizontal: 15),
                        margin: const pw.EdgeInsets.only(bottom: 12),
                        decoration: pw.BoxDecoration(
                            color: cBlack,
                            borderRadius: pw.BorderRadius.circular(10)),
                        child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(l10n.alochiAiLabel,
                                  style: pw.TextStyle(
                                      font: ttfBold,
                                      fontSize: 9,
                                      color: PdfColor.fromHex('#888888'),
                                      letterSpacing: 0.6)),
                              pw.SizedBox(height: 6),
                              pw.Text(
                                  summaryStr.isNotEmpty
                                      ? summaryStr
                                      : l10n.aiSummaryFallbackMsg(
                                          firstName, pct),
                                  style: pw.TextStyle(
                                      font: ttf,
                                      fontSize: 12,
                                      color: PdfColors.white,
                                      lineSpacing: 1.75)),
                            ])),
                    pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            vertical: 12, horizontal: 14),
                        decoration: pw.BoxDecoration(
                            color: cGrayBg,
                            borderRadius: pw.BorderRadius.circular(10)),
                        child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(l10n.forParentsLabel,
                                  style: pw.TextStyle(
                                      font: ttfBold,
                                      fontSize: 11,
                                      color: cBlack)),
                              pw.SizedBox(height: 5),
                              pw.Text(l10n.parentTipsText,
                                  style: pw.TextStyle(
                                      font: ttf,
                                      fontSize: 11,
                                      color: PdfColor.fromHex('#444444'),
                                      lineSpacing: 1.8)),
                            ]))
                  ]))
            ]),

            pw.SizedBox(height: 18),
            // Bottom most
            pw.Container(
                padding: const pw.EdgeInsets.only(top: 8),
                decoration: pw.BoxDecoration(
                    border: pw.Border(
                        top: pw.BorderSide(
                            color: PdfColor.fromHex('#eeeeee'), width: 1))),
                child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(l10n.footerBrandTagline,
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 10,
                              color: PdfColor.fromHex('#bbbbbb'))),
                      pw.Text("$group · $grade-${l10n.gradeShort} · $dateStr",
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 10,
                              color: PdfColor.fromHex('#bbbbbb'))),
                    ]))
          ];
        }));

    return pdf.save();
  }

  static String _getTopicName(
      List<MapEntry<String, ({int ok, int tot})>> topics,
      int index,
      AppLocalizations l10n) {
    if (topics.isEmpty) return l10n.weakTopicFallback;
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
      pw.Font ttf,
      pw.Font ttfBold,
      PdfColor green,
      PdfColor red,
      AppLocalizations l10n) {
    return pw.Column(
        children: items.map((e) {
      final pctVal = e.value.tot > 0 ? (e.value.ok * 100 ~/ e.value.tot) : 0;
      final isGood = pctVal >= 60;
      final color = isGood ? green : red;
      final bgColor = isGood
          ? PdfColor(green.red, green.green, green.blue, 0.13)
          : PdfColor(red.red, red.green, red.blue, 0.13);
      final badgeText = isGood ? l10n.wellMasteredBadge : l10n.needsReviewBadge;

      return pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: pw.BoxDecoration(
              border: pw.Border(
                  bottom: pw.BorderSide(
                      color: PdfColor.fromHex('#f3f3f3'), width: 1))),
          child: pw.Row(children: [
            pw.Expanded(
                flex: 4,
                child: pw.Text(e.key,
                    style: pw.TextStyle(
                        font: ttf,
                        fontSize: 13,
                        color: PdfColor.fromHex('#111111')))),
            pw.Container(
                width: 130,
                height: 7,
                decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#eeeeee'),
                    borderRadius: pw.BorderRadius.circular(20)),
                child: pw.Row(children: [
                  if (pctVal > 0)
                    pw.Expanded(
                        flex: pctVal,
                        child: pw.Container(
                            decoration: pw.BoxDecoration(
                                color: color,
                                borderRadius: pw.BorderRadius.circular(20)))),
                  if (pctVal < 100)
                    pw.Expanded(flex: 100 - pctVal, child: pw.SizedBox()),
                ])),
            pw.Expanded(
                flex: 2,
                child: pw.Text("${e.value.ok}/${e.value.tot} — $pctVal%",
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                        font: ttfBold, fontSize: 12, color: color))),
            pw.Expanded(
                flex: 2,
                child: pw.Container(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            vertical: 2, horizontal: 9),
                        decoration: pw.BoxDecoration(
                            color: bgColor,
                            borderRadius: pw.BorderRadius.circular(20)),
                        child: pw.Text(badgeText,
                            style: pw.TextStyle(
                                font: ttfBold, fontSize: 10, color: color))))),
          ]));
    }).toList());
  }

  static pw.Widget _buildPlanItem(String title, String topic, String desc,
      PdfColor titleColor, pw.Font ttf, pw.Font ttfBold) {
    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style:
                  pw.TextStyle(font: ttfBold, fontSize: 9, color: titleColor)),
          pw.SizedBox(height: 2),
          pw.Text(topic,
              style: pw.TextStyle(
                  font: ttfBold,
                  fontSize: 12,
                  color: PdfColor.fromHex('#111111'))),
          pw.Text(desc,
              style: pw.TextStyle(
                  font: ttf, fontSize: 11, color: PdfColor.fromHex('#888888'))),
        ]);
  }
}
