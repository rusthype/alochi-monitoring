// lib/features/local_test/local_result_screen.dart
// Offline natija — mavzular bo'yicha + Telegram ga yuborish + PDF
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../shared/theme/app_theme.dart';
import 'local_data.dart';
import 'local_grade_screen.dart';
import '../../core/db/offline_queue.dart';
import '../../core/db/history_db.dart';
import '../../core/services/pdf_service.dart';
import 'package:printing/printing.dart';
const _botToken = '8777359165:AAGr313YLnqCBf_nJ5j6_ytsxjJj36x5jEw';
// Superadmin Telegram ID lar (CLAUDE.md dan):
//   Elbek @m4e7tro = 433778264
//   S7 @Maxsoldier_hype = 8418578752
//   . @ggg_oo10 = 5345196664
const _adminIds = <int, String>{
  433778264: 'Elbek',
  8418578752: 'S7',
  5345196664: 'Admin',
};

/// HTML maxsus belgilarini Telegram parse_mode=HTML uchun escape qiladi.
String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

class LocalResultScreen extends StatefulWidget {
  final String firstName, lastName, group;
  final int grade, variant;
  final List<LocalQuestion> questions;
  final Map<int, String> answers;
  final int mathOk, engOk, pct;
  final Map<String, ({int ok, int tot})> topicScores;

  const LocalResultScreen(
      {super.key,
      required this.firstName,
      required this.lastName,
      required this.group,
      required this.grade,
      required this.variant,
      required this.questions,
      required this.answers,
      required this.mathOk,
      required this.engOk,
      required this.pct,
      required this.topicScores});

  @override
  State<LocalResultScreen> createState() => _LocalResultScreenState();
}

