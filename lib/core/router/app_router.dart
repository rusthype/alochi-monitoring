import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/login_screen.dart';
import '../widgets/error_screen.dart';
import '../../features/session/session_setup_screen.dart';
import '../../features/session/group_select_screen.dart';
import '../../features/session/student_entry_screen.dart';
import '../../features/session/my_tests_screen.dart';

// Test screens
import '../../features/test/package_screen.dart';
import '../../features/local_test/history_screen.dart';
import '../../features/local_test/local_grade_screen.dart';
import '../../features/combined/combined_screen.dart';
import '../../features/test/engine_host_screen.dart';
import '../../features/test/test_screen.dart';
import '../../features/result/result_screen.dart';
import '../../features/unit1/unit1_runner.dart';
import '../../features/interhouse/interhouse_runner.dart';
import '../../features/combined/combined_runner.dart';
import '../../features/test/confirm_screen.dart';
import '../../features/local_test/local_result_screen.dart';
import '../../features/local_test/local_test_screen.dart';
import '../../features/unit1/unit1_screen.dart';

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
            );
          }),
      GoRoute(
          path: '/student_entry',
          builder: (context, state) {
             final extra = state.extra as Map<String, dynamic>? ?? {};
             return StudentEntryScreen(
               session: extra['session'],
               preselectedGroup: extra['preselectedGroup'],
             );
          }),
      
      // Additional screens mapped properly
      GoRoute(
          path: '/package', builder: (context, state) {
             final extra = state.extra as Map<String, dynamic>? ?? {};
             return PackageScreen(
               session: extra['session'],
               offline: extra['offline'] ?? false,
             );
          }),
      GoRoute(
          path: '/my_tests', builder: (context, state) {
             final extra = state.extra as Map<String, dynamic>? ?? {};
             return MyTestsScreen(
               session: extra['session'],
               offline: extra['offline'] ?? false,
             );
          }),
      GoRoute(
          path: '/history', builder: (context, state) {
             return const HistoryScreen();
          }),
      GoRoute(
          path: '/local_grade', builder: (context, state) {
             return const LocalGradeScreen();
          }),
      GoRoute(
          path: '/combined', builder: (context, state) {
             return const CombinedScreen();
          }),
      GoRoute(
          path: '/engine_host', builder: (context, state) {
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
          path: '/test', builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return TestScreen(
              session: extra['session'],
              package: extra['package'],
              questions: extra['questions'] ?? const [],
            );
          }),
      GoRoute(
          path: '/result', builder: (context, state) {
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
          path: '/local_test',
          builder: (context, state) {
             final extra = state.extra as Map<String, dynamic>? ?? {};
             return LocalTestScreen(
               firstName: extra['firstName'] ?? '',
               lastName: extra['lastName'] ?? '',
               group: extra['group'] ?? '',
               school: extra['school'] ?? '',
               grade: extra['grade'] ?? 0,
               variant: extra['variant'] ?? 1,
               questions: extra['questions'] ?? const [],
             );
          }),
      GoRoute(
          path: '/unit1', builder: (context, state) => const Unit1Screen()),
      GoRoute(
          path: '/unit1_result',
          builder: (context, state) {
             final extra = state.extra as Map<String, dynamic>? ?? {};
             return Unit1ResultScreen(
               studentName: extra['studentName'] ?? '',
               firstName: extra['firstName'] ?? '',
               lastName: extra['lastName'] ?? '',
               school: extra['school'] ?? '',
               variant: extra['variant'] ?? 1,
               correct: extra['correct'] ?? 0,
               total: extra['total'] ?? 0,
               pct: extra['pct'] ?? 0,
               vocabOk: extra['vocabOk'] ?? 0,
               grammarOk: extra['grammarOk'] ?? 0,
               spellingOk: extra['spellingOk'] ?? 0,
               sentenceOk: extra['sentenceOk'] ?? 0,
               readingOk: extra['readingOk'] ?? 0,
               answers: extra['answers'] ?? const [],
               detail: extra['detail'] ?? const {},
             );
          }),
      GoRoute(
          path: '/interhouse',
          builder: (context, state) {
             final extra = state.extra as Map<String, dynamic>? ?? {};
             return InterhouseRunner(
               session: extra['session'],
               isOnline: extra['isOnline'] ?? false,
               packageId: extra['packageId'] ?? 0,
               variant: extra['variant'] ?? 1,
               testData: extra['testData'],
             );
          }),
      GoRoute(
          path: '/combined_runner',
          builder: (context, state) {
             final extra = state.extra as Map<String, dynamic>? ?? {};
             return CombinedRunner(
               firstName: extra['firstName'] ?? '',
               lastName: extra['lastName'] ?? '',
               school: extra['school'] ?? '',
               variant: extra['variant'] ?? 1,
               mathQuestions: extra['mathQuestions'] ?? const [],
               testData: extra['testData'],
             );
          }),
      GoRoute(
          path: '/combined_result',
          builder: (context, state) {
             final extra = state.extra as Map<String, dynamic>? ?? {};
             return CombinedResultScreen(
               studentName: extra['studentName'] ?? '',
               firstName: extra['firstName'] ?? '',
               lastName: extra['lastName'] ?? '',
               school: extra['school'] ?? '',
               variant: extra['variant'] ?? 1,
               mathOk: extra['mathOk'] ?? 0,
               engOk: extra['engOk'] ?? 0,
               vocabOk: extra['vocabOk'] ?? 0,
               grammarOk: extra['grammarOk'] ?? 0,
               spellingOk: extra['spellingOk'] ?? 0,
               sentenceOk: extra['sentenceOk'] ?? 0,
               readingOk: extra['readingOk'] ?? 0,
               totalOk: extra['totalOk'] ?? 0,
               pct: extra['pct'] ?? 0,
               timeStr: extra['timeStr'] ?? '',
               answers: extra['answers'] ?? const [],
               detail: extra['detail'] ?? const {},
             );
          }),
      GoRoute(
          path: '/confirm', builder: (context, state) {
             final extra = state.extra as Map<String, dynamic>? ?? {};
             return ConfirmScreen(
               session: extra['session'],
               package: extra['package'],
             );
          }),
      GoRoute(
          path: '/local_result',
          builder: (context, state) {
             final extra = state.extra as Map<String, dynamic>? ?? {};
             return LocalResultScreen(
               firstName: extra['firstName'] ?? '',
               lastName: extra['lastName'] ?? '',
               group: extra['group'] ?? '',
               school: extra['school'] ?? '',
               grade: extra['grade'] ?? 0,
               variant: extra['variant'] ?? 1,
               questions: extra['questions'] ?? const [],
               answers: extra['answers'] ?? const {},
               mathOk: extra['mathOk'] ?? 0,
               engOk: extra['engOk'] ?? 0,
               pct: extra['pct'] ?? 0,
               topicScores: extra['topicScores'] ?? const {},
             );
          }),
      GoRoute(
          path: '/widget_route',
          builder: (context, state) {
             // Fallback for any other widget if ever passed via extra, but we shouldn't use this!
             return Scaffold(body: Center(child: Text(AppLocalizations.of(context)!.routeNotFound)));
          }),
    ],
  );
});
