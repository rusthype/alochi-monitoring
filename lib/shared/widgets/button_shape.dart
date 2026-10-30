import 'package:flutter/material.dart';

/// Corner radius of the big login-screen buttons, pills and capsules.
const double kControlRadius = 14;

/// Corner radius of chips and segmented tabs. Frame and hover/ink shape must
/// both use this, so the highlight never renders as a smaller pill inside
/// the border.
const double kChipRadius = 13;

/// Ink overlay that paints only for hover and press, never for keyboard
/// focus. A pointer-activated control whose focus is restored after a route
/// pop (FocusScope) would otherwise keep a solid grey focus highlight while
/// the mouse is elsewhere. Values mirror the Material 3 defaults for
/// hover (8%) and press (10%); keyboard activation still works.
WidgetStateProperty<Color?> pointerOnlyOverlay(Color foreground) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return foreground.withValues(alpha: .10);
      }
      if (states.contains(WidgetState.hovered)) {
        return foreground.withValues(alpha: .08);
      }
      return null;
    });

/// Style for a [TextButton] living inside a [BottomChip]: same shape as the
/// frame, so hover/pressed/focus overlays follow the outline exactly.
ButtonStyle bottomChipButtonStyle({
  required Color foreground,
  double fontSize = 12,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 8),
  double radius = kChipRadius,
}) =>
    TextButton.styleFrom(
      foregroundColor: foreground,
      padding: padding,
      minimumSize: const Size(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
    ).copyWith(overlayColor: pointerOnlyOverlay(foreground));

/// Outlined, softly shadowed frame for the small action chips under the
/// login card. Clips its child to the rounded shape.
class BottomChip extends StatelessWidget {
  const BottomChip({
    super.key,
    required this.fill,
    required this.border,
    required this.child,
    this.height,
    this.minHeight,
    this.radius = kChipRadius,
  });

  final Color fill;
  final Color border;
  final Widget child;
  final double? height;
  final double? minHeight;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        constraints:
            minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border),
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
