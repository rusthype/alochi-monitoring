// lib/features/test/engine_host_screen.dart
// Faza 4b — wires JSON-driven TestEngine into the catalog flow.
//
// Section → math/english payload mapping rules (applied in _isMathSection):
//   "Math" | starts-with "Matema"  → math field (correct + total)
//   Everything else                → english accumulator (yig'indi)
//
// The canonical source of truth is detail.sections (full per-section scores).
// The top-level math/english/vocab fields exist only for legacy panel display.
// vocab is always {cor:0, tot:0} — engine tests don't have a separate vocab section.
//
// Duration default: 60 seconds per answerable question, clamped to [60s, 90min].

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/api_client.dart';
import '../../core/db/attempt_store.dart';
import '../../core/db/history_db.dart';
import '../../core/db/offline_queue.dart';
import '../../core/engine/test_engine.dart';
import '../../core/engine/test_models.dart';
import '../../core/engine/test_scorer.dart';
import '../../core/services/pdf_service.dart';
import '../../core/sync/sync_service.dart';
import '../../shared/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EngineHostScreen
// ─────────────────────────────────────────────────────────────────────────────

class EngineHostScreen extends StatefulWidget {
  /// Raw test data blob from TestCache.get() or a bare test_data object.
  ///
  /// Accepted shapes:
  ///   A) {test_key, title, grade, version, test_data: {...}} — from TestCache.get()
  ///   B) {test_key, title, grade, variants: {...}, ...}      — raw test blob
  final Map<String, dynamic> testData;

  final int variant;
  final String firstName;
  final String lastName;
  final String school;
  final String? group;
  final int? grade;
  final String studentId;

  /// Optional override. When null, defaults to 60 s/question (min 60s, max 90min).
  final Duration? duration;

  const EngineHostScreen({
    super.key,
    required this.testData,
    required this.variant,
    required this.firstName,
    required this.lastName,
    required this.school,
    this.group,
    this.grade,
    this.studentId = '',
    this.duration,
  });

  @override
  State<EngineHostScreen> createState() => _EngineHostScreenState();
}

