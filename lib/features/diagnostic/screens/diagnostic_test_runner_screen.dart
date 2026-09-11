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
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart' show ApiException;
import '../../../core/services/heartbeat_service.dart';
import '../../../core/services/proctor_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_kiosk_api.dart';
import '../widgets/diagnostic_bottom_nav.dart';
import '../widgets/diagnostic_header_bar.dart';
import '../widgets/diagnostic_option_card.dart';
import '../widgets/diagnostic_question_card.dart';
import '../widgets/diagnostic_question_dots.dart';
import '../../../core/utils/student_name_formatter.dart';

/// Max width of the centered content dock (question card and the floating
/// bottom-nav panel both clamp to this) for the fixed-variant redesign.
const double _kDockMaxWidth = 760;

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
    int grade, {
  String language,
});
typedef DiagnosticStartAttemptFn = Future<Map<String, dynamic>> Function({
  required String attemptId,
  required String subject,
});
typedef DiagnosticSubmitAnswerFn = Future<Map<String, dynamic>> Function({
  required String attemptId,
  required String questionId,
  required String selected,
});
typedef DiagnosticFinishAttemptFn = Future<Map<String, dynamic>> Function({
  required String attemptId,
  required List<Map<String, dynamic>> answers,
});

class DiagnosticTestRunnerScreen extends StatefulWidget {
  final String attemptId;

  /// Raw roster name (NOT patronymic-stripped) — this is what
  /// [HeartbeatService.startTest] sends as the live-monitoring identity, so
  /// it must keep whatever the backend uses to disambiguate same-name
  /// classmates. Formatted only where actually displayed on-screen (see
  /// `_buildHeader`).
  final String studentName;
  final int grade;
  final String schoolCode;
  final String language;

  /// Test-only overrides — default to the real [diagnosticKioskApi] methods.
  /// `diagnosticKioskApi` is a bare top-level singleton with no injectable
  /// HTTP client, so this is the smallest seam that lets widget tests fake
  /// network responses without touching that file.
  final DiagnosticAvailableSubjectsFn? availableSubjectsOverride;
  final DiagnosticStartAttemptFn? startAttemptOverride;
  final DiagnosticSubmitAnswerFn? submitAnswerOverride;
  final DiagnosticFinishAttemptFn? finishAttemptOverride;

  const DiagnosticTestRunnerScreen({
    super.key,
    required this.attemptId,
    required this.studentName,
    required this.grade,
    this.schoolCode = '',
    required this.language,
    this.availableSubjectsOverride,
    this.startAttemptOverride,
    this.submitAnswerOverride,
    this.finishAttemptOverride,
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
  bool _subjectsEmpty = false;
  Map<String, dynamic>? _question;
  String? _selectedOption;
  int _position = 0;
  int _total = 0;
  String _currentSubject = '';
  _SubjectTransition? _transition;

  /// Local UI-only bookmark state, keyed by question_id (YAGNI — no backend
  /// field/API call, see DiagnosticQuestionCard's doc comment).
  final Set<String> _flaggedQuestionIds = <String>{};

  /// Countdown seconds remaining, or null when the current attempt carries
  /// no known duration. Populated from `duration_minutes` on the
  /// start-attempt response only (see _startSubject) — per-question answer
  /// responses also carry the same value but must not reset the timer.
  int? _remainingSeconds;
  Timer? _timer;

  /// Whether the current attempt is the fixed-variant math bank (all
  /// questions known upfront, supports prev/next/grid/finish nav) vs the
  /// CAT engine's adaptive one-question-at-a-time flow. Set from the
  /// backend's `is_fixed_variant` field on every start/answer response.
  bool _isFixedVariant = false;

  /// Full question set for a fixed-variant/full-package attempt (populated
  /// once from the start response's `questions` array) and the answers
  /// picked so far, keyed by 1-indexed position. Purely local state — once
  /// populated, prev/next/jump/select never hit the network again.
  List<Map<String, dynamic>> _questions = [];
  final Map<int, String> _answers = {};

  void _startCountdownIfNeeded(Map<String, dynamic> resp) {
    final minutes = (resp['duration_minutes'] as num?)?.toInt();
    _timer?.cancel();
    _timer = null;
    if (minutes == null) {
      setState(() => _remainingSeconds = null);
      return;
    }
    setState(() => _remainingSeconds = minutes * 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = _remainingSeconds;
      if (remaining == null) {
        timer.cancel();
        return;
      }
      if (remaining <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        _finishTest();
        return;
      }
      setState(() => _remainingSeconds = remaining - 1);
    });
  }

  DiagnosticAvailableSubjectsFn get _availableSubjects =>
      widget.availableSubjectsOverride ?? diagnosticKioskApi.availableSubjects;
  DiagnosticStartAttemptFn get _startAttemptCall =>
      widget.startAttemptOverride ?? diagnosticKioskApi.startAttempt;
  DiagnosticSubmitAnswerFn get _submitAnswerCall =>
      widget.submitAnswerOverride ?? diagnosticKioskApi.submitAnswer;
  DiagnosticFinishAttemptFn get _finishAttemptCall =>
      widget.finishAttemptOverride ?? diagnosticKioskApi.finishAttempt;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _initProctoring();
  }

