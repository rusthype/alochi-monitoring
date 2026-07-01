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

    // 4. Navigate to result display.
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

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
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

  String _aiSummary(int pct, List<SectionScore> weak) {
    if (pct >= 80) {
      return "${widget.firstName} yaxshi natija ($pct%) ko'rsatdi. "
          "Zaif bo'limlarni mustahkamlasa, keyingi testda 90%+ ga erishishi mumkin! 🎯";
    }
    final weakNames = weak.take(2).map((w) => w.name).join(', ');
    final weakPart =
        weak.isNotEmpty ? " $weakNames bo'limlarida qiynalmoqda." : '';
    return "${widget.firstName} $pct% natija ko'rsatdi.$weakPart "
        "14 kunlik reja bajarilsa, 2–3 haftada sezilarli o'zgarish bo'ladi! 📚";
  }

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

              const SizedBox(height: 12),

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

              const SizedBox(height: 12),

              // ── 5. 14 kunlik reja ─────────────────────────────────────────
              _ReportCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHead(
                      icon: Icons.calendar_month_rounded,
                      label: '14 KUNLIK REJA',
                    ),
                    const SizedBox(height: 8),
                    _PlanRow(
                      days: '1–3 KUN',
                      title: weak.isNotEmpty
                          ? '${weak[0].name} takrorlash'
                          : "Barcha bo'limlar takrorlash",
                      desc: 'Har kuni 15 daqiqa mashq',
                    ),
                    _PlanRow(
                      days: '4–7 KUN',
                      title: weak.length > 1
                          ? '${weak[1].name} mashqlari'
                          : 'Mustahkamlash mashqlari',
                      desc: 'Har kuni 5 ta misol yechish',
                    ),
                    const _PlanRow(
                      days: '8–11 KUN',
                      title: 'Aralash mashqlar',
                      desc: "Barcha bo'limlarni takrorlash",
                    ),
                    const _PlanRow(
                      days: '12–14 KUN',
                      title: 'Nazorat testi',
                      desc: 'Natijalarni solishtirish',
                      isLast: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── 6. AI xulosa ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.secondaryMuted,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.secondary.withValues(alpha: .25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded,
                            size: 18, color: AppColors.secondary),
                        const SizedBox(width: 8),
                        Text(
                          'AI XULOSA',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _aiSummary(pct, weak),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.ink1,
                        height: 1.6,
                      ),
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

// ── Plan row ──────────────────────────────────────────────────────────────────

class _PlanRow extends StatelessWidget {
  final String days;
  final String title;
  final String desc;
  final bool isLast;

  const _PlanRow({
    required this.days,
    required this.title,
    required this.desc,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.secondaryMuted,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: AppColors.secondary.withValues(alpha: .3)),
            ),
            child: Text(
              days,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.secondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(desc, style: AppTextStyles.bodyMedium),
              ],
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
