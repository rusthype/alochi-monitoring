// lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart
//
// CAT (adaptive) test runner — new, no existing screen pattern fits since
// the CAT engine is server-adaptive and drives one question at a time.
// Flow: availableSubjects(grade) -> startAttempt(first subject) -> loop
// submitAnswer -> render next question, or startAttempt(next_subject) on a
// subject transition, or navigate to the finished screen when done.
//
// Backend contract (alochi_backend/apps/diagnostic/views.py, CATStartView /
// CATAnswerView / _build_cat_question_response): the question dict carries
// flat option_a..option_d keys (already per-attempt shuffled) plus optional
// image_url/svg_visual, and POST cat/answer/ requires `selected` to be
// exactly "A"|"B"|"C"|"D".
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart' show ApiException;
import '../../../core/engine/question_widgets.dart' show EngineOptionRow;
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_network_image.dart';
import '../data/diagnostic_kiosk_api.dart';
import '../widgets/diagnostic_widgets.dart';

/// One rendered answer option: `key` is "A".."D", `text` is the display
/// string for that letter (already de/re-shuffled server-side).
class DiagnosticOptionItem {
  final String key;
  final String text;
  const DiagnosticOptionItem({required this.key, required this.text});
}

List<DiagnosticOptionItem> extractDiagnosticOptions(Map<String, dynamic> q) {
  final items = <DiagnosticOptionItem>[];
  for (final letter in ['A', 'B', 'C', 'D']) {
    final lowerKey = 'option_${letter.toLowerCase()}';
    final text = (q[lowerKey] ?? q[letter] ?? '').toString().trim();
    if (text.isNotEmpty) {
      items.add(DiagnosticOptionItem(key: letter, text: text));
    }
  }
  return items;
}

/// Pending "subject A finished, subject B starting" state — shown as a brief
/// full-screen message instead of jumping straight to the next question.
class _SubjectTransition {
  final String from;
  final String to;
  const _SubjectTransition({required this.from, required this.to});
}

typedef DiagnosticAvailableSubjectsFn = Future<Map<String, dynamic>> Function(
    int grade);
typedef DiagnosticStartAttemptFn = Future<Map<String, dynamic>> Function({
  required String attemptId,
  required String subject,
});
typedef DiagnosticSubmitAnswerFn = Future<Map<String, dynamic>> Function({
  required String attemptId,
  required String questionId,
  required String selected,
});

class DiagnosticTestRunnerScreen extends StatefulWidget {
  final String attemptId;
  final String studentName;
  final int grade;

  /// Test-only overrides — default to the real [diagnosticKioskApi] methods.
  /// `diagnosticKioskApi` is a bare top-level singleton with no injectable
  /// HTTP client, so this is the smallest seam that lets widget tests fake
  /// network responses without touching that file.
  final DiagnosticAvailableSubjectsFn? availableSubjectsOverride;
  final DiagnosticStartAttemptFn? startAttemptOverride;
  final DiagnosticSubmitAnswerFn? submitAnswerOverride;

  const DiagnosticTestRunnerScreen({
    super.key,
    required this.attemptId,
    required this.studentName,
    required this.grade,
    this.availableSubjectsOverride,
    this.startAttemptOverride,
    this.submitAnswerOverride,
  });

  @override
  State<DiagnosticTestRunnerScreen> createState() =>
      _DiagnosticTestRunnerScreenState();
}

