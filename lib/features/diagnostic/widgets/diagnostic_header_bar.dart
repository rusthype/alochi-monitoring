// lib/features/diagnostic/widgets/diagnostic_header_bar.dart
//
// Presentational header for DiagnosticTestRunnerScreen: subject badge,
// answered-count, countdown timer, student name + language badge. The
// countdown itself (Timer.periodic) lives in the parent screen's State —
// this widget only renders whatever `remainingSeconds` it's given.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import 'diagnostic_widgets.dart';

class DiagnosticHeaderBar extends StatelessWidget {
  final String subjectLabel;
  final IconData subjectIcon;
  final Color subjectColor;
  final int position;
  final int total;
  final String studentName;
  final String language;

  /// Null when the current flow has no known test duration (e.g. the CAT
  /// engine's start/answer responses carry no `duration_minutes` — see
  /// DiagnosticTestRunnerScreen's `_remainingSeconds` doc comment) — the
  /// timer row is simply omitted in that case.
  final int? remainingSeconds;

  const DiagnosticHeaderBar({
    super.key,
    required this.subjectLabel,
    required this.subjectIcon,
    required this.subjectColor,
    required this.position,
    required this.total,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: subjectColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(subjectIcon, size: 16, color: subjectColor),
                  const SizedBox(width: 6),
                  Text(
                    subjectLabel,
                    style: TextStyle(
                        color: subjectColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.diagnosticQuestionCounter(position, total),
                  style: const TextStyle(
                      color: AppColors.ink3,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.answeredLabel,
                  style: const TextStyle(
                      color: AppColors.ink3,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                ),
                if (remainingSeconds != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.timer_outlined,
                      size: 15, color: AppColors.ink3),
                  const SizedBox(width: 4),
                  Text(
                    '${_formatClock(remainingSeconds!)} ${l10n.timeLeftLabel}',
                    style: const TextStyle(
                        color: AppColors.ink3,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ],
              ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: total > 0 ? (position / total).clamp(0.0, 1.0) : 0,
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(AppColors.brand),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              studentName,
              style: const TextStyle(color: AppColors.ink3, fontSize: 13),
            ),
            const SizedBox(width: 8),
            DiagnosticLanguageBadge(language: language),
          ],
        ),
      ],
    );
  }
}