  Future<void> _initProctoring() async {
    HeartbeatService.instance.onTerminated = () {
      ProctorService.instance.stop();
      HeartbeatService.instance.finishTest();
      if (mounted) context.pushReplacement('/diagnostic_finished');
    };
    try {
      await HeartbeatService.instance
          .startTest(
            schoolCode: widget.schoolCode,
            name: widget.studentName,
            variant: 'CAT',
            testKey: 'diag_${widget.attemptId}',
            studentCode: widget.attemptId,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    // The widget may have been disposed (dispose() already called
    // ProctorService.stop()) while the awaited call above was still
    // in flight — starting the proctor loop now would resurrect a
    // timer after teardown.
    if (!mounted) return;
    ProctorService.instance
      ..onWarning = (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.amber[900]),
          );
        }
      }
      ..start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    ProctorService.instance.stop();
    HeartbeatService.instance.finishTest();
    HeartbeatService.instance.onTerminated = null;
    super.dispose();
  }

  /// Shared "end the test now" path — used both when the backend reports
  /// `finished: true` with no next subject, and when the countdown timer
  /// hits zero.
  void _finishTest() {
    ProctorService.instance.stop();
    HeartbeatService.instance.finishTest();
    if (!mounted) return;
    context.pushReplacement('/diagnostic_finished');
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
      _subjectsEmpty = false;
    });
    try {
      final subjectsResp =
          await _availableSubjects(widget.grade, language: widget.language);
      final subjects = (subjectsResp['subjects'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          [];
      if (subjects.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _subjectsEmpty = true;
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
      final questionsList = (resp['questions'] as List?)
          ?.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _position = (resp['position'] as num?)?.toInt() ?? 1;
        _total = (resp['total_questions'] as num?)?.toInt() ?? 0;
        _isFixedVariant = resp['is_fixed_variant'] == true;
        _answers.clear();
        if (_isFixedVariant && questionsList != null && questionsList.isNotEmpty) {
          _questions = questionsList;
          final idx = (_position - 1).clamp(0, _questions.length - 1);
          _question = _questions[idx];
        } else {
          _questions = [];
          _question = _extractQuestion(resp);
        }
        _loading = false;
      });
      _startCountdownIfNeeded(resp);
      final q = _question;
      HeartbeatService.instance.updateProgress(_position, _total, [],
          q != null ? _questionText(q) : null, _selectedOption);
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
        _timer?.cancel();
        _finishTest();
        return;
      }
      if (finished && nextSubject.isNotEmpty) {
        _timer?.cancel();
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
        // Keep the selected option visible (no correct/incorrect reveal)
        // for a beat before advancing, instead of a manual continue tap.
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        setState(() {
          _question = next;
          _selectedOption = null;
          _position = (resp['position'] as num?)?.toInt() ?? _position;
          _total = (resp['total_questions'] as num?)?.toInt() ?? _total;
          _isFixedVariant = resp['is_fixed_variant'] == true;
        });
        HeartbeatService.instance.updateProgress(_position, _total, [],
            next != null ? _questionText(next) : null, _selectedOption);
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

  /// Local, network-free navigation for a fixed-variant/full-package
  /// attempt — [zeroBasedIndex] is clamped to the known question set.
  void _jumpTo(int zeroBasedIndex) {
    if (_questions.isEmpty) return;
    final clamped = zeroBasedIndex.clamp(0, _questions.length - 1);
    setState(() {
      _position = clamped + 1;
      _question = _questions[clamped];
      _selectedOption = _answers[_position];
    });
  }

  /// Finish path for a fixed-variant attempt: warns about unanswered
  /// questions (same dialog pattern as test_screen.dart's `_finish`), then
  /// submits every locally-collected answer in one `finishAttempt` call.
  Future<void> _confirmAndFinishPackage() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context)!;
    final unanswered = _total - _answers.length;
    if (unanswered > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.finishConfirmTitle,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(l10n.unansweredWarning(unanswered)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.backButton),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size(100, 40)),
              child: Text(l10n.finishTest),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final answers = <Map<String, dynamic>>[];
    _answers.forEach((position, selected) {
      final idx = position - 1;
      if (idx < 0 || idx >= _questions.length) return;
      final qid = _questionId(_questions[idx]);
      if (qid.isEmpty) return;
      answers.add({'question_id': qid, 'selected': selected});
    });
    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      await _finishAttemptCall(attemptId: widget.attemptId, answers: answers);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException ? e.message : e.toString();
      });
      return;
    }
    _timer?.cancel();
    _finishTest();
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
                : (_error != null || _subjectsEmpty)
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
    // _subjectsEmpty is an expected, calm "not configured yet" state — its
    // own dedicated copy in a neutral/amber info card. Any other _error is a
    // real ApiException/network failure: keep the original red warning
    // treatment so a proctor can still tell "broken" from "nothing to do
    // here" at a glance.
    final title = _subjectsEmpty
        ? l10n.diagnosticSubjectsEmptyTitle
        : (_error ?? l10n.diagnosticSubjectsEmptyTitle);
    final subtitle =
        _subjectsEmpty ? l10n.diagnosticSubjectsEmptySubtitle : null;
    final badgeColor = _subjectsEmpty ? AppColors.amber : AppColors.error;
    final badgeIcon =
        _subjectsEmpty ? Icons.info_outline_rounded : Icons.warning_rounded;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.pageBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(badgeIcon, color: badgeColor, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _subjectsEmpty ? AppColors.ink1 : AppColors.error),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.ink2),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.diagnosticGoBack),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _bootstrap,
                      child: Text(l10n.retry),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isFixedVariantAttempt => _isFixedVariant;

  Widget _buildQuestionView(AppLocalizations l10n, Map<String, dynamic> q) {
    final imageUrl = (q['image_url'] ?? '').toString().trim();
    final svgVisual = (q['svg_visual'] ?? '').toString().trim();
    final options = extractDiagnosticOptions(q);
    final questionId = _questionId(q);
    final showBottomNav = _isFixedVariantAttempt;
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, showBottomNav ? 20 : 140),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kDockMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DiagnosticHeaderBar(
                      subjectLabel: _subjectLabel(l10n, _currentSubject),
                      subjectIcon: _subjectIcon(_currentSubject),
                      subjectColor: _subjectColor(_currentSubject),
                      position: _position,
                      total: _total,
                      // widget.studentName is intentionally the raw/
                      // unformatted roster name (see
                      // diagnostic_student_select_screen.dart's _start())
                      // so HeartbeatService.startTest() keeps whatever
                      // disambiguating info (patronymic) the backend sends
                      // — format it just for display here.
                      studentName: formatStudentDisplayName(widget.studentName),
                      language: widget.language,
                      remainingSeconds: _remainingSeconds,
                      isFixedVariant: _isFixedVariantAttempt,
                      grade: widget.grade,
                    ),
                    if (_isFixedVariantAttempt) ...[
                      const SizedBox(height: 12),
                      DiagnosticQuestionDots(
                        total: _total,
                        currentIndex: (_position - 1)
                            .clamp(0, _total == 0 ? 0 : _total - 1),
                        answeredIndexes:
                            _answers.keys.map((p) => p - 1).toSet(),
                        onSelectIndex: _jumpTo,
                      ),
                    ],
                    const SizedBox(height: 20),
                    DiagnosticQuestionCard(
                      position: _position,
                      questionText: _questionText(q),
                      imageUrl: imageUrl,
                      svgVisual: svgVisual,
                      flagged: _flaggedQuestionIds.contains(questionId),
                      onToggleFlag: () => setState(() {
                        if (!_flaggedQuestionIds.remove(questionId)) {
                          _flaggedQuestionIds.add(questionId);
                        }
                      }),
                    ),
                    const SizedBox(height: 20),
                    ...options.map((opt) => DiagnosticOptionCard(
                          label: opt.key,
                          text: opt.text,
                          selected: _selectedOption == opt.key,
                          onTap: _submitting ||
                                  (!_isFixedVariant && _selectedOption != null)
                              ? () {}
                              : () {
                                  if (_isFixedVariant) {
                                    // Local-only: pick/change the answer for
                                    // the current position, no network call.
                                    setState(() {
                                      _selectedOption = opt.key;
                                      _answers[_position] = opt.key;
                                    });
                                    HeartbeatService.instance.updateProgress(
                                        _position,
                                        _total,
                                        [],
                                        _questionText(q),
                                        opt.key);
                                  } else {
                                    setState(() => _selectedOption = opt.key);
                                    _submit();
                                  }
                                },
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showBottomNav)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kDockMaxWidth),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: DiagnosticBottomNav(
                    onPrevious:
                        _position <= 1 ? null : () => _jumpTo(_position - 2),
                    onNext: () => _jumpTo(_position),
                    onFinish: _isFixedVariant
                        ? _confirmAndFinishPackage
                        : _finishTest,
                    isLast: (_position - 1) >= (_total - 1),
                    submitting: _submitting,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
