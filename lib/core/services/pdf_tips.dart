// lib/core/services/pdf_tips.dart
// Online va offline PDF lar uchun umumiy tavsiya matnlari (ARB: mathTip*/engTip*/status*).

import 'package:alochi_monitoring/l10n/app_localizations.dart';

class PdfTips {
  static List<String> mathTips(double pct, AppLocalizations l10n) {
    if (pct < 0.5) {
      return [l10n.mathTipLow1, l10n.mathTipLow2, l10n.mathTipLow3];
    }
    if (pct < 0.75) {
      return [l10n.mathTipMed1, l10n.mathTipMed2, l10n.mathTipMed3];
    }
    if (pct < 0.9) {
      return [l10n.mathTipHigh1, l10n.mathTipHigh2, l10n.mathTipHigh3];
    }
    return [l10n.mathTipExc1, l10n.mathTipExc2, l10n.mathTipExc3];
  }

  static List<String> englishTips(double pct, AppLocalizations l10n) {
    if (pct < 0.5) {
      return [l10n.engTipLow1, l10n.engTipLow2, l10n.engTipLow3];
    }
    if (pct < 0.75) {
      return [l10n.engTipMed1, l10n.engTipMed2, l10n.engTipMed3];
    }
    if (pct < 0.9) {
      return [l10n.engTipHigh1, l10n.engTipHigh2, l10n.engTipHigh3];
    }
    return [l10n.engTipExc1, l10n.engTipExc2, l10n.engTipExc3];
  }

  static String overallStatus(int totalPct, AppLocalizations l10n) {
    if (totalPct >= 90) return l10n.statusGold;
    if (totalPct >= 75) return l10n.statusGoodMsg;
    if (totalPct >= 60) return l10n.statusSatisfactory;
    return l10n.statusKeepTrying;
  }
}
