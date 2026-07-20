
class HtmlService {
  static String generateResultHtml({
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
  }) {
    final dateStr = "${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}";
    final totalOk = mathOk + engOk;
    final totalQ = mathTotal + engTotal;
    final totalErr = totalQ - totalOk;
    final initial = firstName.isNotEmpty ? firstName[0].toLowerCase() : '';

    String statusText = pct < 60 ? "Qo'shimcha mashq kerak" : "Yaxshi natija";
    String pctColor = pct < 60 ? "#EF4444" : "#10B981";

    final mathPct = mathTotal > 0 ? (mathOk * 100 ~/ mathTotal) : 0;
    final engPct = engTotal > 0 ? (engOk * 100 ~/ engTotal) : 0;
    final mathPctColor = mathPct < 60 ? "#EF4444" : "#10B981";
    final engPctColor = engPct < 60 ? "#EF4444" : "#10B981";
    final subjectRow = (mathTotal == 0 && engTotal == 0) ? '' : '''
  <div style='display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:16px'>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#111'>$mathOk/$mathTotal</div><div style='font-size:11px;color:#888;margin-top:2px'>Matematika</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#111'>$engOk/$engTotal</div><div style='font-size:11px;color:#888;margin-top:2px'>Ingliz tili</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:$mathPctColor'>$mathPct%</div><div style='font-size:11px;color:#888;margin-top:2px'>Math %</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:$engPctColor'>$engPct%</div><div style='font-size:11px;color:#888;margin-top:2px'>English %</div></div>
  </div>
''';

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
    final finalSummary = summaryStr.isNotEmpty ? summaryStr : "$firstName $pct% natija ko'rsatdi. O'zlashtirish darajasiga qarab 14 kunlik reja bilan ishlash tavsiya etiladi.";

    String buildTopics(List<MapEntry<String, ({int ok, int tot})>> topics, String title) {
      if (topics.isEmpty) return '';
      
      String rows = '';
      for (var e in topics) {
        final pctVal = e.value.tot > 0 ? (e.value.ok * 100 ~/ e.value.tot) : 0;
        final isGood = pctVal >= 60;
        final color = isGood ? "#10B981" : "#EF4444";
        final bgColor = isGood ? "#10B98122" : "#EF444422";
        final badgeText = isGood ? "Yaxshi o'zlashtirilgan" : "Qayta o'rganish";

        rows += '''
<tr>
  <td style='padding:7px 4px;font-size:13px;border-bottom:1px solid #f3f3f3'>${e.key}</td>
  <td style='padding:7px 4px;width:130px;border-bottom:1px solid #f3f3f3'>
    <div style='background:#eee;border-radius:20px;height:7px;overflow:hidden'>
      <div style='width:$pctVal%;height:100%;background:$color;border-radius:20px'></div>
    </div>
  </td>
  <td style='padding:7px 4px;font-size:12px;font-weight:700;color:$color;text-align:right;border-bottom:1px solid #f3f3f3'>${e.value.ok}/${e.value.tot} — $pctVal%</td>
  <td style='padding:7px 4px;text-align:right;border-bottom:1px solid #f3f3f3'>
    <span style='background:$bgColor;color:$color;padding:2px 9px;border-radius:20px;font-size:10px;font-weight:700'>$badgeText</span>
  </td>
</tr>
''';
      }

      return '''
<div style='font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.8px;color:#888;margin-bottom:8px;border-bottom:1px solid #eee;padding-bottom:5px'>$title</div>
<table style='width:100%;border-collapse:collapse;margin-bottom:18px'>
$rows
</table>
''';
    }

    String getTopicName(int index) {
      if (combinedTopics.isEmpty) return "Zaif mavzu";
      final sorted = List<MapEntry<String, ({int ok, int tot})>>.from(combinedTopics)
        ..sort((a, b) {
          final pa = a.value.tot > 0 ? a.value.ok / a.value.tot : 0.0;
          final pb = b.value.tot > 0 ? b.value.ok / b.value.tot : 0.0;
          return pa.compareTo(pb);
        });
      if (index < sorted.length) return sorted[index].key;
      return sorted.last.key;
    }

    return '''
<!DOCTYPE html><html lang='uz'><head><meta charset='UTF-8'><title>Pasport</title><link href='https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap' rel='stylesheet'><style>*{box-sizing:border-box;margin:0;padding:0}body{font-family:Inter,sans-serif;background:#fff;color:#111;font-size:13px;line-height:1.5;padding:24px}@media print{@page{margin:12mm 14mm}body{padding:0}}</style></head><body><div style='max-width:760px;margin:0 auto'>
  <div style='display:flex;align-items:center;justify-content:space-between;border-bottom:2.5px solid #111;padding-bottom:10px;margin-bottom:16px'>
    <div style='font-size:11px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:#555'>A'lochi — Diagnostik Pasport</div>
    <div style='font-size:10px;color:#888'>$dateStr · Variant $variant</div>
  </div>
  <div style='display:flex;align-items:center;gap:18px;background:#f7f7f7;border-radius:12px;padding:16px 20px;margin-bottom:16px'>
    <div style='width:54px;height:54px;border-radius:50%;background:#111;color:#fff;display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:900;flex-shrink:0'>$initial</div>
    <div style='flex:1'>
      <div style='font-size:20px;font-weight:800;margin-bottom:5px'>$firstName $lastName</div>
      <div style='display:flex;gap:16px;font-size:12px;color:#555'><span>$grade-sinf</span><span>$group</span><span>Variant $variant</span></div>
    </div>
    <div style='background:#111;color:#fff;border-radius:12px;padding:14px 22px;text-align:center'>
      <div style='font-size:32px;font-weight:900;line-height:1;margin-bottom:3px;color:$pctColor'>$pct%</div>
      <div style='font-size:10px;opacity:.6;text-transform:uppercase'>$statusText</div>
    </div>
  </div>
  <div style='display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:16px'>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#10B981'>$totalOk</div><div style='font-size:11px;color:#888;margin-top:2px'>To'g'ri javob</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#EF4444'>$totalErr</div><div style='font-size:11px;color:#888;margin-top:2px'>Xato javob</div></div>
    <div style='border:1.5px solid #eee;border-radius:10px;padding:12px;text-align:center'><div style='font-size:26px;font-weight:900;color:#FF8A00'>$totalQ</div><div style='font-size:11px;color:#888;margin-top:2px'>Jami savol</div></div>
  </div>
  $subjectRow
  ${buildTopics(combinedTopics, "Mavzu bo'yicha tahlil")}
  ${buildTopics(unitScores, "Unit bo'yicha tahlil")}

  <div style='display:grid;grid-template-columns:1fr 1fr;gap:14px'>
    <div>
      <div style='font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.8px;color:#888;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px'>14 Kunlik reja</div>
      <div style='padding-left:14px;border-left:2.5px solid #eee'>
        <div style='margin-bottom:10px'><div style='font-size:9px;font-weight:700;color:#FF8A00;text-transform:uppercase'>1–3 KUN</div><div style='font-size:12px;font-weight:700;margin-top:2px'>${getTopicName(0)}</div><div style='font-size:11px;color:#888'>Har kuni 15 daqiqa mashq</div></div>
        <div style='margin-bottom:10px'><div style='font-size:9px;font-weight:700;color:#2563EB;text-transform:uppercase'>4–7 KUN</div><div style='font-size:12px;font-weight:700;margin-top:2px'>${getTopicName(1)}</div><div style='font-size:11px;color:#888'>Har kuni 5 ta misol yechish</div></div>
        <div style='margin-bottom:10px'><div style='font-size:9px;font-weight:700;color:#10B981;text-transform:uppercase'>8–11 KUN</div><div style='font-size:12px;font-weight:700;margin-top:2px'>Aralash mashqlar</div><div style='font-size:11px;color:#888'>Barcha mavzularni takrorlash</div></div>
        <div><div style='font-size:9px;font-weight:700;color:#888;text-transform:uppercase'>12–14 KUN</div><div style='font-size:12px;font-weight:700;margin-top:2px'>Nazorat testi</div><div style='font-size:11px;color:#888'>Natijalarni solishtirish</div></div>
      </div>
    </div>
    <div>
      <div style='font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.8px;color:#888;margin-bottom:10px;border-bottom:1px solid #eee;padding-bottom:5px'>AI xulosa</div>
      <div style='background:#111;color:#fff;border-radius:10px;padding:13px 15px;margin-bottom:12px'>
        <div style='font-size:9px;opacity:.4;text-transform:uppercase;letter-spacing:.6px;margin-bottom:6px'>A'lochi AI</div>
        <div style='font-size:12px;line-height:1.75;opacity:.88'>$finalSummary</div>
      </div>
      <div style='background:#f7f7f7;border-radius:10px;padding:12px 14px'>
        <div style='font-size:11px;font-weight:700;margin-bottom:5px'>Ota-onaga</div>
        <div style='font-size:11px;color:#444;line-height:1.8'>• Har kuni 20–30 daqiqa o'qish vaqti<br>• Zaif mavzularni birgalikda takrorlang<br>• Rag'batlantiring va sabr bilan o'rgating</div>
      </div>
    </div>
  </div>
  <div style='border-top:1px solid #eee;padding-top:8px;margin-top:18px;display:flex;justify-content:space-between;font-size:10px;color:#bbb'>
    <span>A'lochi Ta'lim · alochi.uz</span>
    <span>$group · $grade-sinf · $dateStr</span>
  </div>
</div>
</body></html>
''';
  }
}
