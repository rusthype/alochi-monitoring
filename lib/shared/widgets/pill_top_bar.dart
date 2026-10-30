// lib/shared/widgets/pill_top_bar.dart
//
// The one kiosk top bar: floating full-round white pill, soft shadow, thin
// light border; round icon-only back button on the left (accent arrow, label
// only as tooltip/Semantics), centered UPPERCASE letter-spaced title, optional
// grey step chip and optional round [PillTopBarAction] buttons on the right.
// Visuals come from diagnostic_session_setup_screen's former
// `_buildFloatingNavbar`.
import 'package:flutter/material.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'button_shape.dart';

const double _kSlot = 40;

class PillTopBar extends StatelessWidget {
  final String title;

  /// Null hides the arrow (an empty slot keeps the title centered).
  final VoidCallback? onBack;

  /// Small grey chip on the right, e.g. a step counter "1/3".
  final String? trailing;

  /// Extra round buttons on the right, after [trailing].
  final List<Widget> actions;

  const PillTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final backLabel = AppLocalizations.of(context)!.backBtn;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          if (onBack == null)
            const SizedBox(width: _kSlot, height: _kSlot)
          else
            Tooltip(
              message: backLabel,
              excludeFromSemantics: true,
              child: Semantics(
                button: true,
                label: backLabel,
                excludeSemantics: true,
                child: _RoundButton(
                  onTap: onBack!,
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          // Guaranteed gap so a long title never touches the buttons.
          const SizedBox(width: 12),
          Expanded(
            child: Tooltip(
              message: title,
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: AppColors.charcoal,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _kSlot),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (trailing != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      trailing!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: AppColors.stone,
                      ),
                    ),
                  ),
                for (final a in actions) ...[const SizedBox(width: 6), a],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon-only round action for [PillTopBar.actions]: same size, thin border and
/// accent icon as the back button. [tooltip] is mandatory (icon-only).
class PillTopBarAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const PillTopBarAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: _RoundButton(
        onTap: onPressed,
        child: Icon(icon, size: 20, color: AppColors.accent),
      ),
    ),
  );
}

class _RoundButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _RoundButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.pageBg,
    shape: CircleBorder(
      side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      // Hover/press only: a restored keyboard focus must not stay painted.
      focusColor: Colors.transparent,
      overlayColor: pointerOnlyOverlay(AppColors.accent),
      child: SizedBox(
        width: _kSlot,
        height: _kSlot,
        child: Center(child: child),
      ),
    ),
  );
}
