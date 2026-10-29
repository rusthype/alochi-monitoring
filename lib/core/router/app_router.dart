import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/login_screen.dart';
import '../../features/session/session_providers.dart';
import '../../features/session/test_session.dart';
import '../widgets/error_screen.dart';
import '../../features/session/session_setup_screen.dart';
import '../../features/auth/school_pick_screen.dart';
import '../../features/session/group_select_screen.dart';
import '../../features/session/student_entry_screen.dart';
import '../../features/session/my_tests_screen.dart';
import '../../features/session/results_screen.dart';
import '../../features/session/student_settings_screen.dart';
import '../../features/session/student_help_screen.dart';
import '../../features/session/student_certificates_screen.dart';
import '../../features/session/student_home_screen.dart';
import '../../features/session/student_messages_screen.dart';
import '../../shared/widgets/student_shell.dart';
import '../models/models.dart';

// Test screens
import '../../features/offline/offline_history_hub_screen.dart';
import '../../features/offline/teacher_lan_monitoring_screen.dart';
import '../../features/test/engine_host_screen.dart';
import '../../features/test/test_screen.dart';
import '../../features/result/result_screen.dart';
import '../../features/test/confirm_screen.dart';

// Diagnostic kiosk flow
import '../../features/diagnostic/screens/diagnostic_school_select_screen.dart';
import '../../features/diagnostic/screens/diagnostic_session_setup_screen.dart';
import '../../features/diagnostic/screens/diagnostic_class_select_screen.dart';
import '../../features/diagnostic/screens/diagnostic_student_select_screen.dart';
import '../../features/diagnostic/screens/diagnostic_test_runner_screen.dart';
import '../../features/diagnostic/screens/diagnostic_finished_screen.dart';
import '../../features/diagnostic/widgets/diagnostic_locale_shell.dart';

/// Reads the Riverpod container from a leaf `GoRoute.builder`'s own
/// [BuildContext] (not the outer `goRouterProvider`'s `ref`, which is only
/// valid at router-construction time) — same pattern login_screen.dart uses
/// to write [currentStudentSessionProvider].
ProviderContainer _ref(BuildContext context) =>
    ProviderScope.containerOf(context);

