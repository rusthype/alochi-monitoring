// lib/features/diagnostic/widgets/diagnostic_tactile_option_card.dart
//
// Duolingo/Kahoot-style 3D tactile answer card for fixed-variant questions —
// a NEW widget independent of `DiagnosticOptionCard` (which stays untouched
// for the CAT/adaptive flow). Letter-badge color is fixed per letter
// (A=violet, B=blue, C=amber, D=emerald) regardless of selection; the card
// itself gets a thick bottom edge that reads as a pressable 3D key, and dips
// 2px on tap for tactile feedback.
import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

class DiagnosticTactileOptionCard extends StatefulWidget {
  final String label; // "A".."D"
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const DiagnosticTactileOptionCard({
    super.key,
    required this.label,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  State<DiagnosticTactileOptionCard> createState() =>
      _DiagnosticTactileOptionCardState();
}

class _DiagnosticTactileOptionCardState
    extends State<DiagnosticTactileOptionCard> {
  static const Color _brandDark = Color(0xFFC97A2E);
  static const Color _borderDark = Color(0xFFD1D5DB);

  bool _pressed = false;

  (Color, Color) get _badgeColors {
    switch (widget.label) {
      case 'A':
        return (AppColors.violetMuted, AppColors.violetInk);
      case 'B':
        return (AppColors.blueMuted, AppColors.blueInk);
      case 'C':
        return (AppColors.amberBorder, AppColors.amberDark);
      case 'D':
        return (AppColors.emeraldMuted, AppColors.emeraldInk);
      default:
        return (AppColors.pageBg, AppColors.ink2);
    }
  }

  // ponytail: BoxDecoration.border forbids a borderRadius when side colors
  // differ (Flutter assertion), so the thick "3D" bottom edge can't be one
  // Border with a different bottom color. Instead: a full-size background
  // layer in the edge color, plus a foreground card inset by 4px at the
  // bottom (uniform border, own radius) that exposes that edge as a step —
  // and slides down onto it on press. The foreground Padding is the Stack's
  // only non-positioned child, so the Stack sizes to content height + 4
  // regardless of the parent's constraints (Column, GridView, ...).
  static const double _edgeHeight = 4;

  @override
  Widget build(BuildContext context) {
    final (badgeBg, badgeInk) = _badgeColors;
    final borderColor = widget.selected ? AppColors.brand : AppColors.border;
    final edgeColor = widget.selected ? _brandDark : _borderDark;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: edgeColor,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: _edgeHeight),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              transform:
                  Matrix4.translationValues(0, _pressed ? _edgeHeight : 0, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                // Opaque brandLight, not a translucent alpha blend: this
                // card sits over the solid _brandDark "3D edge" background
                // layer (see the Stack below), so a translucent tint lets
                // that dark backdrop bleed through and reads as one flat,
                // low-contrast orange block with unreadable text (found via
                // a real local run) instead of a pale card with a thin
                // accent edge.
                color: widget.selected ? AppColors.brandLight : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: borderColor,
                  width: widget.selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: badgeBg),
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: badgeInk,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.text,
                      style: TextStyle(
                        color:
                            widget.selected ? AppColors.brand : AppColors.ink1,
                        fontWeight:
                            widget.selected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (widget.selected) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.brand,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 16),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
