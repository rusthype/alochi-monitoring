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
const _adminIds = [8418578752, 5345196664, 433778264];

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

  @override
  void initState() {
    super.initState();
    _scoreAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _scoreVal = Tween<double>(begin: 0, end: widget.pct / 100)
        .animate(CurvedAnimation(parent: _scoreAnim, curve: Curves.easeOut));
    _scoreAnim.forward();
    
    // Yig'ilib qolgan eski oflayn xabarlarni jo'natish
    OfflineQueue.flushTg(_botToken, _adminIds);
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
        school: "Maktab", // Since school is not explicitly passed separately in this widget except inside group string. Wait, group might contain school.
        gradeGroup: '${widget.grade}-sinf ${widget.group}',
        mathScore: widget.mathOk,
        engScore: widget.engOk,
        totalPct: widget.pct.toDouble(),
      );
    } catch (e) {
      debugPrint("Tarixga yozishda xato: $e");
    }

    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final mPct = _mathTotal > 0 ? widget.mathOk * 100 ~/ _mathTotal : 0;
    final ePct = _engTotal > 0 ? widget.engOk * 100 ~/ _engTotal : 0;

    var msg = '📊 <b>${widget.lastName} ${widget.firstName}</b>'
        ' | ${widget.grade}-sinf V${widget.variant} | ✅ ${widget.pct}%'
        '\n📚 ${widget.group.isNotEmpty ? widget.group : "—"} · $dateStr'
        '\n━━━━━━━━━━━━━━━━━━━━'
        '\n📐 Matematika: <b>${widget.mathOk}/$_mathTotal ($mPct%)</b>';

    for (final e in _mathTopics) {
      final p = e.value.tot > 0 ? e.value.ok * 100 ~/ e.value.tot : 0;
      final ico = p >= 80 ? '✅' : p >= 50 ? '🟡' : '🔴';
      msg += '\n  └ $ico ${e.key}: <b>${e.value.ok}/${e.value.tot} ($p%)</b>';
    }

    msg += '\n🔤 Ingliz tili: <b>${widget.engOk}/$_engTotal ($ePct%)</b>';

    for (final e in _engTopics) {
      final p = e.value.tot > 0 ? e.value.ok * 100 ~/ e.value.tot : 0;
      final ico = p >= 80 ? '✅' : p >= 50 ? '🟡' : '🔴';
      msg += '\n  └ $ico ${e.key}: <b>${e.value.ok}/${e.value.tot} ($p%)</b>';
    }
    final weak = widget.topicScores.entries
        .where((e) => e.value.tot > 0 && e.value.ok * 100 ~/ e.value.tot < 50)
        .map((e) => e.key)
        .toList();
    if (weak.isNotEmpty) msg += '\n\n⚠️ Zaif: ${weak.join(', ')}';
    if (msg.length > 1020) msg = '${msg.substring(0, 1020)}...';

    bool sent = false;
    String lastError = '';
    
    for (final id in _adminIds) {
      try {
        final r = await http.post(
          Uri.parse('https://api.telegram.org/bot$_botToken/sendMessage'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'chat_id': id, 'text': msg, 'parse_mode': 'HTML'}),
        );
        if (r.statusCode == 200) {
          if (!sent) {
            sent = true;
            if (mounted) {
              setState(() {
                _tgStatus = '✅ Telegram ga yuborildi';
                _tgSent = true;
              });
            }
          }
        } else {
          lastError = 'Bot xatosi: ${r.statusCode}';
          debugPrint('TG ERROR: ${r.body}');
        }
      } catch (e) {
        lastError = 'Tarmoq xatosi';
      }
    }
    if (!sent) {
      await OfflineQueue.enqueueTg(msg);
      if (mounted) {
        setState(() => _tgStatus = lastError.contains('Bot') 
            ? '📵 Adminlar botni ishga tushirmagan' 
            : '📵 Internet yo\'q — xabar oflayn saqlandi');
      }
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
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _tgSent ? const Color(0xFFF0FDF4) : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _tgSent
                          ? const Color(0xFF86EFAC)
                          : AppColors.border)),
              child: Row(children: [
                Icon(_tgSent ? Icons.check_circle_rounded : Icons.send_rounded,
                    color: _tgSent ? AppColors.ok : AppColors.brand, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_tgStatus,
                        style: TextStyle(
                            fontSize: 13,
                            color: _tgSent ? AppColors.ok : AppColors.ink2,
                            fontWeight: FontWeight.w600))),
              ]),
            ),
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