class _DiagnosticTestRunnerScreenState
    extends State<DiagnosticTestRunnerScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Map<String, dynamic>? _question;
  String? _selectedOption;
  int _position = 0;
  int _total = 0;
  String _currentSubject = '';
  _SubjectTransition? _transition;

  DiagnosticAvailableSubjectsFn get _availableSubjects =>
      widget.availableSubjectsOverride ?? diagnosticKioskApi.availableSubjects;
  DiagnosticStartAttemptFn get _startAttemptCall =>
      widget.startAttemptOverride ?? diagnosticKioskApi.startAttempt;
  DiagnosticSubmitAnswerFn get _submitAnswerCall =>
      widget.submitAnswerOverride ?? diagnosticKioskApi.submitAnswer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final subjectsResp = await _availableSubjects(widget.grade);
      final subjects = (subjectsResp['subjects'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          [];
      if (subjects.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = "Fanlar ro'yxati bo'sh";
        });
        return;
      }
      await _startSubject(subjects.first);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  Future<void> _startSubject(String subject) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedOption = null;
      _transition = null;
      _currentSubject = subject;
    });
    try {
      final resp = await _startAttemptCall(
        attemptId: widget.attemptId,
        subject: subject,
      );
      if (!mounted) return;
      setState(() {
        _question = _extractQuestion(resp);
        _position = (resp['position'] as num?)?.toInt() ?? 1;
        _total = (resp['total_questions'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  Future<void> _submit() async {
    final q = _question;
    final selected = _selectedOption;
    if (q == null || selected == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final resp = await _submitAnswerCall(
        attemptId: widget.attemptId,
        questionId: _questionId(q),
        selected: selected,
      );
      final finished = resp['finished'] == true;
      final nextSubject = (resp['next_subject'] ?? '').toString();
      if (finished && nextSubject.isEmpty) {
        if (!mounted) return;
        context.pushReplacement('/diagnostic_finished');
        return;
      }
      if (finished && nextSubject.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _transition = _SubjectTransition(
            from: _currentSubject,
            to: nextSubject,
          );
        });
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        await _startSubject(nextSubject);
      } else {
        final next = _extractQuestion(resp);
        if (!mounted) return;
        setState(() {
          _question = next;
          _selectedOption = null;
          _position = (resp['position'] as num?)?.toInt() ?? _position;
          _total = (resp['total_questions'] as num?)?.toInt() ?? _total;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Map<String, dynamic>? _extractQuestion(Map<String, dynamic> data) {
    final nested = data['question'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    if (data['id'] != null || data['question_id'] != null) return data;
    return null;
  }

  String _questionId(Map<String, dynamic> q) =>
      (q['id'] ?? q['question_id'] ?? '').toString();

  String _questionText(Map<String, dynamic> q) =>
      (q['text'] ?? q['prompt'] ?? q['question_text'] ?? '').toString();

  String _subjectLabel(AppLocalizations l10n, String subject) {
    switch (subject) {
      case 'math':
        return l10n.mathSubjectFull;
      case 'english':
        return l10n.englishSubjectFull;
      default:
        return subject;
    }
  }

  Color _subjectColor(String subject) {
    switch (subject) {
      case 'math':
        return AppColors.math;
      case 'english':
        return AppColors.eng;
      default:
        return AppColors.brand;
    }
  }

  IconData _subjectIcon(String subject) {
    switch (subject) {
      case 'math':
        return Icons.calculate_rounded;
      case 'english':
        return Icons.translate_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final q = _question;
    final transition = _transition;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: transition != null
            ? _buildTransitionView(l10n, transition)
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView(l10n)
                    : q == null
                        ? Center(child: Text(l10n.diagnosticNoStudents))
                        : _buildQuestionView(l10n, q),
      ),
    );
  }

  Widget _buildTransitionView(
      AppLocalizations l10n, _SubjectTransition transition) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          l10n.diagnosticSubjectTransitionMessage(
            _subjectLabel(l10n, transition.from),
            _subjectLabel(l10n, transition.to),
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.ink1,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_rounded, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _bootstrap, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    final color = _subjectColor(_currentSubject);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_subjectIcon(_currentSubject), size: 16, color: color),
                  const SizedBox(width: 6),
                  Text(
                    _subjectLabel(l10n, _currentSubject),
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
            Text(
              l10n.diagnosticQuestionCounter(_position, _total),
              style: const TextStyle(
                  color: AppColors.ink3,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _total > 0 ? (_position / _total).clamp(0.0, 1.0) : 0,
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(AppColors.brand),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.studentName,
          style: const TextStyle(color: AppColors.ink3, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildQuestionView(AppLocalizations l10n, Map<String, dynamic> q) {
    final imageUrl = (q['image_url'] ?? '').toString().trim();
    final svgVisual = (q['svg_visual'] ?? '').toString().trim();
    final options = extractDiagnosticOptions(q);
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(l10n),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _questionText(q),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink1,
                            ),
                          ),
                          if (imageUrl.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            AppNetworkImage(
                              url: imageUrl,
                              height: 260,
                              fit: BoxFit.contain,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ] else if (svgVisual.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            SvgPicture.string(svgVisual,
                                height: 130, fit: BoxFit.contain),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...options.map((opt) => EngineOptionRow(
                          label: opt.key,
                          text: opt.text,
                          selected: _selectedOption == opt.key,
                          onTap: _submitting
                              ? () {}
                              : () =>
                                  setState(() => _selectedOption = opt.key),
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: DiagnosticBottomCta(
            label: l10n.continueButton,
            enabled: _selectedOption != null,
            loading: _submitting,
            onTap: _submit,
          ),
        ),
      ],
    );
  }
}