/// Route-level guard: bounces to the login screen when a route that needs
/// `extra[...]` values is rebuilt without them (e.g. pushed by bare path),
/// instead of throwing "type 'Null' is not a subtype of ..." from the builder.
GoRouterRedirect _requireExtra(List<String> keys) => (context, state) {
      final extra = state.extra;
      final ok = extra is Map && keys.every((k) => extra[k] != null);
      return ok ? null : '/';
    };

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
          path: '/school_select',
          builder: (context, state) => const SchoolPickScreen()),
      GoRoute(
          path: '/session_setup',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return SessionSetupScreen(
              testKey: extra['testKey'] as String? ?? '',
            );
          }),
      GoRoute(
          path: '/group_select/:schoolCode',
          builder: (context, state) {
            final schoolCode = state.pathParameters['schoolCode'] ?? '';
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return GroupSelectScreen(
              schoolCode: schoolCode,
              schoolLabel: extra['schoolLabel'] as String? ?? '',
              schoolId: extra['schoolId'] as String? ?? '',
              // A school without groups falls back to the test the proctor
              // tapped (no fallback = dead end for a guruhsiz maktab).
              fallbackEntry: _ref(context).read(selectedCatalogEntryProvider),
            );
          }),
      GoRoute(
          path: '/student_entry',
          // session_setup_screen.dart sets [currentSessionProvider] and
          // pushes this path WITHOUT extra; fall back to the provider and
          // only bounce to login when neither source has a session.
          redirect: (context, state) {
            final extra = state.extra;
            final fromExtra = extra is Map ? extra['session'] : null;
            return fromExtra == null && ref.read(currentSessionProvider) == null
                ? '/'
                : null;
          },
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return StudentEntryScreen(
              session: extra['session'] as TestSession? ??
                  _ref(context).read(currentSessionProvider)!,
              preselectedGroup: extra['preselectedGroup'],
            );
          }),

      // Additional screens mapped properly
      // The 5 student-cabinet screens (kStudentBranchPaths order —
      // student_shell.dart/student_sidebar.dart index into this by path).
      // IndexedStack branches: switching tabs no longer rebuilds the shell
      // or triggers a GoRouter page transition, and each branch keeps its
      // own scroll/data-fetch state alive in the background (was the nav
      // "slайд" bug — see student_shell.dart's file header).
      //
      // `extra['session']` is only present on the FIRST navigation into a
      // branch (e.g. straight from login) — `goBranch` (sidebar taps) does
      // not carry `extra`, so every leaf here falls back to
      // [currentStudentSessionProvider] (written by login_screen.dart)
      // when `extra` doesn't have it, instead of crashing on a null
      // required `session` param.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            StudentShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/my_tests',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>? ?? {};
                  return MyTestsScreen(
                    session: extra['session'] as StudentSession? ??
                        _ref(context).read(currentStudentSessionProvider)!,
                    offline: extra['offline'] ?? false,
                  );
                }),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/results',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>? ?? {};
                  return ResultsScreen(
                    session: extra['session'] as StudentSession? ??
                        _ref(context).read(currentStudentSessionProvider)!,
                  );
                }),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/settings',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>? ?? {};
                  return StudentSettingsScreen(
                    session: extra['session'] as StudentSession? ??
                        _ref(context).read(currentStudentSessionProvider)!,
                  );
                }),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/help',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>? ?? {};
                  return StudentHelpScreen(
                    session: extra['session'] as StudentSession? ??
                        _ref(context).read(currentStudentSessionProvider)!,
                  );
                }),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/certificates',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>? ?? {};
                  return StudentCertificatesScreen(
                    session: extra['session'] as StudentSession? ??
                        _ref(context).read(currentStudentSessionProvider)!,
                  );
                }),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/home',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>? ?? {};
                  return StudentHomeScreen(
                    session: extra['session'] as StudentSession? ??
                        _ref(context).read(currentStudentSessionProvider)!,
                  );
                }),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/messages',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>? ?? {};
                  return StudentMessagesScreen(
                    session: extra['session'] as StudentSession? ??
                        _ref(context).read(currentStudentSessionProvider)!,
                  );
                }),
          ]),
        ],
      ),
      GoRoute(
          path: '/history',
          builder: (context, state) {
            // Task 4: wraps the existing (unmodified-internally, now
            // embeddable) HistoryScreen as one tab of a 2-tab hub, alongside
            // the new diagnostic-attempt history — same destination, no new
            // button anywhere (locked navigation decision).
            return const OfflineHistoryHubScreen();
          }),
      GoRoute(
          path: '/lan_hub',
          builder: (context, state) => const TeacherLanMonitoringScreen()),
      GoRoute(
          path: '/engine_host',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return EngineHostScreen(
              testData: extra['testData'] ?? const {},
              variant: extra['variant'] ?? 1,
              firstName: extra['firstName'] ?? '',
              lastName: extra['lastName'] ?? '',
              school: extra['school'] ?? '',
              group: extra['group'],
              groupId: extra['groupId'],
              grade: extra['grade'],
              studentId: extra['studentId'] ?? '',
            );
          }),
      GoRoute(
          path: '/test',
          redirect: _requireExtra(['session', 'package']),
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return TestScreen(
              session: extra['session'],
              package: extra['package'],
              questions: extra['questions'] ?? const [],
            );
          }),
      GoRoute(
          path: '/result',
          redirect: _requireExtra(['session', 'package', 'result']),
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return ResultScreen(
              session: extra['session'],
              package: extra['package'],
              result: extra['result'],
              synced: extra['synced'] ?? false,
              xpEarned: extra['xpEarned'] ?? 0,
              wrongAnswers: extra['wrongAnswers'] ?? const [],
            );
          }),
      GoRoute(
          path: '/confirm',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return ConfirmScreen(
              session: extra['session'],
              package: extra['package'],
            );
          }),
      GoRoute(
          path: '/diagnostic_school_select',
          builder: (context, state) => const DiagnosticSchoolSelectScreen()),
      GoRoute(
          path: '/diagnostic_session_setup',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return DiagnosticSessionSetupScreen(
              schoolId: extra['schoolId'] as String? ?? '',
              schoolName: extra['schoolName'] as String? ?? '',
              schoolCode: extra['schoolCode'] as String? ?? '',
              expectedPin: extra['expectedPin'] as String? ?? '',
            );
          }),
      GoRoute(
          path: '/diagnostic_class_select',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return DiagnosticClassSelectScreen(
              schoolId: extra['schoolId'] as String? ?? '',
              schoolName: extra['schoolName'] as String? ?? '',
              schoolCode: extra['schoolCode'] as String? ?? '',
            );
          }),
      ShellRoute(
        builder: (context, state, child) => DiagnosticLocaleShell(child: child),
        routes: [
          GoRoute(
              path: '/diagnostic_student_select',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return DiagnosticStudentSelectScreen(
                  schoolId: extra['schoolId'] as String? ?? '',
                  schoolName: extra['schoolName'] as String? ?? '',
                  schoolCode: extra['schoolCode'] as String? ?? '',
                  classLabel: extra['classLabel'] as String? ?? '',
                  language: extra['language'] as String? ?? 'uz',
                  hasWebTest: extra['hasWebTest'] as bool? ?? false,
                  webTestKey: extra['webTestKey'] as String? ?? '',
                );
              }),
          GoRoute(
              path: '/diagnostic_test_runner',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                final rawPrefetched = extra['prefetchedSubjects'];
                final rawAllSubjects = extra['prefetchedAllSubjects'];
                return DiagnosticTestRunnerScreen(
                  attemptId: extra['attemptId'] as String? ?? '',
                  studentName: extra['studentName'] as String? ?? '',
                  grade: extra['grade'] as int? ?? 1,
                  schoolCode: extra['schoolCode'] as String? ?? '',
                  language: extra['language'] as String? ?? 'uz',
                  schoolName: extra['schoolName'] as String? ?? '',
                  classLabel: extra['classLabel'] as String? ?? '',
                  schoolId: extra['schoolId'] as String? ?? '',
                  hasWebTest: extra['hasWebTest'] as bool? ?? false,
                  webTestKey: extra['webTestKey'] as String? ?? '',
                  prefetchedSubjects: rawPrefetched is Map
                      ? rawPrefetched.map((k, v) => MapEntry(
                          k.toString(), Map<String, dynamic>.from(v as Map)))
                      : null,
                  prefetchedAllSubjects: rawAllSubjects is List
                      ? rawAllSubjects.map((e) => e.toString()).toList()
                      : null,
                );
              }),
          GoRoute(
              path: '/diagnostic_finished',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return DiagnosticFinishedScreen(
                  studentName: extra['studentName'] as String?,
                  subjectsCompleted:
                      (extra['subjectsCompleted'] as List?)?.cast<String>() ??
                          const [],
                  schoolId: extra['schoolId'] as String? ?? '',
                  schoolName: extra['schoolName'] as String? ?? '',
                  schoolCode: extra['schoolCode'] as String? ?? '',
                  classLabel: extra['classLabel'] as String? ?? '',
                  language: extra['language'] as String? ?? '',
                  hasWebTest: extra['hasWebTest'] as bool? ?? false,
                  webTestKey: extra['webTestKey'] as String? ?? '',
                );
              }),
        ],
      ),
      GoRoute(
          path: '/widget_route',
          builder: (context, state) {
            // Fallback for any other widget if ever passed via extra, but we shouldn't use this!
            return Scaffold(
                body: Center(
                    child: Text(AppLocalizations.of(context)!.routeNotFound)));
          }),
    ],
  );
});
