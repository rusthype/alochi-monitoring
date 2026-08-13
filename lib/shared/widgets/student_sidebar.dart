// lib/shared/widgets/student_sidebar.dart
//
// Generalized (public) version of my_tests_screen.dart's private
// `_SidebarNavigation` — same 7-item menu, same visuals, same
// enabled/disabled + "Скоро" badge language as login_screen.dart's disabled
// `_routeButton`. Extracted so every student-cabinet screen (via
// StudentShell) shares one sidebar instead of re-declaring it.
//
// NEW: the 7-item route table is centralized here as [_items] — a screen
// now just passes its own route path as [currentRoute] and the matching
// item lights up as active, instead of the old hardcoded
// "Мои тесты is always active" + single `onResultsTap` callback. Only
// `/my_tests` and `/results` are real routes today; the other 5 stay
// `enabled: false` with the "Скоро" badge exactly as before — do not enable
// them here, that happens screen-by-screen later.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/models/models.dart';
import '../theme/app_theme.dart';
import 'hover_region.dart';

class _SidebarItem {
  final String? path; // null = no real route yet (disabled placeholder)
  final IconData icon;
  final String Function(AppLocalizations) label;
  final bool enabled;

  const _SidebarItem({
    this.path,
    required this.icon,
    required this.label,
    this.enabled = true,
  });
}

final List<_SidebarItem> _items = [
  _SidebarItem(
      icon: Icons.home_rounded, label: (l10n) => l10n.sidebarHome, enabled: false),
  _SidebarItem(
      path: '/my_tests',
      icon: Icons.assignment_rounded,
      label: (l10n) => l10n.myTestsTitle),
  _SidebarItem(
      path: '/results',
      icon: Icons.bar_chart_rounded,
      label: (l10n) => l10n.sidebarResults),
  _SidebarItem(
      icon: Icons.mail_rounded,
      label: (l10n) => l10n.sidebarMessages,
      enabled: false),
  _SidebarItem(
      path: '/certificates',
      icon: Icons.workspace_premium_rounded,
      label: (l10n) => l10n.sidebarCertificates),
  _SidebarItem(
      path: '/settings',
      icon: Icons.settings_rounded,
      label: (l10n) => l10n.sidebarSettings),
  _SidebarItem(
      path: '/help',
      icon: Icons.help_rounded,
      label: (l10n) => l10n.sidebarHelp),
];

class StudentSidebar extends StatelessWidget {
  /// The route path of the screen currently showing this sidebar (e.g.
  /// `/my_tests`, `/results`) — the matching item renders active.
  final String currentRoute;
  final StudentSession session;

  const StudentSidebar({
    super.key,
    required this.currentRoute,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.school_rounded,
                    color: AppColors.brand, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.appTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelLarge
                          .copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final item in _items)
            _item(context, item, active: item.path == currentRoute),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, _SidebarItem item, {required bool active}) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = item.enabled;
    final color =
        !enabled ? AppColors.ink3 : (active ? AppColors.brand : AppColors.ink2);
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        children: [
          Icon(item.icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(item.label(l10n),
                style: AppTextStyles.labelLarge.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                )),
          ),
          if (!enabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(l10n.comingSoon,
                  style: AppTextStyles.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 9)),
            ),
        ],
      ),
    );

    // `go` (not `push`) — these are sibling top-level tabs, not a
    // push-drill-down flow. `push` left every previously-visited tab's
    // screen instance (and its own data-fetching state) stacked underneath,
    // growing the Navigator stack unboundedly as a student bounced between
    // tabs. `go` replaces the current location instead, matching the
    // existing "hard reset" pattern this app already uses elsewhere
    // (my_tests_screen.dart's "Bosh sahifa" exit calls `context.go('/')`).
    // Safe here: with this app's flat (non-nested) route table, `go` swaps
    // the whole match list via GoRouter's declarative Page diffing, not an
    // imperative Navigator.pop() — so it does NOT trigger the PopScope
    // (canPop: false) back-button interception my_tests_screen.dart relies
    // on, which only fires on an actual pop attempt (hardware back, appbar
    // back), never on a declarative page-list change from `go()`.
    final onTap = (enabled && !active)
        ? () => context.go(item.path!, extra: {'session': session})
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: !enabled
          ? Opacity(opacity: 0.6, child: child)
          : HoverRegion(
              builder: (context, isHovered) => Material(
                color: active
                    ? AppColors.brandLight
                    : (isHovered ? AppColors.hoverBg : Colors.transparent),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onTap,
                  child: child,
                ),
              ),
            ),
    );
  }
}