class _LocalResultScreenState extends State<LocalResultScreen>
    with TickerProviderStateMixin {
  late final AnimationController _scoreAnim;
  late final Animation<double> _scoreVal;
  String _tgStatus = '📤 Yuborilmoqda...';
  bool _tgSent = false;
  // Har bir admin uchun: null = yuborildi, String = xato sababi
  final Map<int, String?> _tgPerAdmin = {};
  bool _tgExpanded = false;

  @override
  void initState() {
    super.initState();
    _scoreAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _scoreVal = Tween<double>(begin: 0, end: widget.pct / 100)
        .animate(CurvedAnimation(parent: _scoreAnim, curve: Curves.easeOut));
    _scoreAnim.forward();

    // Yig'ilib qolgan eski oflayn xabarlarni jo'natish (eski queue helper)
    OfflineQueue.flushTg(_botToken, _adminIds.keys.toList());
    _sendTelegram();
  }

  @override
  void dispose() {
    _scoreAnim.dispose();
    super.dispose();
  }

  int get _total => widget.questions.length;
  int get _mathTotal => widget.questions.where((q) => q.isMath).length;
  int get _engTotal => _total - _mathTotal;
  int get _totalOk => widget.mathOk + widget.engOk;

  List<MapEntry<String, ({int ok, int tot})>> get _mathTopics => widget.topicScores.entries
      .where((e) => widget.questions.any((q) => q.isMath && q.topic == e.key))
      .toList();

  List<MapEntry<String, ({int ok, int tot})>> get _engTopics => widget.topicScores.entries
      .where((e) => widget.questions.any((q) => !q.isMath && q.topic == e.key))
      .toList();

  Future<void> _sendTelegram() async {
    try {
      await HistoryDb.insertResult(
        firstName: widget.firstName,
        lastName: widget.lastName,
        school: "Maktab",
        gradeGroup: '${widget.grade}-sinf ${widget.group}',
        mathScore: widget.mathOk,
        engScore: widget.engOk,
        totalPct: widget.pct.toDouble(),
      );
    } catch (e) {
      debugPrint("Tarixga yozishda xato: $e");
    }

    // 1) Token tirikligini /getMe orqali tekshirish
    try {
      final ping = await http
          .get(Uri.parse('https://api.telegram.org/bot$_botToken/getMe'))
          .timeout(const Duration(seconds: 6));
      if (ping.statusCode == 401) {
        if (mounted) {
          setState(() => _tgStatus = '🔑 Bot token bekor qilingan (401)');
        }
        return;
      }
      if (ping.statusCode != 200) {
        if (mounted) {
          setState(
              () => _tgStatus = '⚠️ Telegram javob bermayapti (${ping.statusCode})');
        }
        return;
      }
    } on Exception catch (e) {
      // Tarmoq yo'q — xabarni oflayn navbatga qo'shamiz
      final msg = _buildMessage();
      await OfflineQueue.enqueueTg(msg);
      if (mounted) {
        setState(() =>
            _tgStatus = "📵 Internet yo'q — xabar oflayn saqlandi (${e.runtimeType})");
      }
      return;
    }

    // 2) Xabarni yasash (HTML escape bilan)
    final msg = _buildMessage();

    // 3) Har bir adminga alohida yuborib, javobni saqlash
    int okCount = 0;
    for (final entry in _adminIds.entries) {
      final id = entry.key;
      try {
        final r = await http
            .post(
              Uri.parse('https://api.telegram.org/bot$_botToken/sendMessage'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(
                  {'chat_id': id, 'text': msg, 'parse_mode': 'HTML'}),
            )
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          _tgPerAdmin[id] = null; // muvaffaqiyat
          okCount++;
        } else {
          _tgPerAdmin[id] = _tgErrorReason(r.statusCode, r.body);
          debugPrint('TG ERROR for $id: ${r.statusCode} ${r.body}');
        }
      } on Exception catch (e) {
        _tgPerAdmin[id] = 'Tarmoq xatosi: ${e.runtimeType}';
      }
    }

    // 4) Umumiy status
    if (!mounted) return;
    if (okCount == _adminIds.length) {
      setState(() {
        _tgStatus = '✅ Telegram: ${_adminIds.length}/${_adminIds.length} admin oldi';
        _tgSent = true;
      });
    } else if (okCount > 0) {
      setState(() {
        _tgStatus = '⚠️ Telegram: $okCount/${_adminIds.length} admin oldi';
        _tgSent = true;
      });
    } else {
      // Hech kim olmadi — oflayn navbatga
      await OfflineQueue.enqueueTg(msg);
      setState(() => _tgStatus =
          '📵 Hech bir admin xabar olmadi — oflayn navbatga qo\'shildi');
    }
  }

  String _buildMessage() {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final mPct = _mathTotal > 0 ? widget.mathOk * 100 ~/ _mathTotal : 0;
    final ePct = _engTotal > 0 ? widget.engOk * 100 ~/ _engTotal : 0;

    final name = _escapeHtml('${widget.lastName} ${widget.firstName}');
    final groupStr = widget.group.isNotEmpty ? _escapeHtml(widget.group) : '—';

    var msg = '📊 <b>$name</b>'
        ' | ${widget.grade}-sinf V${widget.variant} | ✅ ${widget.pct}%'
        '\n📚 $groupStr · $dateStr'
        '\n━━━━━━━━━━━━━━━━━━━━'
        '\n📐 Matematika: <b>${widget.mathOk}/$_mathTotal ($mPct%)</b>';

    for (final e in _mathTopics) {
      final p = e.value.tot > 0 ? e.value.ok * 100 ~/ e.value.tot : 0;
      final ico = p >= 80
          ? '✅'
          : p >= 50
              ? '🟡'
              : '🔴';
      msg +=
          '\n  └ $ico ${_escapeHtml(e.key)}: <b>${e.value.ok}/${e.value.tot} ($p%)</b>';
    }

    msg += '\n🔤 Ingliz tili: <b>${widget.engOk}/$_engTotal ($ePct%)</b>';

    for (final e in _engTopics) {
      final p = e.value.tot > 0 ? e.value.ok * 100 ~/ e.value.tot : 0;
      final ico = p >= 80
          ? '✅'
          : p >= 50
              ? '🟡'
              : '🔴';
      msg +=
          '\n  └ $ico ${_escapeHtml(e.key)}: <b>${e.value.ok}/${e.value.tot} ($p%)</b>';
    }
    final weak = widget.topicScores.entries
        .where((e) => e.value.tot > 0 && e.value.ok * 100 ~/ e.value.tot < 50)
        .map((e) => _escapeHtml(e.key))
        .toList();
    if (weak.isNotEmpty) msg += '\n\n⚠️ Zaif: ${weak.join(', ')}';
    if (msg.length > 3500) msg = '${msg.substring(0, 3500)}...';
    return msg;
  }

  /// Telegram API javobidan inson tushunadigan xato sababi.
  String _tgErrorReason(int statusCode, String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final desc = (j['description'] as String?) ?? '';
      if (statusCode == 403) {
        if (desc.contains('blocked')) return 'Adminbotni bloklab qo\'ygan';
        if (desc.contains("haven't") || desc.contains('initiated')) {
          return "Admin botga /start bosmagan";
        }
        return 'Ruxsat yo\'q (403)';
      }
      if (statusCode == 400) return 'Xato so\'rov: $desc';
      if (statusCode == 401) return 'Bot token bekor';
      return '$statusCode: $desc';
    } catch (_) {
      return 'HTTP $statusCode';
    }
  }

  @override
  Widget build(BuildContext context) {
    final passed = widget.pct >= 60;
    final mainClr = passed ? AppColors.ok : AppColors.err;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: passed
                          ? [const Color(0xFF10B981), const Color(0xFF059669)]
                          : [const Color(0xFFEF4444), const Color(0xFFDC2626)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: mainClr.withValues(alpha: .3),
                        blurRadius: 20,
                        offset: const Offset(0, 8))
                  ]),
              child: Column(children: [
                // Icon
                Icon(
                    widget.pct >= 80
                        ? Icons.celebration_rounded
                        : widget.pct >= 60
                            ? Icons.emoji_events_rounded
                            : Icons.fitness_center_rounded,
                    size: 52,
                    color: Colors.white),
                const SizedBox(height: 8),
                Text(
                    widget.pct >= 80
                        ? 'Barakalla!'
                        : widget.pct >= 60
                            ? 'Yaxshi!'
                            : 'Harakat qiling!',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text('${widget.lastName} ${widget.firstName}',
                    style:
                        const TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 20),
                // Score ring
                AnimatedBuilder(
                    animation: _scoreVal,
                    builder: (_, __) {
                      final pct = (_scoreVal.value * 100).round();
                      return Stack(alignment: Alignment.center, children: [
                        SizedBox(
                            width: 100,
                            height: 100,
                            child: CircularProgressIndicator(
                                value: _scoreVal.value,
                                strokeWidth: 8,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation(
                                    Colors.white))),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('$pct%',
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white)),
                          Text('$_totalOk/$_total',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white70)),
                        ]),
                      ]);
                    }),
              ]),
            ),
            const SizedBox(height: 16),
            // Scores row
            Row(children: [
              Expanded(
                  child: _ScoreCard(
                      'Matematika', widget.mathOk, _mathTotal, AppColors.math)),
              const SizedBox(width: 10),
              Expanded(
                  child: _ScoreCard(
                      'Ingliz tili', widget.engOk, _engTotal, AppColors.eng)),
            ]),
            const SizedBox(height: 16),
            // Topics
            if (widget.topicScores.isNotEmpty) ...[
              _TopicsCard(
                  title: 'Matematika',
                  icon: Icons.calculate_rounded,
                  color: AppColors.math,
                  isMath: true,
                  topics: widget.topicScores,
                  questions: widget.questions),
              const SizedBox(height: 10),
              _TopicsCard(
                  title: 'Ingliz tili',
                  icon: Icons.language_rounded,
                  color: AppColors.eng,
                  isMath: false,
                  topics: widget.topicScores,
                  questions: widget.questions),
              const SizedBox(height: 16),
            ],
            // Telegram status
            _buildTelegramStatus(),
            const SizedBox(height: 16),
            // PDF Actions
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final pdfBytes = await PdfService.generateResultPdf(
                      firstName: widget.firstName, lastName: widget.lastName, group: widget.group, grade: widget.grade, variant: widget.variant, mathOk: widget.mathOk, mathTotal: _mathTotal, engOk: widget.engOk, engTotal: _engTotal, pct: widget.pct, mathTopics: _mathTopics, engTopics: _engTopics,
                    );
                    await Printing.layoutPdf(onLayout: (_) => pdfBytes, name: '${widget.lastName}_${widget.firstName}_Natija.pdf');
                  },
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Chop etish'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink1, side: const BorderSide(color: AppColors.border), padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final pdfBytes = await PdfService.generateResultPdf(
                      firstName: widget.firstName, lastName: widget.lastName, group: widget.group, grade: widget.grade, variant: widget.variant, mathOk: widget.mathOk, mathTotal: _mathTotal, engOk: widget.engOk, engTotal: _engTotal, pct: widget.pct, mathTopics: _mathTopics, engTopics: _engTopics,
                    );
                    await Printing.sharePdf(bytes: pdfBytes, filename: '${widget.lastName}_${widget.firstName}_Natija.pdf');
                  },
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('PDF Saqlash'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.brand, side: const BorderSide(color: AppColors.brand), padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            // Next student button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LocalGradeScreen()),
                    (_) => false),
                icon: const Icon(Icons.person_add_rounded),
                label: const Text("Keyingi o'quvchi",
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              icon: const Icon(Icons.home_rounded, size: 16),
              label: const Text('Bosh sahifa'),
              style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
            ),
          ]),
        ),
      ))),
    );
  }

  Widget _buildTelegramStatus() {
    final hasFailures = _tgPerAdmin.values.any((v) => v != null);
    final hasResults = _tgPerAdmin.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _tgSent ? const Color(0xFFF0FDF4) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color:
                  _tgSent ? const Color(0xFF86EFAC) : AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_tgSent ? Icons.check_circle_rounded : Icons.send_rounded,
                color: _tgSent ? AppColors.ok : AppColors.brand, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(_tgStatus,
                    style: TextStyle(
                        fontSize: 13,
                        color: _tgSent ? AppColors.ok : AppColors.ink2,
                        fontWeight: FontWeight.w600))),
            if (hasResults)
              IconButton(
                onPressed: () => setState(() => _tgExpanded = !_tgExpanded),
                icon: Icon(
                    _tgExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.ink3,
                    size: 20),
                tooltip: 'Tafsilot',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ]),
          if (_tgExpanded && hasResults) ...[
            const Divider(height: 18, color: AppColors.border),
            ..._adminIds.entries.map((entry) {
              final id = entry.key;
              final name = entry.value;
              final err = _tgPerAdmin[id];
              final ok = err == null && _tgPerAdmin.containsKey(id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Icon(
                      ok
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      size: 14,
                      color: ok ? AppColors.ok : AppColors.err),
                  const SizedBox(width: 8),
                  Text('$name ',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink1)),
                  Text('(ID: $id)',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.ink3,
                          fontFamily: 'JetBrainsMono')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(ok ? 'yetkazildi' : (err ?? '—'),
                          style: TextStyle(
                              fontSize: 11,
                              color: ok ? AppColors.ok : AppColors.err))),
                ]),
              );
            }),
            if (hasFailures) ...[
              const SizedBox(height: 6),
              const Text(
                  "Tavsiya: yetib bormagan admin @alochipoll_bot ga /start bossin.",
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.ink3,
                      fontStyle: FontStyle.italic)),
            ],
          ],
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final String title;
  final int ok, total;
  final Color color;
  const _ScoreCard(this.title, this.ok, this.total, this.color);
  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? ok * 100 ~/ total : 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .03),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.ink3,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$ok',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1)),
          const SizedBox(width: 4),
          Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('/ $total',
                  style: const TextStyle(fontSize: 13, color: AppColors.ink3))),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(
                height: 6,
                width: double.infinity,
                color: color.withValues(alpha: .1)),
            FractionallySizedBox(
                widthFactor: pct / 100,
                child: Container(height: 6, color: color)),
          ]),
        ),
        const SizedBox(height: 4),
        Text('$pct%',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

class _TopicsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool isMath;
  final Map<String, ({int ok, int tot})> topics;
  final List<LocalQuestion> questions;
  const _TopicsCard(
      {required this.title,
      required this.icon,
      required this.color,
      required this.isMath,
      required this.topics,
      required this.questions});
  @override
  Widget build(BuildContext context) {
    final relevant = topics.entries
        .where(
            (e) => questions.any((q) => q.isMath == isMath && q.topic == e.key))
        .toList();
    if (relevant.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 12),
        ...relevant.map((e) {
          final p = e.value.tot > 0 ? e.value.ok / e.value.tot : 0.0;
          final barClr = p >= 0.8
              ? AppColors.ok
              : p >= 0.5
                  ? const Color(0xFFF59E0B)
                  : AppColors.err;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(e.key,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.ink1,
                            fontWeight: FontWeight.w500))),
                Text('${e.value.ok}/${e.value.tot}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: barClr)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(children: [
                  Container(
                      height: 5,
                      width: double.infinity,
                      color: barClr.withValues(alpha: .12)),
                  FractionallySizedBox(
                      widthFactor: p,
                      child: Container(height: 5, color: barClr)),
                ]),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}
