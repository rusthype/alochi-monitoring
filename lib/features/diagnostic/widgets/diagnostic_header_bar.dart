// lib/features/diagnostic/widgets/diagnostic_header_bar.dart
//
// Presentational header for DiagnosticTestRunnerScreen: subject badge,
// answered-count, countdown timer, student name + language badge. The
// countdown itself (Timer.periodic) lives in the parent screen's State —
// this widget only renders whatever `remainingSeconds` it's given.
//
// For a fixed-variant attempt (isFixedVariant: true) the layout collapses
// to a single row (name+grade-pill+language on the left, timer on the
// right) — subject-pill/counter/progress-bar are the CAT-only layout below
// and are never shown here; DiagnosticQuestionDots (added by the screen,
// not this widget) carries progress instead.
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

  /// Whether the current attempt is fixed-variant (all questions known
  /// upfront) — see DiagnosticTestRunnerScreen._isFixedVariantAttempt.
  final bool isFixedVariant;

  /// Student grade, shown as a colored pill next to the name — only used
  /// when [isFixedVariant] is true.
  final int? grade;

  const DiagnosticHeaderBar({
    super.key,
    required this.subjectLabel,
    required this.subjectIcon,
    required this.subjectColor,
    required this.position,
    required this.total,
    required this.studentName,
    required this.language,
    required this.isFixedVariant,
    this.grade,
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
    if (isFixedVariant) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    studentName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.ink3, fontSize: 13),
                  ),
                ),
                if (grade != null) ...[
                  const SizedBox(width: 8),
                  _GradePill(grade: grade!),
                ],
                const SizedBox(width: 8),
                DiagnosticLanguageBadge(language: language),
              ],
            ),
          ),
          if (remainingSeconds != null) ...[
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 15, color: AppColors.ink3),
                const SizedBox(width: 4),
                Text(
                  '${_formatClock(remainingSeconds!)} ${l10n.timeLeftLabel}',
                  style: const TextStyle(
                    color: AppColors.ink3,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }
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

/// Grade badge, copied from test_screen.dart's private `_GradePill`
/// (read-only pattern reference — see this feature's task doc) so this
/// file never imports that screen.
class _GradePill extends StatelessWidget {
  final int grade;
  const _GradePill({required this.grade});

  @override
  Widget build(BuildContext context) {
    final colors = {
      1: (
        AppColors.secondaryMuted,
        const Color(0xFF9A3412),
        AppColors.amberBorder,
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
      child: Text(
        '$grade-${AppLocalizations.of(context)!.gradeShort}',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.$2),
      ),
    );
  }
}
