// lib/shared/widgets/history_card.dart
//
// Shared look for the offline history lists (general + diagnostic tabs):
// rounded white card with a soft shadow, small rounded tags, and a rounded
// empty state.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HistoryCard extends StatelessWidget {
  final Widget child;
  const HistoryCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .035),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}

/// Small rounded label. Neutral grey by default; pass [color] for a tinted
/// (score) variant.
class HistoryTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;
  const HistoryTag(this.label, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppColors.ink2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color == null ? AppColors.muted : color!.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight:
                      color == null ? FontWeight.w500 : FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryEmpty extends StatelessWidget {
  final String text;
  const HistoryEmpty(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .035),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.history_toggle_off_rounded,
                  size: 40, color: AppColors.ink3),
            ),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.ink2, fontSize: 16)),
          ],
        ),
      );
}
