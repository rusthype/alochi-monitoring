// lib/features/local_test/local_result_screen.dart
// Offline natija — mavzular bo'yicha + Server /result/ endpointga yuborish + PDF
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import 'local_data.dart';
import '../../core/db/offline_queue.dart';
import '../../core/db/history_db.dart';
import '../../core/api/api_client.dart';
import '../../core/sync/sync_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/services/html_service.dart';
import 'package:printing/printing.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

class LocalResultScreen extends StatefulWidget {
  final String firstName, lastName, group, school;
  final int grade, variant;
  final List<LocalQuestion> questions;
  final Map<int, String> answers;
  final int mathOk, engOk, pct;
  final Map<String, ({int ok, int tot})> topicScores;
  final DateTime? testStartedAt;

  const LocalResultScreen(
      {super.key,
      required this.firstName,
      required this.lastName,
      required this.group,
      required this.school,
      required this.grade,
      required this.variant,
      required this.questions,
      required this.answers,
      required this.mathOk,
      required this.engOk,
      required this.pct,
      required this.topicScores,
      this.testStartedAt});

  @override
  State<LocalResultScreen> createState() => _LocalResultScreenState();
}

class _LocalResultScreenState extends State<LocalResultScreen>
    with TickerProviderStateMixin {
  late final AnimationController _scoreAnim;
  late final Animation<double> _scoreVal;
  String _sendStatus = '';
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _scoreAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _scoreVal = Tween<double>(begin: 0, end: widget.pct / 100)
        .animate(CurvedAnimation(parent: _scoreAnim, curve: Curves.easeOut));
    _scoreAnim.forward();

    _sendStatus = AppLocalizations.of(context)!.localResSending;
    _submitLocal();
  }

  @override
  void dispose() {
    SyncService.instance.flushNow();
    _scoreAnim.dispose();
    super.dispose();
  }

  int get _total => widget.questions.length;
  int get _mathTotal => widget.questions.where((q) => q.isMath).length;
  int get _engTotal => _total - _mathTotal;
  int get _totalOk => widget.mathOk + widget.engOk;

  List<MapEntry<String, ({int ok, int tot})>> get _mathTopics => widget
      .topicScores.entries
      .where((e) => widget.questions.any((q) => q.isMath && q.topic == e.key))
      .toList();

  List<MapEntry<String, ({int ok, int tot})>> get _engTopics => widget
      .topicScores.entries
      .where((e) => widget.questions.any((q) => !q.isMath && q.topic == e.key))
      .toList();

  Future<void> _submitLocal() async {
    try {
      await HistoryDb.insertResult(
        firstName: widget.firstName,
        lastName: widget.lastName,
        school: widget.school.isEmpty ? '—' : widget.school,
        gradeGroup: '${widget.grade}-sinf ${widget.group}',
        mathScore: widget.mathOk,
        engScore: widget.engOk,
        totalPct: widget.pct.toDouble(),
      );
    } catch (e) {
      debugPrint('Tarixga yozishda xato: $e');
    }

    final payload = _buildPayload();
    final token = newIdempotencyToken();
    try {
      await OfflineQueue.enqueueLocal(payload, token);
      // Immediate send without blocking UI
      SyncService.instance.flushNow();
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sendStatus = AppLocalizations.of(context)!.localResSavedSending;
      });
      // Submit bo'lgandan keyin HTML ni bot uchun yuklaymiz (retry bilan)
      _autoUploadHtmlForBot(token);
    } catch (e) {
      debugPrint('Navbatga yozishda xato: $e');
      if (!mounted) return;
      setState(() {
        _sent = false;
        _sendStatus = AppLocalizations.of(context)!.localResSaveError;
      });
    }
  }

  /// App ko'rsatadigan HTML ni bot uchun serverga yuklaydi.
  /// Race condition: /result/ submit va HTML upload parallel — agar natija
  /// DB ga hali yetmagan bo'lsa (404), exponential back-off: 2s → 5s → 10s.
  Future<void> _autoUploadHtmlForBot(String token) async {
    String htmlStr;
    try {
      htmlStr = HtmlService.generateResultHtml(
        firstName: widget.firstName,
        lastName: widget.lastName,
        group: widget.group,
        grade: widget.grade,
        variant: widget.variant,
        mathOk: widget.mathOk,
        mathTotal: _mathTotal,
        engOk: widget.engOk,
        engTotal: _engTotal,
        pct: widget.pct,
        mathTopics: _mathTopics,
        engTopics: _engTopics,
      );
    } catch (e) {
      debugPrint(
          'LocalResultScreen._autoUploadHtmlForBot: HTML generate xato: $e');
      return;
    }

    const delays = [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10)
    ];
    for (var i = 0; i <= delays.length; i++) {
      try {
        final ok = await api.uploadResultHtml(token, htmlStr);
        if (ok) return; // muvaffaqiyatli yuklandi
        // ok==false → 404 (result hali serverda yo'q) — keyingi urinish
      } catch (e) {
        debugPrint(
            'LocalResultScreen._autoUploadHtmlForBot attempt $i error: $e');
        return; // tarmoq xatosi — qayta urinish ma'nosiz
      }
      if (i < delays.length) {
        debugPrint(
            'LocalResultScreen._autoUploadHtmlForBot: 404, ${delays[i].inSeconds}s kutilmoqda...');
        await Future<void>.delayed(delays[i]);
      }
    }
    debugPrint(
        'LocalResultScreen._autoUploadHtmlForBot: barcha urinishlar tugadi.');
  }

  Map<String, dynamic> _buildPayload() {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final startedAt = widget.testStartedAt;
    final durationSeconds =
        startedAt != null ? now.difference(startedAt).inSeconds : 0;
    return {
      'name': '${widget.lastName} ${widget.firstName}'.trim(),
      'grade': widget.grade,
      'variant': widget.variant.toString(),
      'source': 'flutter',
      'vocab': {'cor': 0, 'tot': 0},
      'english': {'cor': widget.engOk, 'tot': _engTotal},
      'math': {'cor': widget.mathOk, 'tot': _mathTotal},
      'pct': widget.pct,
      'time': time,
      'school_code': widget.school,
      if (durationSeconds > 0) 'duration_seconds': durationSeconds,
    };
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
                          ? [AppColors.emerald, const Color(0xFF059669)]
                          : [AppColors.brightRed, AppColors.error],
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
                // A'lochi logo
                Container(
                  width: 56,
                  height: 56,
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: ClipOval(
                      child:
                          Image.asset('assets/logo.png', fit: BoxFit.contain)),
                ),
                const SizedBox(height: 8),
                // Result emoji
                Icon(
                    widget.pct >= 80
                        ? Icons.celebration_rounded
                        : widget.pct >= 60
                            ? Icons.emoji_events_rounded
                            : Icons.fitness_center_rounded,
                    size: 36,
                    color: Colors.white),
                const SizedBox(height: 8),
                Text(
                    widget.pct >= 80
                        ? AppLocalizations.of(context)!.localResBarakalla
                        : widget.pct >= 60
                            ? AppLocalizations.of(context)!.localResYaxshi
                            : AppLocalizations.of(context)!.keepTrying,
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
                      AppLocalizations.of(context)!.mathSubjectFull,
                      widget.mathOk,
                      _mathTotal,
                      AppColors.math)),
              const SizedBox(width: 10),
              Expanded(
                  child: _ScoreCard(
                      AppLocalizations.of(context)!.englishSubjectFull,
                      widget.engOk,
                      _engTotal,
                      AppColors.eng)),
            ]),
            const SizedBox(height: 16),
            // Topics
            if (widget.topicScores.isNotEmpty) ...[
              _TopicsCard(
                  title: AppLocalizations.of(context)!.mathSubjectFull,
                  icon: Icons.calculate_rounded,
                  color: AppColors.math,
                  isMath: true,
                  topics: widget.topicScores,
                  questions: widget.questions),
              const SizedBox(height: 10),
              _TopicsCard(
                  title: AppLocalizations.of(context)!.englishSubjectFull,
                  icon: Icons.language_rounded,
                  color: AppColors.eng,
                  isMath: false,
                  topics: widget.topicScores,
                  questions: widget.questions),
              const SizedBox(height: 16),
            ],
            // Send status
            _buildSendStatus(),
            const SizedBox(height: 16),
            // PDF Actions
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final pdfBytes = await PdfService.generateResultPdf(
                      firstName: widget.firstName,
                      lastName: widget.lastName,
                      group: widget.group,
                      grade: widget.grade,
                      variant: widget.variant,
                      mathOk: widget.mathOk,
                      mathTotal: _mathTotal,
                      engOk: widget.engOk,
                      engTotal: _engTotal,
                      pct: widget.pct,
                      mathTopics: _mathTopics,
                      engTopics: _engTopics,
                      l10n: AppLocalizations.of(context)!,
                    );
                    await Printing.layoutPdf(
                        onLayout: (_) => pdfBytes,
                        name:
                            '${widget.lastName}_${widget.firstName}_Natija.pdf');
                  },
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: Text(AppLocalizations.of(context)!.printPdf),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink1,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final pdfBytes = await PdfService.generateResultPdf(
                      firstName: widget.firstName,
                      lastName: widget.lastName,
                      group: widget.group,
                      grade: widget.grade,
                      variant: widget.variant,
                      mathOk: widget.mathOk,
                      mathTotal: _mathTotal,
                      engOk: widget.engOk,
                      engTotal: _engTotal,
                      pct: widget.pct,
                      mathTopics: _mathTopics,
                      engTopics: _engTopics,
                      l10n: AppLocalizations.of(context)!,
                    );
                    await Printing.sharePdf(
                        bytes: pdfBytes,
                        filename:
                            '${widget.lastName}_${widget.firstName}_Natija.pdf');
                  },
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: Text(AppLocalizations.of(context)!.savePdf),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      side: const BorderSide(color: AppColors.brand),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            // Next student button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.person_add_rounded),
                label: Text(AppLocalizations.of(context)!.nextStudentButton,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.home_rounded, size: 16),
              label: Text(AppLocalizations.of(context)!.homePage),
              style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
            ),
          ]),
        ),
      ))),
    );
  }

  Widget _buildSendStatus() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _sent ? AppColors.successMuted : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _sent ? AppColors.correctBorder : AppColors.border),
      ),
      child: Row(children: [
        Icon(_sent ? Icons.check_circle_rounded : Icons.cloud_upload_rounded,
            color: _sent ? AppColors.ok : AppColors.brand, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(_sendStatus,
                style: TextStyle(
                    fontSize: 13,
                    color: _sent ? AppColors.ok : AppColors.ink2,
                    fontWeight: FontWeight.w600))),
      ]),
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
                  ? AppColors.amber
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