class _EngineHostScreenState extends State<EngineHostScreen> {
  TestSpec? _spec;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _parseSpec();
  }

  void _parseSpec() {
    try {
      // Unwrap the cache wrapper if present.
      final Map<String, dynamic> blob = (widget.testData['test_data'] is Map)
          ? Map<String, dynamic>.from(widget.testData['test_data'] as Map)
          : widget.testData;

      final spec = TestSpec.fromJson(blob);
      if (spec.variants.isEmpty) {
        _parseError = 'Test ma\'lumotlari bo\'sh (variants topilmadi)';
      } else {
        _spec = spec;
      }
    } catch (e) {
      _parseError = 'Test yuklanmadi: $e';
    }
  }

  // ── Duration helper ─────────────────────────────────────────────────────────

  Duration _effectiveDuration(TestSpec spec) {
    if (widget.duration != null) return widget.duration!;
    if (spec.durationMinutes != null && spec.durationMinutes! > 0) {
      final mins = spec.durationMinutes!.clamp(1, 180);
      return Duration(minutes: mins);
    }
    final variantKey = widget.variant.toString();
    final sections = spec.sectionsForVariant(variantKey);
    final totalQs = sections.fold(0, (sum, s) => sum + s.questionCount);
    final secs = (totalQs * 60).clamp(60, 90 * 60);
    return Duration(seconds: secs);
  }

  // ── Section mapping ─────────────────────────────────────────────────────────

  /// True when the section name maps to the "math" bucket in the legacy payload.
  static bool isMathSection(String name) {
    final n = name.trim().toLowerCase();
    return n == 'math' || n.startsWith('matema');
  }

  _Agg _mathAgg(ScoredResult result) {
    int cor = 0, tot = 0;
    for (final s in result.sectionScores) {
      if (isMathSection(s.name)) {
        cor += s.correct;
        tot += s.total;
      }
    }
    return _Agg(cor, tot);
  }

  _Agg _engAgg(ScoredResult result) {
    int cor = 0, tot = 0;
    for (final s in result.sectionScores) {
      if (!isMathSection(s.name)) {
        cor += s.correct;
        tot += s.total;
      }
    }
    return _Agg(cor, tot);
  }

  // ── Payload builder ─────────────────────────────────────────────────────────
  //
  // Maps ScoredResult → the Map<String, dynamic> shape consumed by
  // OfflineQueue.enqueueLocal / api.submitLocalResult.
  // math/english top-level are for legacy panel only.
  // detail.sections is the canonical per-section breakdown.

  Map<String, dynamic> _buildPayload(ScoredResult result) {
    final math = _mathAgg(result);
    final eng = _engAgg(result);

    return <String, dynamic>{
      'name': '${widget.lastName} ${widget.firstName}',
      'grade': widget.grade ?? _spec?.grade ?? 0,
      'variant': widget.variant.toString(),
      'source': 'flutter',
      'math': {'cor': math.correct, 'tot': math.total},
      'english': {'cor': eng.correct, 'tot': eng.total},
      'vocab': {'cor': 0, 'tot': 0},
      'pct': result.totalPct.round(),
      'school_code': widget.school,
      'group_name': widget.group ?? '',
      'student_id': widget.studentId,
      'detail': <String, dynamic>{
        'sections': result.sectionScores
            .map((s) => <String, dynamic>{
                  'name': s.name,
                  'correct': s.correct,
                  'total': s.total,
                  'pct': s.pct,
                })
            .toList(),
        if (result.shields != null) 'shields': result.shields,
        if (result.levelLabel != null) 'level': result.levelLabel,
        'test_key': result.testKey,
      },
    };
  }

  // ── onComplete ──────────────────────────────────────────────────────────────

  Future<void> _handleComplete(ScoredResult result) async {
    final payload = _buildPayload(result);
    final token = newIdempotencyToken();

    // 1. Save to local history DB.
    try {
      final math = _mathAgg(result);
      final eng = _engAgg(result);
      await HistoryDb.insertResult(
        firstName: widget.firstName,
        lastName: widget.lastName,
        school: widget.school,
        gradeGroup: widget.group ?? '',
        mathScore: math.correct,
        engScore: eng.correct,
        totalPct: result.totalPct,
      );
    } catch (e) {
      debugPrint('EngineHostScreen: HistoryDb error: $e');
    }

    // 2. Enqueue for offline-first sync.
    try {
      await OfflineQueue.enqueueLocal(payload, token);
    } catch (e) {
      debugPrint('EngineHostScreen: enqueueLocal error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              "Natija saqlanmadi — internet yoki xotira muammosi. Qayta urinib ko'ring."),
          backgroundColor: AppColors.err,
          duration: const Duration(seconds: 6),
        ));
      }
    }

    // 3. Attempt an immediate flush (fire-and-forget — don't block navigation).
    SyncService.instance.flushNow().catchError((e) {
      debugPrint('EngineHostScreen: flushNow error: $e');
      return Future<void>.value();
    });

    // 4. Submit succeeded — drop the crash-recovery attempt record so a
    // relaunch of this test starts fresh instead of "resuming" a finished one.
    try {
      await AttemptStore.clear(result.testKey);
    } catch (e) {
      debugPrint('EngineHostScreen: AttemptStore.clear error: $e');
    }

    // 5. Navigate to result display.
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _EngineResultScreen(
          firstName: widget.firstName,
          lastName: widget.lastName,
          school: widget.school,
          group: widget.group,
          grade: widget.grade ?? _spec?.grade ?? 0,
          variant: widget.variant,
          result: result,
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_parseError != null) {
      return _ErrorScaffold(message: _parseError!);
    }
    if (_spec == null) {
      return const _ErrorScaffold(message: 'Test yuklanmadi');
    }

    return TestEngine(
      spec: _spec!,
      variant: widget.variant,
      firstName: widget.firstName,
      lastName: widget.lastName,
      school: widget.school,
      group: widget.group,
      studentId: widget.studentId,
      duration: _effectiveDuration(_spec!),
      onComplete: _handleComplete,
    );
  }
}

// ── Internal aggregator ───────────────────────────────────────────────────────

class _Agg {
  final int correct;
  final int total;
  const _Agg(this.correct, this.total);
}

// ── Error scaffold ────────────────────────────────────────────────────────────

