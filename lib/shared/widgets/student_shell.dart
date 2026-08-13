// lib/shared/widgets/student_shell.dart
//
// Shared chrome for the student-cabinet screens (self-login flow):
// Scaffold > SafeArea > Row(StudentSidebar, Column(StudentTopHeaderBar,
// Expanded(navigationShell))).
//
// Now the single `builder` of app_router.dart's StatefulShellRoute.indexedStack
// (5 branches: my_tests/results/settings/help/certificates) instead of being
// instantiated fresh inside each of those 5 screens — so it's built ONCE and
// the sidebar/header no longer flash/rebuild when switching tabs (that was
// the nav "slайд" bug: every screen used to wrap itself in its own
// StudentShell, so GoRouter saw each tab switch as a brand-new Page).
//
// [kStudentBranchPaths] is the single source of truth for branch order/index
// — MUST match the branch registration order in app_router.dart exactly.
// Shared with student_sidebar.dart so both stay in sync without duplicating
// the list.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/session/logout.dart';
import 'student_sidebar.dart';
import 'student_top_bar.dart';

const kStudentBranchPaths = [
  '/my_tests',
  '/results',
  '/settings',
  '/help',
  '/certificates',
  '/home',
  '/messages',
];

const _kResultsBranchIndex = 1; // kStudentBranchPaths.indexOf('/results')

final List<String Function(AppLocalizations)> _branchTitles = [
  (l10n) => l10n.myTestsTitle,
  (l10n) => l10n.resultsScreenTitle,
  (l10n) => l10n.sidebarSettings,
  (l10n) => l10n.helpScreenTitle,
  (l10n) => l10n.certificatesScreenTitle,
  (l10n) => l10n.sidebarHome,
  (l10n) => l10n.sidebarMessages,
];

class StudentShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const StudentShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isSmall = MediaQuery.of(context).size.width < 800;
    final currentIndex = navigationShell.currentIndex;
    // Sidebar is the normal way to reach `/results`; when it's hidden
    // (narrow viewport) the header shows a results shortcut instead — but
    // not while already on `/results`, same as the sidebar suppresses its
    // own "Результаты" tap when already active.
    final onResultsTap = (isSmall && currentIndex != _kResultsBranchIndex)
        ? () => navigationShell.goBranch(_kResultsBranchIndex)
        : null;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (!isSmall) StudentSidebar(navigationShell: navigationShell),
            Expanded(
              child: Column(
                children: [
                  StudentTopHeaderBar(
                    title: _branchTitles[currentIndex](l10n),
                    onLogout: () => logoutStudentSession(context),
                    onResultsTap: onResultsTap,
                  ),
                  Expanded(child: navigationShell),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
