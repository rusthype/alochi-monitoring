/// Generates one self-contained, print-ready HTML "passport" per diagnostic
/// history record for the offline ZIP-export feature. Deliberately
/// independent from `HtmlService.generateResultHtml` (used by the
/// unrelated monitoring test flow, which has real per-topic data this
/// diagnostic-kiosk flow never captures — see plan Context).
///
/// Every record here has a math_score/english_score pair that is either
/// BOTH present (raw correct-count out of `kDiagnosticSubjectMax`, once the
/// backend has scored the attempt) or BOTH null (the attempt is still
/// sitting in the local offline queue, never reached the server — the
/// PRIMARY reason this export feature exists). No per-topic/per-question
/// data exists anywhere in this flow, so no topic-breakdown section is
/// generated — fabricating one would be dishonest.
library;

/// Flat max question count per fixed-variant diagnostic subject (both
/// math and english) — backend `apps/diagnostic/fixed_variant.py`'s
/// `QUESTIONS_PER_VARIANT = 30`, confirmed by
/// `tests_fixed_variant.py::test_fixed_variant_attempt_reports_flat_30_max_for_both_subjects`
/// (`max_math=30, max_english=30`).
const int kDiagnosticSubjectMax = 30;

class DiagnosticExportService {
  DiagnosticExportService._();

  static String generateStudentPassportHtml(Map<String, dynamic> record) {
    final studentName = (record['student_name'] ?? '').toString();
    final classLabel = (record['class_label'] ?? '').toString();
    final school = (record['school'] ?? '').toString();
    final dateStr = _formatDate(record['date_taken'] as int?);
    final mathScore = record['math_score'] as int?;
    final englishScore = record['english_score'] as int?;

    if (mathScore == null && englishScore == null) {
      return _pendingHtml(
        studentName: studentName,
        classLabel: classLabel,
        school: school,
        dateStr: dateStr,
      );
    }
    return _sentHtml(
      studentName: studentName,
      classLabel: classLabel,
      school: school,
      dateStr: dateStr,
      mathScore: mathScore ?? 0,
      englishScore: englishScore ?? 0,
    );
  }

  static String _formatDate(int? epochMs) {
    if (epochMs == null) return '-';
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
  }

  static const _headStyle = '''
<style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:'Plus Jakarta Sans',sans-serif;background:#fff;color:#111;font-size:13px;line-height:1.5;padding:24px}@media print{@page{margin:12mm 14mm}body{padding:0}}</style>''';

  static const _fontLink =
      "<link href='https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap' rel='stylesheet'>";

  static String _pendingHtml({
    required String studentName,
    required String classLabel,
    required String school,
    required String dateStr,
  }) {
    return '''
<!DOCTYPE html><html lang='uz'><head><meta charset='UTF-8'><title>A'lochi — $studentName</title>
$_fontLink
$_headStyle
</head><body><div style='max-width:640px;margin:0 auto'>
  <div style='display:flex;align-items:center;justify-content:space-between;border-bottom:2.5px solid #111;padding-bottom:10px;margin-bottom:16px'>
    <div style='font-size:11px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:#555'>A'lochi — Diagnostik Pasport</div>
    <div style='font-size:10px;color:#888'>$dateStr</div>
  </div>
  <div style='display:flex;align-items:center;gap:18px;background:#f7f7f7;border-radius:12px;padding:16px 20px;margin-bottom:16px'>
    <div style='width:54px;height:54px;border-radius:50%;background:#111;color:#fff;display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:900;flex-shrink:0'>${_initial(studentName)}</div>
    <div style='flex:1'>
      <div style='font-size:20px;font-weight:800;margin-bottom:5px'>$studentName</div>
      <div style='display:flex;gap:16px;font-size:12px;color:#555'><span>$classLabel</span><span>$school</span></div>
    </div>
  </div>
  <div style='background:#FEF2F2;border:1.5px solid #DC2626;border-radius:12px;padding:18px 20px'>
    <div style='font-size:13px;font-weight:800;color:#DC2626;margin-bottom:6px'>Natija hali serverga yuborilmagan</div>
    <div style='font-size:12px;color:#7f1d1d;line-height:1.7'>Bu urinish test topshirilgan payt internet aloqasi yo'q edi. Qurilma internetga ulanishi bilan natija avtomatik serverga yuboriladi va rasmiy ball bilan qayta shakllantiriladi.</div>
  </div>
  <div style='border-top:1px solid #eee;padding-top:8px;margin-top:18px;display:flex;justify-content:space-between;font-size:10px;color:#bbb'>
    <span>A'lochi Ta'lim · alochi.org</span>
    <span>$school · $classLabel · $dateStr</span>
  </div>
</div></body></html>
''';
  }

