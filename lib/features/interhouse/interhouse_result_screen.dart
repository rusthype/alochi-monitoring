// lib/features/interhouse/interhouse_result_screen.dart
// Interhouse Grade 2 result display + submission
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../core/models/models.dart';
import '../../core/api/api_client.dart';
import '../../core/db/offline_queue.dart';
import '../../core/db/history_db.dart';
import '../../core/sync/sync_service.dart';
import '../../core/services/pdf_service.dart';
import 'package:printing/printing.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'interhouse_data.dart';
import 'interhouse_scorer.dart';
import '../../core/utils/topic_format.dart';

class InterhouseResultScreen extends StatefulWidget {
  final IhResult result;
  final IhTestData testData;
  final int variant;
  final bool isOnline;
  final StudentSession? session;
  final String? packageId;
  final String? firstName;
  final String? lastName;
  final String? school;
  final DateTime? testStartedAt;

  const InterhouseResultScreen({
    super.key,
    required this.result,
    required this.testData,
    required this.variant,
    required this.isOnline,
    this.session,
    this.packageId,
    this.firstName,
    this.lastName,
    this.school,
    this.testStartedAt,
  });

  @override
  State<InterhouseResultScreen> createState() => _InterhouseResultScreenState();
}

class _InterhouseResultScreenState extends State<InterhouseResultScreen>
    with TickerProviderStateMixin {
  late final AnimationController _scoreAnim;
  late final Animation<double> _scoreVal;
  String _sendStatus = 'Yuborilmoqda...';
  bool _sent = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _scoreAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _scoreVal = Tween<double>(begin: 0, end: widget.result.totalPct / 100)
        .animate(CurvedAnimation(parent: _scoreAnim, curve: Curves.easeOut));
    _scoreAnim.forward();
    _submit();
  }

  @override
  void dispose() {
    SyncService.instance.flushNow();
    _scoreAnim.dispose();
    super.dispose();
  }

  String _studentName() {
    if (widget.isOnline) return widget.session?.studentName ?? '';
    final last = widget.lastName ?? '';
    final first = widget.firstName ?? '';
    return '$last $first'.trim();
  }

  List<MapEntry<String, ({int ok, int tot})>> get _engTopics =>
      widget.result.parts
          .map((p) => MapEntry(p.partName, (ok: p.score, tot: 6)))
          .toList();

  Map<String, dynamic> _buildDetail() => {
        'test_key': 'interhouse_g2',
        'variant': widget.variant,
        'topics': topicsFromEngEntries(_engTopics),
        'shields': widget.result.parts.map((p) => p.shields).toList(),
        'total': widget.result.total,
        'total_shields': widget.result.totalShields,
        'level': widget.result.level.label,
        'cambridge': widget.result.level.cambridge,
        'cefr': widget.result.level.cefr,
      };

  Map<String, dynamic> _buildOfflinePayload() {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final startedAt = widget.testStartedAt;
    final durationSeconds =
        startedAt != null ? now.difference(startedAt).inSeconds : 0;
    return {
      'name': _studentName(),
      'grade': 2,
      'variant': widget.variant.toString(),
      'source': 'flutter',
      'vocab': {'cor': 0, 'tot': 0},
      'english': {'cor': widget.result.total, 'tot': 30},
      'math': {'cor': 0, 'tot': 0},
      'pct': widget.result.totalPct,
      'time': time,
      'school_code': widget.school ?? '',
      'detail': _buildDetail(),
      if (durationSeconds > 0) 'duration_seconds': durationSeconds,
    };
  }

  Future<void> _submit() async {
    try {
      // Save to local history
      await HistoryDb.insertResult(
        firstName: widget.firstName ?? (widget.session?.studentName ?? ''),
        lastName: widget.lastName ?? '',
        school: widget.school ?? '—',
        gradeGroup: '2-sinf IH',
        mathScore: 0,
        engScore: widget.result.total,
        totalPct: widget.result.totalPct.toDouble(),
      );
    } catch (e) {
      debugPrint('IH HistoryDb error: $e');
    }

    try {
      if (widget.isOnline) {
        await _submitOnline();
      } else {
        await _submitOffline();
      }
    } catch (e) {
      debugPrint('IH submit error: $e');
      if (mounted) {
        setState(() {
          _error = true;
          _sendStatus = 'Xatolik. Keyinroq yuboriladi.';
        });
      }
    }
  }

  Future<void> _submitOnline() async {
    final detail = _buildDetail();
    final testResult = TestResult(
      packageId: widget.packageId ?? '',
      variant: widget.variant,
      mathScore: 0,
      engScore: widget.result.total,
      totalPct: widget.result.totalPct,
      answers: const {},
      deviceId: 'flutter_interhouse-${defaultTargetPlatform.name}',
    );

    final resp = await api.submitResultFull(testResult, detail: detail);
    final synced = resp['synced'] as bool? ?? false;
    final permanent = resp['permanent'] as bool? ?? false;

    if (!synced && !permanent) {
      // Queue for retry (transient errors only — permanent 4xx are dropped)
      await OfflineQueue.enqueue(testResult);
    }

    if (mounted) {
      setState(() {
        _sent = true;
        _sendStatus =
            synced ? 'Saqlandi!' : 'Saqlandi (offline — keyinroq yuboriladi)';
      });
    }
  }

  Future<void> _submitOffline() async {
    final payload = _buildOfflinePayload();
    final token = newIdempotencyToken();
    await OfflineQueue.enqueueLocal(payload, token);
    OfflineQueue.waitForDropReason(token).then<void>((reason) {
      if (reason == 'max_attempts_exceeded' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.maxAttemptsExceeded),
          backgroundColor: AppColors.err,
          duration: const Duration(seconds: 6),
        ));
      }
    }).catchError((e) {
      debugPrint('InterhouseResultScreen: waitForDropReason error: $e');
      return Future<void>.value();
    });
    if (mounted) {
      setState(() {
        _sent = true;
        _sendStatus = 'Saqlandi, yuborilmoqda...';
      });
    }
  }

  String _getSendStatusText(AppLocalizations l10n) {
    switch (_sendStatus) {
      case 'Yuborilmoqda...':
        return l10n.sending;
      case 'Xatolik. Keyinroq yuboriladi.':
        return l10n.errorLater;
      case 'Saqlandi!':
        return l10n.savedSuccess;
      case 'Saqlandi (offline — keyinroq yuboriladi)':
        return l10n.savedOfflineLater;
      case 'Saqlandi, yuborilmoqda...':
        return l10n.savedSending;
      default:
        return _sendStatus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final result = widget.result;
    final level = result.level;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                // ── Header card ───────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.violet, AppColors.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.violet.withValues(alpha: .3),
                          blurRadius: 20,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: Column(children: [
                    Container(
                      width: 56,
                      height: 56,
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      child: ClipOval(
                          child: Image.asset('assets/logo.png',
                              fit: BoxFit.contain)),
                    ),
                    const SizedBox(height: 8),
                    Text(l10n.interhouseGrade2,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_studentName(),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                        '${l10n.variantBadge(widget.variant)} · ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white60)),
                    const SizedBox(height: 20),

                    // Score ring
                    AnimatedBuilder(
                        animation: _scoreVal,
                        builder: (_, __) {
                          final pct = (_scoreVal.value * 100).round();
                          return Stack(alignment: Alignment.center, children: [
                            SizedBox(
                                width: 110,
                                height: 110,
                                child: CircularProgressIndicator(
                                    value: _scoreVal.value,
                                    strokeWidth: 9,
                                    backgroundColor: Colors.white24,
                                    valueColor: const AlwaysStoppedAnimation(
                                        Colors.white))),
                            Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('$pct%',
                                  style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
                              Text('${result.total}/30',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white70)),
                            ]),
                          ]);
                        }),
                    const SizedBox(height: 12),
                    Text(l10n.shieldsProgressLabel(result.totalShields),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70)),
                  ]),
                ),

                const SizedBox(height: 16),

                // ── Level badge ────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: level.bgColor,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: level.colColor.withValues(alpha: .3)),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: level.colColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(level.label,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        _LevelRow('Cambridge', level.cambridge, level.colColor),
                        const SizedBox(height: 4),
                        _LevelRow('CEFR', level.cefr, level.colColor),
                      ]),
                ),

                const SizedBox(height: 16),

                // ── Part breakdown ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.sectionsBreakdown,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink1)),
                        const SizedBox(height: 14),
                        ...result.parts.map(
                          (p) => _PartRow(part: p),
                        ),
                      ]),
                ),

                const SizedBox(height: 16),

                // ── Send status ────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _error
                        ? AppColors.errMuted
                        : _sent
                            ? AppColors.okMuted
                            : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _error
                            ? AppColors.err.withValues(alpha: .3)
                            : _sent
                                ? AppColors.correctBorder
                                : AppColors.border),
                  ),
                  child: Row(children: [
                    Icon(
                      _error
                          ? Icons.warning_rounded
                          : _sent
                              ? Icons.check_circle_rounded
                              : Icons.cloud_upload_rounded,
                      color: _error
                          ? AppColors.err
                          : _sent
                              ? AppColors.ok
                              : AppColors.brand,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(_getSendStatusText(l10n),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _error
                                    ? AppColors.err
                                    : _sent
                                        ? AppColors.ok
                                        : AppColors.ink2))),
                  ]),
                ),

                const SizedBox(height: 16),

                // ── PDF buttons ────────────────────────────────────────────
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final first = widget.firstName ??
                            (widget.session?.studentName ?? '');
                        final last = widget.lastName ?? '';
                        final pdfBytes = await PdfService.generateResultPdf(
                          firstName: first,
                          lastName: last,
                          group: '',
                          grade: 2,
                          variant: widget.variant,
                          mathOk: 0,
                          mathTotal: 0,
                          engOk: widget.result.total,
                          engTotal: 30,
                          pct: widget.result.totalPct,
                          mathTopics: const [],
                          engTopics: _engTopics,
                          l10n: l10n,
                        );
                        await Printing.layoutPdf(
                            onLayout: (_) => pdfBytes,
                            name: '${last}_${first}_Natija.pdf');
                      },
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: Text(l10n.printPdf),
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
                        final first = widget.firstName ??
                            (widget.session?.studentName ?? '');
                        final last = widget.lastName ?? '';
                        final pdfBytes = await PdfService.generateResultPdf(
                          firstName: first,
                          lastName: last,
                          group: '',
                          grade: 2,
                          variant: widget.variant,
                          mathOk: 0,
                          mathTotal: 0,
                          engOk: widget.result.total,
                          engTotal: 30,
                          pct: widget.result.totalPct,
                          mathTopics: const [],
                          engTopics: _engTopics,
                          l10n: l10n,
                        );
                        await Printing.sharePdf(
                            bytes: pdfBytes,
                            filename: '${last}_${first}_Natija.pdf');
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: Text(l10n.savePdf),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brand,
                          side: const BorderSide(color: AppColors.brand),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ]),

                const SizedBox(height: 16),

                // ── Buttons ────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.person_add_rounded),
                    label: Text(l10n.nextStudentBtn,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.home_rounded, size: 16),
                  label: Text(l10n.homePage),
                  style: TextButton.styleFrom(foregroundColor: AppColors.ink2),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _LevelRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _LevelRow(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
        Text('$label: ',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: .7))),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: color))),
      ]);
}

class _PartRow extends StatelessWidget {
  final IhPartScore part;
  const _PartRow({required this.part});

  @override
  Widget build(BuildContext context) {
    final filled = '■' * part.shields;
    final empty = '□' * (5 - part.shields);
    final shieldStr = filled + empty;
    final progress = part.score / 6;
    final clr = progress >= 0.8
        ? AppColors.ok
        : progress >= 0.5
            ? AppColors.amber
            : AppColors.err;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(part.partName,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink1))),
          Text('${part.score}/6',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: clr)),
          const SizedBox(width: 10),
          Text(shieldStr,
              style: TextStyle(fontSize: 14, letterSpacing: 2, color: clr)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            Container(
                height: 6,
                width: double.infinity,
                color: clr.withValues(alpha: .12)),
            FractionallySizedBox(
                widthFactor: progress, child: Container(height: 6, color: clr)),
          ]),
        ),
      ]),
    );
  }
}