class _ErrorScaffold extends StatelessWidget {
  final String message;
  const _ErrorScaffold({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: const BackButton(color: AppColors.ink1),
        title: const Text('Test', style: AppTextStyles.titleMedium),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 56, color: AppColors.err),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge.copyWith(color: AppColors.ink2),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Orqaga'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EngineResultScreen
//
// Simple result display: score ring + per-section table + PDF button.
// Does NOT modify or extend the existing ResultScreen (which requires
// TestResult/StudentSession/TestPackage — the old schema).
// ─────────────────────────────────────────────────────────────────────────────

class _EngineResultScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String school;
  final String? group;
  final int grade;
  final int variant;
  final ScoredResult result;

  const _EngineResultScreen({
    required this.firstName,
    required this.lastName,
    required this.school,
    this.group,
    required this.grade,
    required this.variant,
    required this.result,
  });

  @override
  State<_EngineResultScreen> createState() => _EngineResultScreenState();
}

class _EngineResultScreenState extends State<_EngineResultScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  bool _pdfGenerating = false;
  String? _pdfPath;

  // AI summary (TZ §10.4) — null until loaded; stays null if offline/unavailable
  // (in which case the card is not shown at all).
  Map<String, dynamic>? _aiSummary;
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadAiSummary();
  }

  /// Fetches the AI analysis (TZ §10.4) for the per-topic breakdown.
  /// Silent on failure — `api.fetchAiSummary` returns null offline / when the
  /// AI service is unavailable, and the card simply stays hidden.
  Future<void> _loadAiSummary() async {
    final topics = widget.result.topicScores;
    if (topics.isEmpty) return; // nothing to analyze — card stays hidden

    setState(() => _aiLoading = true);
    try {
      final payload = topics
          .map((t) => <String, dynamic>{
                'topic': t.topic,
                'correct': t.correct,
                'total': t.total,
                'pct': t.pct.round(),
              })
          .toList();
      final data = await api.fetchAiSummary(
        grade: widget.grade,
        totalPct: widget.result.totalPct.round(),
        topics: payload,
      );
      if (!mounted) return;
      setState(() {
        _aiSummary = data;
        _aiLoading = false;
      });
    } catch (e) {
      debugPrint('_EngineResultScreen._loadAiSummary error: $e');
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  int _secPct(SectionScore s) =>
      s.total > 0 ? (s.correct / s.total * 100).round() : 0;

  Color _secColor(int pct) {
    if (pct >= 80) return AppColors.success;
    if (pct >= 55) return AppColors.secondary;
    return const Color(0xFFEF4444);
  }

  String _gradeLabel(int pct) {
    if (pct >= 90) return "A'lo";
    if (pct >= 75) return 'Yaxshi';
    if (pct >= 55) return 'Qoniqarli';
    return "Qo'shimcha mashq kerak";
  }

  List<SectionScore> _weakSections() {
    final list = widget.result.sectionScores
        .where((s) => _secPct(s) < 75)
        .toList()
      ..sort((a, b) => _secPct(a).compareTo(_secPct(b)));
    return list;
  }

  List<SectionScore> _strongSections() =>
      widget.result.sectionScores.where((s) => _secPct(s) >= 75).toList();

  Future<void> _generatePdf() async {
    if (_pdfGenerating) return;
    setState(() => _pdfGenerating = true);
    try {
      final mathTopics = <MapEntry<String, ({int ok, int tot})>>[];
      final engTopics = <MapEntry<String, ({int ok, int tot})>>[];
      int mathOk = 0, mathTot = 0, engOk = 0, engTot = 0;

      for (final s in widget.result.sectionScores) {
        final entry = MapEntry(s.name, (ok: s.correct, tot: s.total));
        if (_EngineHostScreenState.isMathSection(s.name)) {
          mathTopics.add(entry);
          mathOk += s.correct;
          mathTot += s.total;
        } else {
          engTopics.add(entry);
          engOk += s.correct;
          engTot += s.total;
        }
      }

      // Per-§ / per-topic breakdown + AI summary for the TZ §11 passport.
      final topicScores = widget.result.topicScores
          .map((t) => MapEntry(t.topic, (ok: t.correct, tot: t.total)))
          .toList();

      final bytes = await PdfService.generateResultPdf(
        firstName: widget.firstName,
        lastName: widget.lastName,
        group: widget.group ?? '',
        grade: widget.grade,
        variant: widget.variant,
        mathOk: mathOk,
        mathTotal: mathTot,
        engOk: engOk,
        engTotal: engTot,
        pct: widget.result.totalPct.round(),
        mathTopics: mathTopics,
        engTopics: engTopics,
        topicScores: topicScores,
        aiSummary: _aiSummary,
      );

      final dir = await getApplicationSupportDirectory();
      final path =
          '${dir.path}/result_${widget.firstName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(path).writeAsBytes(bytes);

      if (mounted) setState(() => _pdfPath = path);
      await OpenFilex.open(path);
    } catch (e) {
      debugPrint('_EngineResultScreen._generatePdf error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF yaratishda xato'),
            backgroundColor: AppColors.err,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pdfGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final pct = result.totalPct.round();
    final correct = result.totalCorrect;
    final wrong = result.totalQuestions - result.totalCorrect;
    final heroColor = _secColor(pct);
    final gradeLabel = _gradeLabel(pct);
    final weak = _weakSections();
    final strong = _strongSections();
    final studentName = '${widget.firstName} ${widget.lastName}';
    final subLine =
        '${widget.group?.isNotEmpty == true ? widget.group! : widget.school} · Variant ${widget.variant}';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Natija', style: AppTextStyles.titleMedium),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context)
                .popUntil((route) => route.settings.name == 'student_entry'),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text("Keyingi o'quvchi"),
          ),
          TextButton.icon(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_rounded, size: 18),
            label: const Text('Bosh sahifa'),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fade,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. Header ─────────────────────────────────────────────────
              _ReportCard(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppColors.secondaryMuted,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded,
                          size: 22, color: AppColors.secondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(studentName, style: AppTextStyles.titleMedium),
                          const SizedBox(height: 2),
                          Text(subLine, style: AppTextStyles.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── 2. Score hero ─────────────────────────────────────────────
              _ReportCard(
                child: Column(
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: result.totalPct / 100,
                              strokeWidth: 9,
                              backgroundColor: AppColors.gray100,
                              color: heroColor,
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: heroColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      gradeLabel,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: heroColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatChip(
                          icon: Icons.check_circle_rounded,
                          label: "To'g'ri $correct",
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.cancel_rounded,
                          label: 'Xato $wrong',
                          color: const Color(0xFFEF4444),
                        ),
                      ],
                    ),
                    if (result.shields != null ||
                        result.levelLabel != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          if (result.shields != null)
                            _BadgeChip(
                              icon: Icons.shield_rounded,
                              label: '${result.shields} qalqon',
                              color: AppColors.primary,
                            ),
                          if (result.levelLabel != null)
                            _BadgeChip(
                              icon: Icons.military_tech_rounded,
                              label: result.levelLabel!,
                              color: AppColors.success,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── 3. Bo'limlar bo'yicha ─────────────────────────────────────
              _ReportCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHead(
                      icon: Icons.bar_chart_rounded,
                      label: "BO'LIMLAR BO'YICHA",
                    ),
                    const SizedBox(height: 8),
                    if (result.sectionScores.isEmpty)
                      const Text("Ma'lumot yo'q", style: AppTextStyles.bodyMedium)
                    else
                      ...result.sectionScores.map(
                        (s) => _SectionRowV2(
                          section: s,
                          pct: _secPct(s),
                          color: _secColor(_secPct(s)),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _TzAnalysis(result: widget.result),

              // ── AI summary (TZ §10.4) — hidden when offline/unavailable ────
              if (_aiLoading || _aiSummary != null) ...[
                const SizedBox(height: 16),
                _AiSummaryCard(loading: _aiLoading, data: _aiSummary),
              ],

              // NOTE(merge-review): old "6. AI xulosa" (fake local template)
              // and old "5. 14 kunlik reja" were both removed — the new
              // _TzAnalysis above already covers per-topic analysis + its
              // own 14-day plan, and _AiSummaryCard replaces the AI xulosa.
              // The remaining "4. Tahlil" section below is section-level
              // (coarser than _TzAnalysis's per-topic breakdown) — left as
              // a separate, lower-priority overlap; revisit if desired.
              const SizedBox(height: 24),

              // ── 4. Tahlil ─────────────────────────────────────────────────
              _ReportCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHead(
                      icon: Icons.insights_rounded,
                      label: 'TAHLIL',
                    ),
                    const SizedBox(height: 8),
                    if (strong.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              size: 16, color: AppColors.success),
                          const SizedBox(width: 6),
                          Text(
                            'Kuchli tomonlar',
                            style: AppTextStyles.labelLarge
                                .copyWith(color: AppColors.success),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...strong.take(4).map((s) {
                        final p = _secPct(s);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin:
                                    const EdgeInsets.only(right: 8, top: 4),
                                decoration: const BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  "${s.name} — $p% · yaxshi o'zlashtirilgan",
                                  style: AppTextStyles.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    if (strong.isNotEmpty && weak.isNotEmpty)
                      const SizedBox(height: 12),
                    if (weak.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 16, color: Color(0xFFEF4444)),
                          const SizedBox(width: 6),
                          Text(
                            'Mustahkamlash kerak',
                            style: AppTextStyles.labelLarge.copyWith(
                              color: const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...weak.take(5).map((s) {
                        final p = _secPct(s);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin:
                                    const EdgeInsets.only(right: 8, top: 4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  "${s.name} — $p% · qo'shimcha mashq",
                                  style: AppTextStyles.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                    if (weak.isEmpty)
                      Row(
                        children: [
                          const Icon(Icons.celebration_rounded,
                              size: 18, color: AppColors.success),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Barcha bo'limlar yaxshi o'zlashtirilgan!",
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.success),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── 7. PDF action ─────────────────────────────────────────────
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _pdfGenerating ? null : _generatePdf,
                icon: _pdfGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 20),
                label: Text(
                  _pdfPath != null ? 'PDF qayta ochish' : 'PDF hisobot',
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Badge chip ────────────────────────────────────────────────────────────────

class _BadgeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _BadgeChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── AI summary card (TZ §10.4) ──────────────────────────────────────────────────

class _AiSummaryCard extends StatelessWidget {
  final bool loading;
  final Map<String, dynamic>? data;
  const _AiSummaryCard({required this.loading, this.data});

  static List<String> _strList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final summary = data?['summary']?.toString().trim() ?? '';
    final strengths = _strList(data?['strengths']);
    final weaknesses = _strList(data?['weaknesses']);
    final recs = _strList(data?['recommendations']);
    final focus = _strList(data?['focus_14day']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.primary),
            SizedBox(width: 8),
            Text('AI tahlil', style: AppTextStyles.labelLarge),
          ]),
          const SizedBox(height: 12),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Tahlil tayyorlanmoqda…',
                      style: AppTextStyles.bodyMedium),
                ),
              ]),
            )
          else ...[
            if (summary.isNotEmpty)
              Text(summary, style: AppTextStyles.bodyLarge.copyWith(height: 1.4)),
            if (strengths.isNotEmpty) ...[
              const SizedBox(height: 14),
              _block('Kuchli tomonlar', strengths,
                  Icons.check_circle_rounded, AppColors.ok),
            ],
            if (weaknesses.isNotEmpty) ...[
              const SizedBox(height: 14),
              _block('Zaif tomonlar', weaknesses, Icons.error_rounded,
                  AppColors.err),
            ],
            if (recs.isNotEmpty) ...[
              const SizedBox(height: 14),
              _block('Tavsiyalar', recs, Icons.lightbulb_rounded,
                  const Color(0xFFD97706)),
            ],
            if (focus.isNotEmpty) ...[
              const SizedBox(height: 14),
              _block('14 kunlik e\'tibor', focus,
                  Icons.calendar_today_rounded, AppColors.primary),
            ],
          ],
        ],
      ),
    );
  }

  Widget _block(String title, List<String> items, IconData icon, Color color) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color)),
        const SizedBox(height: 6),
        ...items.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(t, style: AppTextStyles.bodyMedium)),
              ]),
            )),
      ]);
}

