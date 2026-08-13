// lib/shared/widgets/student_shell.dart
//
// Shared chrome for the student-cabinet screens (self-login flow):
// Scaffold > SafeArea > Row(StudentSidebar, Column(StudentTopHeaderBar,
// Expanded(child))) — the exact structure my_tests_screen.dart's `build()`
// used to build inline (see git history), now shared so every screen looks
// consistent instead of each reinventing its own chrome.
//
// Deliberately does NOT wrap in PopScope — that's kiosk-security behavior
// specific to my_tests_screen.dart (blocks all back-navigation there); a
// shared PopScope(canPop: false) here would also block results_screen.dart's
// own back button, which must keep working. Screens that need it wrap
// StudentShell in their own PopScope, same as before.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../theme/app_theme.dart';
import 'student_sidebar.dart';
import 'student_top_bar.dart';

class StudentShell extends StatelessWidget {
  final String currentRoute;
  final StudentSession session;
  final String title;
  final VoidCallback onLogout;
  final Widget child;

  const StudentShell({
    super.key,
    required this.currentRoute,
    required this.session,
    required this.title,
    required this.onLogout,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 800;
    // Sidebar is the normal way to reach `/results`; when it's hidden
    // (narrow viewport) the header shows a results shortcut instead — but
    // not while already on `/results`, same as the sidebar suppresses its
    // own "Результаты" tap when already active.
    final onResultsTap = (isSmall && currentRoute != '/results')
        ? () => context.push('/results', extra: {'session': session})
        : null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Row(
          children: [
            if (!isSmall)
              StudentSidebar(currentRoute: currentRoute, session: session),
            Expanded(
              child: Column(
                children: [
                  StudentTopHeaderBar(
                    title: title,
                    onLogout: onLogout,
                    onResultsTap: onResultsTap,
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
