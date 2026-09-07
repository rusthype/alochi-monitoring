// lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart
//
// CAT (adaptive) test runner — new, no existing screen pattern fits since
// the CAT engine is server-adaptive and drives one question at a time.
// Flow: availableSubjects(grade) -> startAttempt(first subject) -> loop
// submitAnswer -> render next question, or startAttempt(next_subject) on a
// subject transition, or navigate to the finished screen when done.
//
// The backend response shape is loosely typed per the kiosk API contract
// ("first question + attempt_id + position info" / "next question data
// when not finished") — parsing below is defensive about exact key names.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart' show ApiException;
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_kiosk_api.dart';

class DiagnosticTestRunnerScreen extends StatefulWidget {
  final String attemptId;
  final String studentName;
  final int grade;

  const DiagnosticTestRunnerScreen({
    super.key,
    required this.attemptId,
    required this.studentName,
    required this.grade,
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
  dynamic _selectedOption;

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
      final subjectsResp =
          await diagnosticKioskApi.availableSubjects(widget.grade);
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
    });
    try {
      final resp = await diagnosticKioskApi.startAttempt(
        attemptId: widget.attemptId,
        subject: subject,
      );
      if (!mounted) return;
      setState(() {
        _question = _extractQuestion(resp);
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
      final resp = await diagnosticKioskApi.submitAnswer(
        attemptId: widget.attemptId,
        questionId: _questionId(q),
        selected: _optionValue(selected),
      );
      final finished = resp['finished'] == true;
      final nextSubject = (resp['next_subject'] ?? '').toString();
      if (finished && nextSubject.isEmpty) {
        if (!mounted) return;
        context.pushReplacement('/diagnostic_finished');
        return;
      }
      if (nextSubject.isNotEmpty) {
        await _startSubject(nextSubject);
      } else {
        final next = _extractQuestion(resp);
        if (!mounted) return;
        setState(() {
          _question = next;
          _selectedOption = null;
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

  List<dynamic> _questionOptions(Map<String, dynamic> q) {
    final raw = q['options'] ?? q['choices'] ?? q['answers'] ?? const [];
    return raw is List ? raw : const [];
  }

  String _optionLabel(dynamic opt) {
    if (opt is Map) {
      return (opt['text'] ?? opt['label'] ?? opt['value'] ?? '').toString();
    }
    return opt.toString();
  }

  String _optionValue(dynamic opt) {
    if (opt is Map) {
      return (opt['id'] ?? opt['value'] ?? opt['key'] ?? opt['text'] ?? '')
          .toString();
    }
    return opt.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final q = _question;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_rounded,
                              color: AppColors.error, size: 40),
                          const SizedBox(height: 12),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.error)),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _bootstrap,
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    ),
                  )
                : q == null
                    ? Center(child: Text(l10n.diagnosticNoStudents))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  widget.studentName,
                                  style: const TextStyle(
                                      color: AppColors.ink3, fontSize: 13),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _questionText(q),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.ink1,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                ..._questionOptions(q).map((opt) {
                                  final isSelected = _selectedOption == opt;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: OutlinedButton(
                                      onPressed: _submitting
                                          ? null
                                          : () => setState(
                                              () => _selectedOption = opt),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16, horizontal: 16),
                                        alignment: Alignment.centerLeft,
                                        backgroundColor: isSelected
                                            ? AppColors.brand
                                                .withValues(alpha: 0.08)
                                            : AppColors.surface,
                                        side: BorderSide(
                                          color: isSelected
                                              ? AppColors.brand
                                              : AppColors.border,
                                          width: isSelected ? 2 : 1,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: Text(
                                        _optionLabel(opt),
                                        style: TextStyle(
                                          color: isSelected
                                              ? AppColors.brand
                                              : AppColors.ink1,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed:
                                        _selectedOption == null || _submitting
                                            ? null
                                            : _submit,
                                    child: _submitting
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white),
                                          )
                                        : Text(l10n.continueButton),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
      ),
    );
  }
}
