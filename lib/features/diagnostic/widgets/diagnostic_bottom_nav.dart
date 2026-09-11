// lib/features/diagnostic/widgets/diagnostic_bottom_nav.dart
//
// Previous/Next-or-Finish button row — ONLY valid for a fixed-variant/
// all-questions-known-upfront attempt (see
// DiagnosticTestRunnerScreen._isFixedVariantAttempt doc comment). Never
// rendered for a CAT/adaptive attempt. The question-number carousel that
// used to live inside this widget now lives above the question card as
// DiagnosticQuestionDots; the caller (DiagnosticTestRunnerScreen) wraps
// this row in its own centered/floating dock chrome.
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
    return Row(
      children: [
        Visibility(
          maintainSize: true,
          maintainState: true,
          maintainAnimation: true,
          visible: onPrevious != null,
          child: SizedBox(
            width: 110,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(l10n.previousButton,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink2,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ),
        const Spacer(),
        if (isLast)
          SizedBox(
            width: 172,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: submitting ? null : onFinish,
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(l10n.finishTestButton,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ok,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
        else
          SizedBox(
            width: 110,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(l10n.nextButton,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
      ],
    );
  }
}
