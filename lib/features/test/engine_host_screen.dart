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

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:uuid/uuid.dart';

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
    this.duration,
  });

  @override
  State<EngineHostScreen> createState() => _EngineHostScreenState();
}

class _EngineHostScreenState extends State<EngineHostScreen> {
  TestSpec? _spec;
  String? _parseError;

  late final String _sessionId;
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _sessionId = const Uuid().v4();
    _parseSpec();
    _startHeartbeat();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  String get _testKey =>
      _spec?.testKey ??
      widget.testData['test_key']?.toString() ??
      '';

  void _ping(String status) {
    api.pingSession(
      sessionId: _sessionId,
      testKey: _testKey,
      schoolCode: widget.school,
      name: '${widget.lastName} ${widget.firstName}',
      variant: widget.variant,
      status: status,
    );
  }

  void _startHeartbeat() {
    _ping('active');
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _ping('active');
    });
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
      'grade': _spec?.grade ?? 0,
      'variant': widget.variant.toString(),
      'source': 'flutter',
      'math': {'cor': math.correct, 'tot': math.total},
      'english': {'cor': eng.correct, 'tot': eng.total},
      'vocab': {'cor': 0, 'tot': 0},
      'pct': result.totalPct.round(),
      'school_code': widget.school,
      'test_key': result.testKey,
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _ping('finished');

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Natija saqlanmadi')),
        );
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
          grade: _spec?.grade ?? 0,
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

  Color _scoreColor(double pct) {
    if (pct >= 90) return AppColors.ok;
    if (pct >= 60) return const Color(0xFFD97706); // warning amber
    return AppColors.err;
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
    final pct = widget.result.totalPct;
    final color = _scoreColor(pct);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Natija', style: AppTextStyles.titleMedium),
        actions: [
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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Score card ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: pct / 100,
                              strokeWidth: 10,
                              backgroundColor: AppColors.gray100,
                              color: color,
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${pct.round()}%',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                              Text(
                                '${widget.result.totalCorrect}/'
                                '${widget.result.totalQuestions}',
                                style: AppTextStyles.bodyMedium,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${widget.lastName} ${widget.firstName}',
                      style: AppTextStyles.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.school.isNotEmpty
                          ? '${widget.school} · Variant ${widget.variant}'
                          : 'Variant ${widget.variant}',
                      style: AppTextStyles.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (widget.result.shields != null ||
                        widget.result.levelLabel != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          if (widget.result.shields != null)
                            _BadgeChip(
                              icon: Icons.shield_rounded,
                              label: '${widget.result.shields} qalqon',
                              color: AppColors.primary,
                            ),
                          if (widget.result.levelLabel != null)
                            _BadgeChip(
                              icon: Icons.military_tech_rounded,
                              label: widget.result.levelLabel!,
                              color: AppColors.ok,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Per-section breakdown ─────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Row(
                        children: [
                          Icon(Icons.bar_chart_rounded,
                              size: 18, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text(
                            'Bo\'limlar bo\'yicha',
                            style: AppTextStyles.labelLarge,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (widget.result.sectionScores.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Ma\'lumot yo\'q',
                          style: AppTextStyles.bodyMedium,
                        ),
                      )
                    else
                      ...widget.result.sectionScores.map((s) => _SectionRow(s)),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── PDF button ────────────────────────────────────────────────
              ElevatedButton.icon(
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
                    : const Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 20,
                      ),
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

// ── Section row ────────────────────────────────────────────────────────────────

class _SectionRow extends StatelessWidget {
  final SectionScore section;
  const _SectionRow(this.section);

  Color _color(double pct) {
    if (pct >= 90) return AppColors.ok;
    if (pct >= 60) return const Color(0xFFD97706);
    return AppColors.err;
  }

  @override
  Widget build(BuildContext context) {
    final pct = section.pct;
    final color = _color(pct);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                '${pct.round()}%',
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
