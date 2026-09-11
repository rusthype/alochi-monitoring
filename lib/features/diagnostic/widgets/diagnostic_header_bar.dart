// lib/features/diagnostic/widgets/diagnostic_header_bar.dart
//
// Presentational header for DiagnosticTestRunnerScreen: student name +
// grade pill + language badge on the left, countdown timer on the right —
// mirrors lib/features/test/test_screen.dart's header row/_GradePill.
// The countdown itself (Timer.periodic) lives in the parent screen's State
// — this widget only renders whatever `remainingSeconds` it's given.
// Question position/progress is now conveyed by DiagnosticQuestionDots,
// rendered separately by the parent screen.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import 'diagnostic_widgets.dart';

class DiagnosticHeaderBar extends StatelessWidget {
  final int grade;
  final String studentName;
  final String language;

  /// Null when the current flow has no known test duration (e.g. the CAT
  /// engine's start/answer responses carry no `duration_minutes` — see
  /// DiagnosticTestRunnerScreen's `_remainingSeconds` doc comment) — the
  /// timer is simply omitted in that case.
  final int? remainingSeconds;

  const DiagnosticHeaderBar({
    super.key,
    required this.grade,
    required this.studentName,
    required this.language,
    this.remainingSeconds,
  });

  String _formatClock(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  studentName,
                  style: const TextStyle(
                      color: AppColors.ink1,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              _GradePill(grade: grade),
              const SizedBox(width: 8),
              DiagnosticLanguageBadge(language: language),
            ],
          ),
        ),
        const SizedBox(width: 14),
        if (remainingSeconds != null)
          _TimerWidget(
            display: _formatClock(remainingSeconds!),
            label: l10n.timeLeftLabel,
          ),
      ],
    );
  }
}

class _GradePill extends StatelessWidget {
  final int grade;
  const _GradePill({required this.grade});

  @override
  Widget build(BuildContext context) {
    final colors = {
      1: (
        AppColors.secondaryMuted,
        const Color(0xFF9A3412),
        AppColors.amberBorder
      ),
      2: (AppColors.tealMuted, AppColors.tealInk, const Color(0xFF99F6E4)),
      3: (AppColors.blueMuted, AppColors.blueInk, AppColors.blueBorder),
      4: (AppColors.violetMuted, AppColors.violetInk, AppColors.violetBorder),
    };
    final c = colors[grade] ?? colors[1]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.$1,
        border: Border.all(color: c.$3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$grade-${AppLocalizations.of(context)!.gradeShort}',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: c.$2)),
    );
  }
}

class _TimerWidget extends StatelessWidget {
  final String display;
  final String label;
  const _TimerWidget({required this.display, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.secondaryMuted,
          border: Border.all(color: AppColors.amberBorder, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_outlined,
                size: 15, color: AppColors.amberInk),
            const SizedBox(width: 6),
            Text(display,
                style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.amberInk)),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.amberInk)),
          ],
        ),
      );
}
