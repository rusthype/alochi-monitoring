// lib/shared/widgets/pill_chip.dart
//
// The rounded chip used for filters, hub tabs and small actions: white capsule (school-picker pill shape),
// thin border, soft shadow; selected = accent-tinted fill + accent border.
// Extracted from DiagnosticHistoryScreen._chip so the offline history hub
// (tab switcher, clear action) and the diagnostic filters look identical.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'button_shape.dart';

/// Fully rounded capsule, same radius as the school-picker pills
/// (DiagnosticPillButton).
const double _kCapsuleRadius = 100;

class PillChip extends StatelessWidget {
  final String label;
  final bool selected;

  /// 0..1 selection progress; when set it overrides [selected] and lerps the
  /// fill/border/text colors (used to follow a TabBarView swipe live).
  final double? selectedAmount;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Hover/press ink color; defaults to the selected/idle foreground. Lets a
  /// quiet action (e.g. clear history) stay grey and only turn red on hover.
  final Color? hoverColor;

  /// Shown as a tooltip when set (icon-only or terse actions).
  final String? tooltip;

  const PillChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.selectedAmount,
    this.icon,
    this.hoverColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final t = (selectedAmount ?? (selected ? 1.0 : 0.0)).clamp(0.0, 1.0);
    final fg = Color.lerp(AppColors.ink2, AppColors.brand, t)!;
    final chip = BottomChip(
      fill: Color.lerp(
          AppColors.surface, AppColors.brand.withValues(alpha: 0.12), t)!,
      border: Color.lerp(AppColors.border, AppColors.brand, t)!,
      height: 40,
      radius: _kCapsuleRadius,
      child: TextButton(
        onPressed: onPressed,
        style: bottomChipButtonStyle(
          foreground: fg,
          fontSize: 13,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          radius: _kCapsuleRadius,
        ).copyWith(overlayColor: pointerOnlyOverlay(hoverColor ?? fg)),
        child: icon == null
            ? Text(label)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 6),
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}
