// lib/features/diagnostic/widgets/diagnostic_question_dots.dart
//
// Horizontal question-position dots row, rendered above the question card
// in the fixed-variant diagnostic flow. Same visual language as
// lib/features/test/test_screen.dart's private `_QDot`/dots row, made
// public and generic — diagnostic is single-subject so there's no
// isMath split.
import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

class DiagnosticQuestionDots extends StatelessWidget {
  final int total;
  final int currentIndex; // 0-based
  final Set<int> answeredIndexes; // 0-based
  final ValueChanged<int> onSelectIndex;

  const DiagnosticQuestionDots({
    super.key,
    required this.total,
    required this.currentIndex,
    required this.answeredIndexes,
    required this.onSelectIndex,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: total,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) => _QDot(
          number: i + 1,
          isCurrent: i == currentIndex,
          isAnswered: answeredIndexes.contains(i),
          onTap: () => onSelectIndex(i),
        ),
      ),
    );
  }
}

class _QDot extends StatelessWidget {
  final int number;
  final bool isCurrent, isAnswered;
  final VoidCallback onTap;
  const _QDot({
    required this.number,
    required this.isCurrent,
    required this.isAnswered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isCurrent
        ? AppColors.brand
        : isAnswered
            ? AppColors.correctBorder
            : AppColors.chipBorder;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 30,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: isCurrent ? 30 : 26,
            height: isCurrent ? 30 : 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? AppColors.brand
                  : isAnswered
                      ? AppColors.successMuted
                      : AppColors.surface,
              border: Border.all(color: accent, width: isCurrent ? 2 : 1.5),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                          color: AppColors.brand.withValues(alpha: .3),
                          blurRadius: 8,
                          spreadRadius: 1)
                    ]
                  : null,
            ),
            child: Center(
                child: Text(number.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: isCurrent ? 10 : 9,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrainsMono',
                      color: isCurrent
                          ? Colors.white
                          : isAnswered
                              ? AppColors.correctInk
                              : AppColors.chipIcon,
                    ))),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            height: 3,
            width: isCurrent ? 18 : 0,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ]),
      ),
    );
  }
}
