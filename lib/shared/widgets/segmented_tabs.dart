// lib/shared/widgets/segmented_tabs.dart
//
// Generic icon+label segmented tab row. Adapted from
// student_settings_screen.dart's private `_SegmentedRow`/`_SegmentButton`
// pattern (same selected/hover/border visual language), promoted here so
// other screens — starting with the login screen's 3-way switcher — can
// reuse it instead of re-declaring their own tab-button chrome.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/student_palette.dart';
import 'hover_region.dart';

/// One tab's content + state. `badge` renders a small pill (e.g. "Скоро")
/// in the top-right corner — used for locked/coming-soon tabs.
class SegmentedTabItem {
  final IconData icon;
  final String label;
  final bool selected;
  final bool disabled;
  final String? badge;
  final VoidCallback? onTap;

  const SegmentedTabItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.disabled = false,
    this.badge,
    this.onTap,
  });
}

/// Row of equal-width [SegmentedTabButton]s.
class SegmentedTabsRow extends StatelessWidget {
  final List<SegmentedTabItem> items;
  final StudentPalette pal;
  const SegmentedTabsRow({super.key, required this.items, required this.pal});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: SegmentedTabButton(item: items[i], pal: pal)),
          ],
        ],
      ),
    );
  }
}

class SegmentedTabButton extends StatelessWidget {
  final SegmentedTabItem item;
  final StudentPalette pal;
  const SegmentedTabButton({super.key, required this.item, required this.pal});

  @override
  Widget build(BuildContext context) {
    final selected = item.selected;
    final disabled = item.disabled;
    final iconColor =
        disabled ? pal.ink3 : (selected ? AppColors.brand : pal.ink2);
    final labelColor =
        disabled ? pal.ink3 : (selected ? AppColors.brand : pal.ink1);

    final child = Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 22, color: iconColor),
              const SizedBox(height: 6),
              Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
        if (item.badge != null)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                item.badge!,
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 9.5,
                ),
              ),
            ),
          ),
      ],
    );

    if (disabled) {
      return Opacity(
        opacity: .6,
        child: Container(
          decoration: BoxDecoration(
            color: pal.chipBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: pal.border),
          ),
          child: child,
        ),
      );
    }

    return HoverRegion(
      builder: (context, isHovered) => GestureDetector(
        onTap: item.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brandLight
                : (isHovered ? pal.hoverBg : pal.surface),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.brand : pal.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
