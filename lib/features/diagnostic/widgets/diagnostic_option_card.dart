// lib/features/diagnostic/widgets/diagnostic_option_card.dart
//
// Full-width answer-option card for the diagnostic runner mockup: circular
// A/B/C/D letter badge + text, selected = blue border/tint. A NEW widget —
// deliberately NOT a change to the shared `EngineOptionRow`
// (lib/core/engine/question_widgets.dart), which interhouse_runner.dart and
// others still use as-is.
import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

class DiagnosticOptionCard extends StatelessWidget {
  final String label; // "A".."D"
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const DiagnosticOptionCard({
    super.key,
    required this.label,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.brand.withValues(alpha: 0.08)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.brand : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.brand : AppColors.pageBg,
                    border: Border.all(
                      color: selected ? AppColors.brand : AppColors.border,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.ink2,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: selected ? AppColors.brand : AppColors.ink1,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
