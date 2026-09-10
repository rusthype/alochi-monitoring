// lib/features/diagnostic/widgets/diagnostic_bottom_nav.dart
//
// Question-grid + Previous/Next + "finish test" bar — ONLY valid for a
// fixed-variant/all-questions-known-upfront attempt (see
// DiagnosticTestRunnerScreen._isFixedVariantAttempt doc comment). Never
// rendered for a CAT/adaptive attempt: the next question there is only
// known after answering the current one, so back-navigation and a
// pick-any-question grid would violate the adaptive protocol.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

class DiagnosticBottomNav extends StatelessWidget {
  final int total;
  final int currentIndex; // 0-based
  final Set<int> answeredIndexes; // 0-based
  final ValueChanged<int> onSelectIndex;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onFinish;

  const DiagnosticBottomNav({
    super.key,
    required this.total,
    required this.currentIndex,
    required this.answeredIndexes,
    required this.onSelectIndex,
    required this.onFinish,
    this.onPrevious,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: total,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final isCurrent = index == currentIndex;
                final isAnswered = answeredIndexes.contains(index);
                final bg = isCurrent
                    ? AppColors.brand
                    : isAnswered
                        ? AppColors.brand.withValues(alpha: 0.15)
                        : AppColors.pageBg;
                final fg = isCurrent
                    ? Colors.white
                    : isAnswered
                        ? AppColors.brand
                        : AppColors.ink3;
                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onSelectIndex(index),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isCurrent ? AppColors.brand : AppColors.border,
                      ),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                          color: fg, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onPrevious,
                  child: Text(l10n.previousButton),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: onNext,
                  child: Text(l10n.nextButton),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onFinish,
                  child: Text(l10n.finishTestButton),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