// ── TZ per-§ analysis: accordion + strong/weak + 14-day plan (TZ §10) ───────────

class _TzAnalysis extends StatelessWidget {
  final ScoredResult result;
  const _TzAnalysis({required this.result});

  Color _c(double pct) {
    if (pct >= 80) return AppColors.ok;
    if (pct >= 55) return const Color(0xFFD97706);
    return AppColors.err;
  }

  @override
  Widget build(BuildContext context) {
    final qrs = result.questionResults;
    if (qrs.isEmpty) return const SizedBox.shrink();

    final Map<String, List<QuestionResult>> bySection = {};
    for (final r in qrs) {
      (bySection[r.section] ??= []).add(r);
    }
    final strong = result.topicScores.where((t) => t.pct >= 80).toList();
    final weak = result.topicScores.where((t) => t.pct < 55).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mavzu bo'yicha tahlil (accordion) — TZ §10.1
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                Icon(Icons.checklist_rounded, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Mavzu bo\'yicha tahlil', style: AppTextStyles.labelLarge),
              ]),
            ),
            const Divider(height: 1),
            ...bySection.entries.map((e) {
              final correct = e.value.where((r) => r.correct).length;
              final total = e.value.length;
              final pct = total > 0 ? correct * 100.0 / total : 0.0;
              return Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(e.key,
                      style: AppTextStyles.bodyLarge
                          .copyWith(fontWeight: FontWeight.w700)),
                  trailing: Text('$correct/$total — ${pct.round()}%',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w800,
                          color: _c(pct))),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: e.value.map(_qRow).toList(),
                ),
              );
            }),
          ]),
        ),

        // Kuchli / zaif — TZ §10.2
        if (strong.isNotEmpty || weak.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kuchli va zaif tomonlar',
                  style: AppTextStyles.labelLarge),
              const SizedBox(height: 10),
              if (strong.isNotEmpty) ...[
                _chipRow('Kuchli', strong.map((t) => t.topic).toList(), AppColors.ok),
                const SizedBox(height: 8),
              ],
              if (weak.isNotEmpty)
                _chipRow('Mustahkamlash kerak',
                    weak.map((t) => t.topic).toList(), AppColors.err),
            ]),
          ),
        ],

        // 14 kunlik reja — TZ §10.3
        if (weak.isNotEmpty) ...[
          const SizedBox(height: 16),
          _plan14(weak),
        ],
      ],
    );
  }

  Widget _qRow(QuestionResult r) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(r.correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 16, color: r.correct ? AppColors.ok : AppColors.err),
          const SizedBox(width: 8),
          Expanded(
            child: Text(r.questionText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium),
          ),
          if (r.topic != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border)),
              child: Text(r.topic!,
                  style: const TextStyle(
                      fontFamily: 'Inter', fontSize: 10, color: AppColors.ink3)),
            ),
          ],
        ]),
      );

  Widget _chipRow(String label, List<String> items, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map((t) => Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withValues(alpha: .25))),
                      child: Text(t,
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w600)),
                    ))
                .toList(),
          ),
        ],
      );

  Widget _plan14(List<TopicScore> weak) {
    final f1 = weak.isNotEmpty ? weak[0].topic : 'zaif mavzu';
    final f2 = weak.length > 1 ? weak[1].topic : f1;
    final rows = <(String, String)>[
      ('1–3 kun', 'Eng zaif mavzu: $f1 (15 daqiqa/kun)'),
      ('4–7 kun', 'Ikkinchi mavzu: $f2 (5 ta misol/kun)'),
      ('8–11 kun', 'Aralash mashqlar — barcha mavzularni takrorlash'),
      ('12–14 kun', 'Nazorat testi — natijani solishtirish'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.primary),
          SizedBox(width: 8),
          Text('14 kunlik reja', style: AppTextStyles.labelLarge),
        ]),
        const SizedBox(height: 12),
        ...rows.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 68,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(r.$1,
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(r.$2, style: AppTextStyles.bodyMedium)),
              ]),
            )),
      ]),
    );
  }
}

// ── Report card ────────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final Widget child;
  const _ReportCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

// ── Section head ──────────────────────────────────────────────────────────────

class _SectionHead extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHead({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.secondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.ink3,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

// ── Section row v2 ────────────────────────────────────────────────────────────

class _SectionRowV2 extends StatelessWidget {
  final SectionScore section;
  final int pct;
  final Color color;

  const _SectionRowV2({
    required this.section,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(section.name, style: AppTextStyles.labelLarge),
              ),
              Text(
                '${section.correct}/${section.total}',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: section.total > 0 ? section.correct / section.total : 0,
              backgroundColor: AppColors.gray100,
              color: color,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