  static String _sentHtml({
    required String studentName,
    required String classLabel,
    required String school,
    required String dateStr,
    required int mathScore,
    required int englishScore,
  }) {
    final mathPct = (mathScore * 100 / kDiagnosticSubjectMax).round();
    final engPct = (englishScore * 100 / kDiagnosticSubjectMax).round();
    final totalOk = mathScore + englishScore;
    final totalMax = kDiagnosticSubjectMax * 2;
    final totalErr = totalMax - totalOk;
    final pct = (totalOk * 100 / totalMax).round();

    String verdict;
    String verdictColor;
    if (pct >= 80) {
      verdict = "A'lo";
      verdictColor = '#10B981';
    } else if (pct >= 60) {
      verdict = 'Yaxshi';
      verdictColor = '#F97316';
    } else {
      verdict = 'Qayta mashq kerak';
      verdictColor = '#EF4444';
    }

    String subjColor(int p) => p >= 60 ? '#10B981' : '#EF4444';

    final String summary;
    if (pct >= 80) {
      summary =
          "$studentName juda yaxshi natija ko'rsatdi ($pct%). Shu darajani saqlab qolish uchun muntazam mashq qilishni davom ettiring.";
    } else if (pct >= 60) {
      summary =
          "$studentName yaxshi natija ko'rsatdi ($pct%). Ba'zi mavzularni takrorlash orqali natijani yanada oshirish mumkin.";
    } else {
      summary =
          "$studentName $pct% natija ko'rsatdi. Qo'shimcha mashq va muntazam takrorlash tavsiya etiladi.";
    }

    // The only real per-subject signal available (no per-topic data exists
    // for this flow — see plan Context) is which of the two subjects
    // scored lower; the weaker one gets more days in the generic plan.
    final mathIsWeaker = mathPct <= engPct;
    final firstFocus =
        mathIsWeaker ? 'Matematika mashqlari' : 'Ingliz tili mashqlari';
    final secondFocus =
        mathIsWeaker ? 'Ingliz tili mashqlari' : 'Matematika mashqlari';

    return '''
<!DOCTYPE html><html lang='uz'><head><meta charset='UTF-8'><title>A'lochi — $studentName</title>
$_fontLink
$_headStyle
</head><body><div style='max-width:720px;margin:0 auto'>
  <div style='display:flex;align-items:center;justify-content:space-between;border-bottom:2.5px solid #111;padding-bottom:10px;margin-bottom:16px'>
    <div style='font-size:11px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:#555'>A'lochi — Diagnostik Pasport</div>
    <div style='font-size:10px;color:#888'>$dateStr</div>
  </div>
  <div style='display:flex;align-items:center;gap:18px;background:#f7f7f7;border-radius:12px;padding:16px 20px;margin-bottom:16px'>
    <div style='width:54px;height:54px;border-radius:50%;background:#111;color:#fff;display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:900;flex-shrink:0'>${_initial(studentName)}</div>
    <div style='flex:1'>
      <div style='font-size:20px;font-weight:800;margin-bottom:5px'>$studentName</div>
      <div style='display:flex;gap:16px;font-size:12px;color:#555'><span>$classLabel</span><span>$school</span></div>
    </div>
    <div style='background:#111;color:#fff;border-radius:12px;padding:14px 22px;text-align:center'>
      <div style='font-size:32px;font-weight:900;line-height:1;margin-bottom:3px;color:$verdictColor'>$pct%</div>
      <div style='font-size:10px;opacity:.6;text-transform:uppercase'>$verdict</div>
    </div>
  </div>
  <div style='display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:16px'>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#10B981'>$totalOk</div><div style='font-size:11px;color:#888;margin-top:2px'>To'g'ri javob</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#EF4444'>$totalErr</div><div style='font-size:11px;color:#888;margin-top:2px'>Xato javob</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#F97316'>$totalMax</div><div style='font-size:11px;color:#888;margin-top:2px'>Jami savol</div></div>
  </div>
  <div style='display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:16px'>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#111'>$mathScore/$kDiagnosticSubjectMax</div><div style='font-size:11px;color:#888;margin-top:2px'>Matematika</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#111'>$englishScore/$kDiagnosticSubjectMax</div><div style='font-size:11px;color:#888;margin-top:2px'>Ingliz tili</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:${subjColor(mathPct)}'>$mathPct%</div><div style='font-size:11px;color:#888;margin-top:2px'>Math %</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:${subjColor(engPct)}'>$engPct%</div><div style='font-size:11px;color:#888;margin-top:2px'>English %</div></div>
  </div>
  <div style='display:grid;grid-template-columns:1fr 1fr;gap:14px'>
    <div>
      <div style='font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.8px;color:#888;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px'>14 Kunlik reja</div>
      <div style='padding-left:14px;border-left:2.5px solid #eee'>
        <div style='margin-bottom:10px'><div style='font-size:9px;font-weight:700;color:#F97316;text-transform:uppercase'>1–4 KUN</div><div style='font-size:12px;font-weight:700;margin-top:2px'>$firstFocus</div><div style='font-size:11px;color:#888'>Har kuni 15–20 daqiqa mashq</div></div>
        <div style='margin-bottom:10px'><div style='font-size:9px;font-weight:700;color:#2563EB;text-transform:uppercase'>5–7 KUN</div><div style='font-size:12px;font-weight:700;margin-top:2px'>$secondFocus</div><div style='font-size:11px;color:#888'>Har kuni 15–20 daqiqa mashq</div></div>
        <div style='margin-bottom:10px'><div style='font-size:9px;font-weight:700;color:#10B981;text-transform:uppercase'>8–11 KUN</div><div style='font-size:12px;font-weight:700;margin-top:2px'>Aralash mashqlar</div><div style='font-size:11px;color:#888'>Ikkala fanni birga takrorlash</div></div>
        <div><div style='font-size:9px;font-weight:700;color:#888;text-transform:uppercase'>12–14 KUN</div><div style='font-size:12px;font-weight:700;margin-top:2px'>Nazorat testi</div><div style='font-size:11px;color:#888'>Natijalarni solishtirish</div></div>
      </div>
    </div>
    <div>
      <div style='font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.8px;color:#888;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px'>AI xulosa</div>
      <div style='background:#111;color:#fff;border-radius:10px;padding:13px 15px;margin-bottom:12px'>
        <div style='font-size:9px;opacity:.4;text-transform:uppercase;letter-spacing:.6px;margin-bottom:6px'>A'lochi AI</div>
        <div style='font-size:12px;line-height:1.75;opacity:.88'>$summary</div>
      </div>
      <div style='background:#f7f7f7;border-radius:10px;padding:12px 14px'>
        <div style='font-size:11px;font-weight:700;margin-bottom:5px'>Ota-onaga</div>
        <div style='font-size:11px;color:#444;line-height:1.8'>• Har kuni 20–30 daqiqa o'qish vaqti<br>• Zaif fanni birgalikda takrorlang<br>• Rag'batlantiring va sabr bilan o'rgating</div>
      </div>
    </div>
  </div>
  <div style='border-top:1px solid #eee;padding-top:8px;margin-top:18px;display:flex;justify-content:space-between;font-size:10px;color:#bbb'>
    <span>A'lochi Ta'lim · alochi.org</span>
    <span>$school · $classLabel · $dateStr</span>
  </div>
</div></body></html>
''';
  }
}
