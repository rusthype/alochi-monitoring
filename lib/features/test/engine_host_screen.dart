// lib/features/test/engine_host_screen.dart
// Faza 4b — wires JSON-driven TestEngine into the catalog flow.
//
// Section → math/english payload mapping rules (_buildPayload):
//   TestSpec.subject == "math"     → whole-test totals go to the math field
//   TestSpec.subject == "english"  → whole-test totals go to the english field
//   TestSpec.subject == anything else (e.g. "tarix", "onatili") → both
//     {cor:0, tot:0} — that subject has no top-level bucket of its own, so it
//     doesn't silently pollute the math/english KPIs. Its real score lives
//     only in detail.sections.
//   TestSpec.subject == null (legacy tests authored before this field
//     existed) → the old per-section heuristic (isMathSection):
//       "Math" | starts-with "Matema"  → math field (correct + total)
//       Everything else                → english accumulator (yig'indi)
//     Keeps every pre-existing test's payload byte-identical.
//
// The canonical source of truth is detail.sections (full per-section scores).
// The top-level math/english/vocab fields exist only for legacy panel display.
// vocab is always {cor:0, tot:0} — engine tests don't have a separate vocab section.
//
// Duration default: 60 seconds per answerable question, clamped to [60s, 90min].

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
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

  /// Group id (test↔guruh bog'lanishi, 2026-07-11) — included in the
  /// result payload alongside [group] (name) so the backend can attribute
  /// the result to a specific group unambiguously.
  final String? groupId;
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
    this.groupId,
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

  // ── Payload builder ─────────────────────────────────────────────────────────
  //
  // Maps ScoredResult → the Map<String, dynamic> shape consumed by
  // OfflineQueue.enqueueLocal / api.submitLocalResultFull.
  // math/english top-level are for legacy panel only.
  // detail.sections is the canonical per-section breakdown.

  Map<String, dynamic> _buildPayload(ScoredResult result) {
    final (math, eng) = _resolveMathEngBuckets(result, _spec?.subject);

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
      'group_id': widget.groupId ?? '',
      'student_id': widget.studentId,
      'raw_answers': result.rawAnswers,
      'detail': <String, dynamic>{
        'sections': result.sectionScores
            .map((s) => <String, dynamic>{
                  'name': s.name,
                  'correct': s.correct,
                  'total': s.total,
                  'pct': s.pct,
                })
            .toList(),
        'topics': result.topicScores
            .map((t) => <String, dynamic>{
                  'name': t.topic,
                  'correct': t.correct,
                  'total': t.total,
                  'pct': t.pct,
                })
            .toList(),
        'units': result.unitScores
            .map((t) => <String, dynamic>{
                  'name': t.topic,
                  'correct': t.correct,
                  'total': t.total,
                  'pct': t.pct,
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
      final (math, eng) = _resolveMathEngBuckets(result, _spec?.subject);
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
          content: Text(AppLocalizations.of(context)!.resultNotSavedError),
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
          clientToken: token,
          subject: _spec?.subject,
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
      return _ErrorScaffold(message: AppLocalizations.of(context)!.testLoadFailed);
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

// ── Subject-aware math/english bucketing (Task 1.6 rule) ────────────────────
//
// Single source of truth for "which section(s) count toward the legacy
// top-level math/english fields", shared by _EngineHostScreenState
// (_buildPayload → backend payload, _handleComplete → local HistoryDb write)
// and _EngineResultScreenState (_buildPdfBytes → PDF report + silent
// bot-upload). All three used to re-derive this independently — two of them
// (_handleComplete, _buildPdfBytes) never picked up the subject-aware rule
// when Task 1.6 introduced it, so a Tarix/Ona tili result still showed up as
// "Ingliz tili" in the on-device Offline History screen and in the PDF
// parents/schools actually see. Top-level (not a State method) because both
// State classes need it and neither can call the other's instance methods.
//
//   subject == null      → legacy per-section-name heuristic
//                           (_EngineHostScreenState.isMathSection)
//   subject == 'math'    → every section → math bucket, english stays empty
//   subject == 'english' → every section → english bucket, math stays empty
//   subject == anything else (e.g. "tarix", "onatili") → both buckets stay
//     empty — that subject has no top-level math/english bucket of its own;
//     its real score lives only in detail.sections / topicScores.

/// Splits [result]'s sections into the (math, english) lists per the rule
/// above. List-shaped so _buildPdfBytes can build its per-§ "Matematika"/
/// "Ingliz tili" topic tables from exactly the same decision that produces
/// the header totals below — the two can never contradict each other.
(List<SectionScore> math, List<SectionScore> eng) _resolveMathEngSections(
  ScoredResult result,
  String? subject,
) {
  if (subject == null) {
    // Legacy path — no subject field on the test JSON. Byte-identical to
    // pre-Task-1.6 behaviour.
    final math = <SectionScore>[];
    final eng = <SectionScore>[];
    for (final s in result.sectionScores) {
      (_EngineHostScreenState.isMathSection(s.name) ? math : eng).add(s);
    }
    return (math, eng);
  }
  if (subject == 'math') return (result.sectionScores, const []);
  if (subject == 'english') return (const [], result.sectionScores);
  return (const [], const []);
}

/// Sums a section list into a single {correct,total} aggregate.
_Agg _sumSections(List<SectionScore> sections) {
  int cor = 0, tot = 0;
  for (final s in sections) {
    cor += s.correct;
    tot += s.total;
  }
  return _Agg(cor, tot);
}

/// Scalar convenience over [_resolveMathEngSections] — what _buildPayload
/// and _handleComplete need (a single {correct,total} pair each), without
/// caring about which individual sections went into it.
(_Agg math, _Agg eng) _resolveMathEngBuckets(ScoredResult result, String? subject) {
  final (mathSections, engSections) = _resolveMathEngSections(result, subject);
  return (_sumSections(mathSections), _sumSections(engSections));
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
        title: Text(AppLocalizations.of(context)!.testTitle, style: AppTextStyles.titleMedium),
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
                child: Text(AppLocalizations.of(context)!.backButton),
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
  final String clientToken;

  /// TestSpec.subject (Task 1.6), threaded through from _EngineHostScreenState
  /// so _buildPdfBytes can apply the same subject-aware math/eng bucketing
  /// rule as _buildPayload/_handleComplete instead of silently falling back
  /// to the legacy per-section-name heuristic for every test. Null for
  /// legacy tests without a subject field — see _resolveMathEngSections.
  final String? subject;

  const _EngineResultScreen({
    required this.firstName,
    required this.lastName,
    required this.school,
    this.group,
    required this.grade,
    required this.variant,
    required this.result,
    required this.clientToken,
    this.subject,
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
    _loadAiSummary().then((_) => _autoUploadPdfForBot());
  }

  /// Generates the same PDF the "PDF hisobot" button would (now that the AI
  /// summary has had a chance to load) and uploads it silently so the
  /// parent/teacher Telegram report forwards this exact file. Best-effort —
  /// any failure (offline, upload error) is swallowed; the server falls back
  /// to its own older-format PDF in that case.
  ///
  /// Race condition tuzatish: /result/ submit va PDF upload parallel ishlaydi.
  /// Agar natija DB ga hali yetmagan bo'lsa (404), exponential back-off bilan
  /// qayta uriniladi: 2s → 5s → 10s. Shundan keyin ham bo'lmasa — server-side
  /// fallback PDF bot ga ketadi.
  Future<void> _autoUploadPdfForBot() async {
    Uint8List? bytes;
    try {
      bytes = await _buildPdfBytes();
    } catch (e) {
      debugPrint('_EngineResultScreen._autoUploadPdfForBot: PDF generate xato: $e');
      return;
    }

    const delays = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10)];
    for (var i = 0; i <= delays.length; i++) {
      try {
        final ok = await api.uploadResultPdf(widget.clientToken, bytes);
        if (ok) return; // muvaffaqiyatli yuklandi
        // ok==false → 404 (result hali serverda yo'q) — keyingi urinish
      } catch (e) {
        debugPrint('_EngineResultScreen._autoUploadPdfForBot attempt $i error: $e');
        return; // tarmoq xatosi — qayta urinish ma'nosiz
      }
      if (i < delays.length) {
        debugPrint('_EngineResultScreen._autoUploadPdfForBot: 404, ${delays[i].inSeconds}s kutilmoqda...');
        await Future<void>.delayed(delays[i]);
      }
    }
    debugPrint('_EngineResultScreen._autoUploadPdfForBot: barcha urinishlar tugadi, server fallback ishlaydi.');
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
        studentFirstName: widget.firstName,
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

  String _gradeLabel(BuildContext context, int pct) {
    if (pct >= 90) return AppLocalizations.of(context)!.gradeExcellent;
    if (pct >= 75) return AppLocalizations.of(context)!.gradeGood;
    if (pct >= 55) return AppLocalizations.of(context)!.gradeSatisfactory;
    return AppLocalizations.of(context)!.gradeNeedsPractice;
  }

  /// Builds the result PDF bytes — shared by the "PDF hisobot" button and
  /// the silent bot-upload so both ever produce exactly the same file.
  Future<Uint8List> _buildPdfBytes() async {
    // Same subject-aware decision _buildPayload/_handleComplete use (Task
    // 1.6) — list-shaped here so the per-§ "Matematika"/"Ingliz tili" topic
    // tables below can never disagree with their own header totals (e.g. a
    // Tarix test showing "Ingliz tili: 0/0" as the header but still listing
    // its real sections underneath, contradicting itself).
    final (mathSections, engSections) =
        _resolveMathEngSections(widget.result, widget.subject);
    final mathTopics = mathSections
        .map((s) => MapEntry(s.name, (ok: s.correct, tot: s.total)))
        .toList();
    final engTopics = engSections
        .map((s) => MapEntry(s.name, (ok: s.correct, tot: s.total)))
        .toList();
    final math = _sumSections(mathSections);
    final eng = _sumSections(engSections);

    // Per-§ / per-topic breakdown + AI summary for the TZ §11 passport.
    final topicScores = widget.result.topicScores
        .map((t) => MapEntry(t.topic, (ok: t.correct, tot: t.total)))
        .toList();

    return PdfService.generateResultPdf(
      firstName: widget.firstName,
      lastName: widget.lastName,
      group: widget.group ?? '',
      grade: widget.grade,
      variant: widget.variant,
      mathOk: math.correct,
      mathTotal: math.total,
      engOk: eng.correct,
      engTotal: eng.total,
      pct: widget.result.totalPct.round(),
      mathTopics: mathTopics,
      engTopics: engTopics,
      topicScores: topicScores,
      aiSummary: _aiSummary,
    );
  }

  Future<void> _generatePdf() async {
    if (_pdfGenerating) return;
    setState(() => _pdfGenerating = true);
    try {
      final bytes = await _buildPdfBytes();
      String? path;
      if (!Platform.isIOS && !Platform.isAndroid) {
        try {
          final dir = await getDownloadsDirectory();
          if (dir != null) {
            final testPath = '${dir.path}/result_${widget.firstName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
            await File(testPath).writeAsBytes(bytes);
            path = testPath;
          }
        } catch (_) {}
      }
      
      if (path == null) {
        final fallbackDir = await getApplicationSupportDirectory();
        path = '${fallbackDir.path}/result_${widget.firstName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await File(path).writeAsBytes(bytes);
      }

      if (mounted) setState(() => _pdfPath = path);
      final openResult = await OpenFilex.open(path);
      if (openResult.type != ResultType.done) {
        debugPrint(
          '_EngineResultScreen._generatePdf open failed: '
          '${openResult.type} — ${openResult.message}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF saqlandi, lekin ochib bo\'lmadi'),
              backgroundColor: AppColors.err,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
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
    final gradeLabel = _gradeLabel(context, pct);
    final studentName = '${widget.firstName} ${widget.lastName}';
    final subLine =
        '${widget.group?.isNotEmpty == true ? widget.group! : widget.school} · Variant ${widget.variant}';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(AppLocalizations.of(context)!.resultTitle, style: AppTextStyles.titleMedium),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(AppLocalizations.of(context)!.nextStudent),
          ),
          TextButton.icon(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            icon: const Icon(Icons.home_rounded, size: 18),
            label: Text(AppLocalizations.of(context)!.homePage),
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
                          label: AppLocalizations.of(context)!.correctAnswersWithCount(correct.toString()),
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.cancel_rounded,
                          label: AppLocalizations.of(context)!.wrongAnswersWithCount(wrong.toString()),
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
                              label: AppLocalizations.of(context)!.shieldsCount(result.shields.toString()),
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
                    _SectionHead(
                      icon: Icons.bar_chart_rounded,
                      label: AppLocalizations.of(context)!.sectionsByTitle,
                    ),
                    const SizedBox(height: 8),
                    if (result.sectionScores.isEmpty)
                      Text(AppLocalizations.of(context)!.noDataAvailable, style: AppTextStyles.bodyMedium)
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
                  _pdfPath != null ? AppLocalizations.of(context)!.reopenPdf : AppLocalizations.of(context)!.pdfReportButton,
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
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.aiAnalysisTitle, style: AppTextStyles.labelLarge),
          ]),
          const SizedBox(height: 12),
          if (loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(AppLocalizations.of(context)!.analysisPreparing,
                      style: AppTextStyles.bodyMedium),
                ),
              ]),
            )
          else ...[
            if (summary.isNotEmpty)
              Text(summary, style: AppTextStyles.bodyLarge.copyWith(height: 1.4)),
            if (strengths.isNotEmpty) ...[
              const SizedBox(height: 14),
              _block(AppLocalizations.of(context)!.strongSidesTitle, strengths,
                  Icons.check_circle_rounded, AppColors.ok),
            ],
            if (weaknesses.isNotEmpty) ...[
              const SizedBox(height: 14),
              _block(AppLocalizations.of(context)!.weakSidesTitle, weaknesses, Icons.error_rounded,
                  AppColors.err),
            ],
            if (recs.isNotEmpty) ...[
              const SizedBox(height: 14),
              _block(AppLocalizations.of(context)!.recommendationsTitle, recs, Icons.lightbulb_rounded,
                  const Color(0xFFD97706)),
            ],
            if (focus.isNotEmpty) ...[
              const SizedBox(height: 14),
              _block(AppLocalizations.of(context)!.focus14DaysTitle, focus,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(children: [
                const Icon(Icons.checklist_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.subjectAnalysisByTopic, style: AppTextStyles.labelLarge),
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

        // Unitlar bo'yicha tahlil
        if (result.unitScores.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(children: [
                  const Icon(Icons.layers_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.subjectAnalysisByUnit, style: AppTextStyles.labelLarge),
                ]),
              ),
              const Divider(height: 1),
              ...result.unitScores.map((u) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(u.topic, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      Text('${u.correct}/${u.total} — ${u.pct.round()}%',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w800,
                              color: _c(u.pct))),
                    ],
                  ),
                );
              }),
            ]),
          ),
        ],

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
              Text(AppLocalizations.of(context)!.strongAndWeakSides,
                  style: AppTextStyles.labelLarge),
              const SizedBox(height: 10),
              if (strong.isNotEmpty) ...[
                _chipRow(AppLocalizations.of(context)!.strongLabel, strong.map((t) => t.topic).toList(), AppColors.ok),
                const SizedBox(height: 8),
              ],
              if (weak.isNotEmpty)
                _chipRow(AppLocalizations.of(context)!.needsReinforcement,
                    weak.map((t) => t.topic).toList(), AppColors.err),
            ]),
          ),
        ],

        // 14 kunlik reja — TZ §10.3
        if (weak.isNotEmpty) ...[
          const SizedBox(height: 16),
          _plan14(context, weak),
        ],
      ],
    );
  }

  Widget _qRow(QuestionResult r) {
    // Generate some color based on the topic string
    final String topic = r.topic ?? r.category ?? r.section;
    final int hash = topic.hashCode;
    
    // Choose a color palette similar to the HTML tags (t-h, t-a, t-s, etc)
    final colors = [
      (const Color(0xFF1B5E20), const Color(0xFFE8F5E9)), // green
      (const Color(0xFF4A148C), const Color(0xFFEDE7F6)), // purple
      (const Color(0xFFE65100), const Color(0xFFFFF3E0)), // orange
      (const Color(0xFF0D47A1), const Color(0xFFE3F2FD)), // blue
      (const Color(0xFF880E4F), const Color(0xFFFCE4EC)), // pink
      (const Color(0xFF006064), const Color(0xFFE0F7FA)), // cyan
      (const Color(0xFFBF360C), const Color(0xFFFBE9E7)), // deep orange
    ];
    final colorPair = colors[hash.abs() % colors.length];

    final questionText = r.questionText;
    final opts = r.question.opts;
    final correctAnsIndex = r.question.ans;
    final userAns = r.userAnswer;
    int? userAnsIndex;
    if (userAns is int) {
      userAnsIndex = userAns;
    } else if (userAns is String) {
      userAnsIndex = int.tryParse(userAns);
      userAnsIndex ??= opts.indexWhere((o) => o == userAns);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(7),
            ),
            alignment: Alignment.center,
            child: Text('${r.index + 1}',
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: colorPair.$2,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(topic,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: colorPair.$1)),
                ),
                const SizedBox(height: 4),
                Text(questionText,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.5)),
                if (r.question.svg != null && r.question.svg!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SvgPicture.string(r.question.svg!, height: 80, fit: BoxFit.contain),
                ],
                if (opts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Column(
                    children: opts.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final optText = entry.value;
                      final isCorrectOpt = idx == correctAnsIndex;
                      final isSelectedOpt = idx == userAnsIndex;

                      if (!isCorrectOpt && !isSelectedOpt) return const SizedBox.shrink();

                      Color borderColor = AppColors.border;
                      Color bgColor = AppColors.surface;
                      Color textColor = AppColors.ink1;
                      Color labelBg = AppColors.bg;
                      Color labelColor = AppColors.ink2;

                      if (isCorrectOpt) {
                        borderColor = AppColors.ok;
                        bgColor = const Color(0xFFECFDF5);
                        textColor = AppColors.ok;
                        labelBg = AppColors.ok;
                        labelColor = Colors.white;
                      } else if (isSelectedOpt && !isCorrectOpt) {
                        borderColor = AppColors.err;
                        bgColor = const Color(0xFFFEF2F2);
                        textColor = AppColors.err;
                        labelBg = AppColors.err;
                        labelColor = Colors.white;
                      }

                      final label = String.fromCharCode(65 + idx); // A, B, C, D

                      return Container(
                        margin: const EdgeInsets.only(bottom: 5),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: labelBg,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              alignment: Alignment.center,
                              child: Text(label,
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: labelColor)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(optText,
                                  style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textColor)),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _plan14(BuildContext context, List<TopicScore> weak) {
    final f1 = weak.isNotEmpty ? weak[0].topic : AppLocalizations.of(context)!.weakTopicFallback;
    final f2 = weak.length > 1 ? weak[1].topic : f1;
    final rows = <(String, String)>[
      (AppLocalizations.of(context)!.days1to3, AppLocalizations.of(context)!.weakestTopicPlan(f1)),
      (AppLocalizations.of(context)!.days4to7, AppLocalizations.of(context)!.secondTopicPlan(f2)),
      (AppLocalizations.of(context)!.days8to11, AppLocalizations.of(context)!.mixedExercisesPlan),
      (AppLocalizations.of(context)!.days12to14, AppLocalizations.of(context)!.controlTestPlan),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(AppLocalizations.of(context)!.plan14DaysTitle, style: AppTextStyles.labelLarge),
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
