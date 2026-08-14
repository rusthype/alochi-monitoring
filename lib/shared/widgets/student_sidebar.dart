// lib/shared/widgets/student_sidebar.dart
//
// Generalized (public) version of my_tests_screen.dart's private
// `_SidebarNavigation` — same 7-item menu, same visuals, same
// enabled/disabled + "Скоро" badge language as login_screen.dart's disabled
// `_routeButton`. Extracted so every student-cabinet screen (via
// StudentShell) shares one sidebar instead of re-declaring it.
//
// The 7-item route table is centralized here as [_items] — 5 of them
// (`/my_tests`, `/results`, `/certificates`, `/settings`, `/help`) are real
// `StatefulShellRoute` branches (see app_router.dart + student_shell.dart's
// [kStudentBranchPaths]); tapping one now calls `navigationShell.goBranch`
// instead of `context.go`, so switching tabs swaps the IndexedStack branch
// in place (no GoRouter page transition, scroll/state preserved). The other
// 2 stay `enabled: false` with the "Скоро" badge.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/student_palette.dart';
import 'hover_region.dart';
import 'student_shell.dart' show kStudentBranchPaths;

class _SidebarItem {
  final String? path; // null = no real route yet (disabled placeholder)
  final IconData icon;
  final String Function(AppLocalizations) label;
  final bool enabled;

  // All 7 items are enabled today (Bosqich 6 shipped Главная/Сообщения),
  // but `enabled` stays for the next "Скоро" placeholder item, matching
  // login_screen.dart's same disabled-badge pattern.
  const _SidebarItem({
    this.path,
    required this.icon,
    required this.label,
    // ignore: unused_element_parameter
    this.enabled = true,
  });
}

final List<_SidebarItem> _items = [
  _SidebarItem(
      path: '/home',
      icon: Icons.home_rounded,
      label: (l10n) => l10n.sidebarHome),
  _SidebarItem(
      path: '/my_tests',
      icon: Icons.assignment_rounded,
      label: (l10n) => l10n.myTestsTitle),
  _SidebarItem(
      path: '/results',
      icon: Icons.bar_chart_rounded,
      label: (l10n) => l10n.sidebarResults),
  _SidebarItem(
      path: '/messages',
      icon: Icons.mail_rounded,
      label: (l10n) => l10n.sidebarMessages),
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
  final StatefulNavigationShell navigationShell;

  const StudentSidebar({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border(right: BorderSide(color: pal.border)),
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
                          .copyWith(fontWeight: FontWeight.w800, color: pal.ink1)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final item in _items)
            _item(context, item, pal,
                active: item.path != null &&
                    kStudentBranchPaths.indexOf(item.path!) ==
                        navigationShell.currentIndex),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, _SidebarItem item, StudentPalette pal,
      {required bool active}) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = item.enabled;
    final color =
        !enabled ? pal.ink3 : (active ? AppColors.brand : pal.ink2);
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

    // `goBranch` (not `go`/`push`) — these are branches of the same
    // StatefulShellRoute (see app_router.dart), each with its own preserved
    // Navigator stack. goBranch swaps which branch's IndexedStack child is
    // visible without rebuilding it or triggering a page-transition
    // animation, which is exactly the "no slайд, content just switches"
    // behavior this sidebar needs.
    final onTap = (enabled && !active)
        ? () {
            // StudentShell's Scaffold/ScaffoldMessenger is shared across all
            // branches (built once, IndexedStack swaps content) — a "Скоро"
            // SnackBar triggered on one tab (e.g. Помощь video card) would
            // otherwise keep showing after switching tabs, since goBranch
            // doesn't dismiss it. Clear it on every real tab switch.
            ScaffoldMessenger.of(context).clearSnackBars();
            navigationShell.goBranch(kStudentBranchPaths.indexOf(item.path!));
          }
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: !enabled
          ? Opacity(opacity: 0.6, child: child)
          : HoverRegion(
              builder: (context, isHovered) => Material(
                color: active
                    ? AppColors.brandLight
                    : (isHovered ? pal.hoverBg : Colors.transparent),
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
