// lib/features/diagnostic/widgets/diagnostic_bottom_nav.dart
//
// Previous/Next/Finish button bar — ONLY valid for a fixed-variant/
// all-questions-known-upfront attempt (see
// DiagnosticTestRunnerScreen._isFixedVariantAttempt doc comment). Never
// rendered for a CAT/adaptive attempt: the next question there is only
// known after answering the current one, so back-navigation would violate
// the adaptive protocol.
//
// The question-position dot grid used to live inside this widget; it now
// renders separately, above the question card, via DiagnosticQuestionDots.
// Styling mirrors lib/features/test/test_screen.dart's fixed nav bar
// (lines ~596-709) exactly.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

class DiagnosticBottomNav extends StatelessWidget {
  final VoidCallback? onPrevious;
  final VoidCallback onNext;
  final VoidCallback onFinish;
  final bool isLast;
  final bool submitting;

  const DiagnosticBottomNav({
    super.key,
    required this.onNext,
    required this.onFinish,
    required this.isLast,
    required this.submitting,
    this.onPrevious,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: Row(children: [
        AnimatedOpacity(
          opacity: onPrevious == null ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            width: 110,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.arrow_back_rounded, size: 15),
              label: Text(l10n.previousButton,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink2,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 110,
          height: 44,
          child: isLast
              ? ElevatedButton(
                  onPressed: submitting ? null : onFinish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ok,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(l10n.finishTestButton,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.check_rounded, size: 15),
                          ],
                        ),
                )
              : ElevatedButton(
                  onPressed: onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(l10n.nextButton,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 15),
                    ],
                  ),
                ),
        ),
      ]),
    );
  }
}
