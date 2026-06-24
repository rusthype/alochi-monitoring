// lib/features/diagnostic/diagnostic_host_screen.dart
// Combined diagnostic runner: math phase → english phase → PassportScreen.
// Submits combined payload to offline queue like EngineHostScreen.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_client.dart';
import '../../core/db/history_db.dart';
import '../../core/db/offline_queue.dart';
import '../../core/engine/test_engine.dart';
import '../../core/engine/test_models.dart';
import '../../core/engine/test_scorer.dart';
import '../../core/sync/sync_service.dart';
import '../../shared/theme/app_theme.dart';
import 'passport_screen.dart';

enum _DiagPhase { math, transition, english }

class DiagnosticHostScreen extends StatefulWidget {
  final Map<String, dynamic> mathTestData;
  final Map<String, dynamic> engTestData;
  final int variant;
  final String firstName;
  final String lastName;
  final String school;
  final String? group;
  final int grade;

  const DiagnosticHostScreen({
    super.key,
    required this.mathTestData,
    required this.engTestData,
    required this.variant,
    required this.firstName,
    required this.lastName,
    required this.school,
    this.group,
    required this.grade,
  });

  @override
  State<DiagnosticHostScreen> createState() =>
      _DiagnosticHostScreenState();
}

class _DiagnosticHostScreenState extends State<DiagnosticHostScreen> {
  TestSpec? _mathSpec;
  TestSpec? _engSpec;
  String? _parseError;

  _DiagPhase _phase = _DiagPhase.math;
  ScoredResult? _mathResult;

  Timer? _heartbeatTimer;
  late final String _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = const Uuid().v4();
    _parseSpecs();
    _startHeartbeat();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  void _parseSpecs() {
    try {
      final mathBlob = (widget.mathTestData['test_data'] is Map)
          ? Map<String, dynamic>.from(
              widget.mathTestData['test_data'] as Map)
          : widget.mathTestData;
      _mathSpec = TestSpec.fromJson(mathBlob);

      final engBlob = (widget.engTestData['test_data'] is Map)
          ? Map<String, dynamic>.from(
              widget.engTestData['test_data'] as Map)
          : widget.engTestData;
      _engSpec = TestSpec.fromJson(engBlob);
    } catch (e) {
      _parseError = 'Test yuklanmadi: $e';
    }
  }

  Duration _duration(TestSpec spec) {
    final sections =
        spec.sectionsForVariant(widget.variant.toString());
    final totalQs =
        sections.fold(0, (sum, s) => sum + s.questionCount);
    final secs = (totalQs * 60).clamp(60, 90 * 60);
    return Duration(seconds: secs);
  }

  void _ping(String status, String testKey) {
    api.pingSession(
      sessionId: _sessionId,
      testKey: testKey,
      schoolCode: widget.school,
      name: '${widget.lastName} ${widget.firstName}',
      variant: widget.variant,
      status: status,
    );
  }

