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
    this.icon,
    this.hoverColor,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.brand : AppColors.ink2;
    final chip = BottomChip(
      fill: selected
          ? AppColors.brand.withValues(alpha: 0.12)
          : AppColors.surface,
      border: selected ? AppColors.brand : AppColors.border,
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