  void _startHeartbeat() {
    final key = _mathSpec?.testKey ?? 'diag_combined_${widget.grade}';
    _ping('active', key);
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
      _ping('active',
          _phase == _DiagPhase.math
              ? (_mathSpec?.testKey ?? '')
              : (_engSpec?.testKey ?? ''));
    });
  }

  void _onMathComplete(ScoredResult result) {
    _mathResult = result;
    setState(() => _phase = _DiagPhase.transition);
    // Auto-advance to english after brief delay
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _phase = _DiagPhase.english);
    });
  }

  Future<void> _onEngComplete(ScoredResult engResult) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    final mathResult = _mathResult!;
    final mathCor = mathResult.totalCorrect;
    final mathTot = mathResult.totalQuestions;
    final engCor = engResult.totalCorrect;
    final engTot = engResult.totalQuestions;
    final totalTot = mathTot + engTot;
    final totalPct =
        totalTot > 0 ? (mathCor + engCor) * 100.0 / totalTot : 0.0;

    final testKey = 'diag_combined_${widget.grade}';

    final payload = <String, dynamic>{
      'name': '${widget.lastName} ${widget.firstName}',
      'grade': widget.grade,
      'variant': widget.variant.toString(),
      'source': 'flutter',
      'math': {'cor': mathCor, 'tot': mathTot},
      'english': {'cor': engCor, 'tot': engTot},
      'vocab': {'cor': 0, 'tot': 0},
      'pct': totalPct.round(),
      'school_code': widget.school,
      'test_key': testKey,
      'detail': <String, dynamic>{
        'sections': [
          ...mathResult.sectionScores.map((s) => <String, dynamic>{
                'name': s.name,
                'correct': s.correct,
                'total': s.total,
                'pct': s.pct,
                'subject': 'math',
              }),
          ...engResult.sectionScores.map((s) => <String, dynamic>{
                'name': s.name,
                'correct': s.correct,
                'total': s.total,
                'pct': s.pct,
                'subject': 'english',
              }),
        ],
        'test_key': testKey,
        'math_test_key': _mathSpec?.testKey ?? '',
        'eng_test_key': _engSpec?.testKey ?? '',
      },
    };

    final token = newIdempotencyToken();

    try {
      await HistoryDb.insertResult(
        firstName: widget.firstName,
        lastName: widget.lastName,
        school: widget.school,
        gradeGroup: widget.group ?? '',
        mathScore: mathCor,
        engScore: engCor,
        totalPct: totalPct,
      );
    } catch (e) {
      debugPrint('DiagnosticHostScreen HistoryDb error: $e');
    }

    try {
      await OfflineQueue.enqueueLocal(payload, token);
    } catch (e) {
      debugPrint('DiagnosticHostScreen enqueueLocal error: $e');
    }

    SyncService.instance.flushNow().catchError((e) {
      debugPrint('DiagnosticHostScreen flushNow error: $e');
      return Future<void>.value();
    });

    _ping('finished', testKey);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PassportScreen(
          firstName: widget.firstName,
          lastName: widget.lastName,
          school: widget.school,
          group: widget.group,
          grade: widget.grade,
          variant: widget.variant,
          mathResult: mathResult,
          engResult: engResult,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_parseError != null) {
      return _errorScaffold(_parseError!);
    }
    if (_mathSpec == null || _engSpec == null) {
      return _errorScaffold('Test yuklanmadi');
    }

    if (_phase == _DiagPhase.transition) {
      return _TransitionScreen(
        firstName: widget.firstName,
        mathResult: _mathResult!,
      );
    }

    if (_phase == _DiagPhase.math) {
      return TestEngine(
        spec: _mathSpec!,
        variant: widget.variant,
        firstName: widget.firstName,
        lastName: widget.lastName,
        school: widget.school,
        group: widget.group,
        duration: _duration(_mathSpec!),
        onComplete: _onMathComplete,
      );
    }

    return TestEngine(
      spec: _engSpec!,
      variant: widget.variant,
      firstName: widget.firstName,
      lastName: widget.lastName,
      school: widget.school,
      group: widget.group,
      duration: _duration(_engSpec!),
      onComplete: _onEngComplete,
    );
  }

  Widget _errorScaffold(String message) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: const BackButton(color: AppColors.ink1),
        title: const Text('Diagnostik test',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink1)),
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
              Text(message,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyLarge
                      .copyWith(color: AppColors.ink2)),
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

// ── Transition screen between math and english ────────────────────────────────

class _TransitionScreen extends StatelessWidget {
  final String firstName;
  final ScoredResult mathResult;

  const _TransitionScreen({
    required this.firstName,
    required this.mathResult,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.math.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded,
                    size: 48, color: AppColors.math),
              ),
              const SizedBox(height: 20),
              const Text(
                'Matematika tugadi!',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink1),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${mathResult.totalCorrect}/${mathResult.totalQuestions} '
                '(${mathResult.totalPct.round()}%)',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.math),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.eng.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.eng.withValues(alpha: .3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.translate_rounded,
                        color: AppColors.eng, size: 22),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Keyingi: Ingliz tili',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.eng),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tayyorlaning...',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.eng
                                  .withValues(alpha: .7)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.brand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
