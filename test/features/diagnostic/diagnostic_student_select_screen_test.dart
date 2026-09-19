import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_student_select_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _students = <Map<String, dynamic>>[
  {'attempt_id': 'att-1', 'student_name': 'Aliyev Ali', 'session_grade': 4},
];

Widget _wrap(Widget screen) {
  final router = GoRouter(
    initialLocation: '/select',
    routes: [
      GoRoute(path: '/select', builder: (_, __) => screen),
      GoRoute(
        path: '/diagnostic_test_runner',
        builder: (_, state) => const Scaffold(body: Text('RUNNER')),
      ),
    ],
  );
  return MaterialApp.router(
    routerConfig: router,
    locale: const Locale('uz'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

void main() {
  testWidgets(
      'pressing Enter with a student selected navigates the same as tapping '
      'the start CTA', (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (_students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
          {'subjects': <String>[]},
      peekSubjectOverride: ({required attemptId, required subject}) async =>
          {'fixed_variant': false},
    )));
    await tester.pumpAndSettle();

    // Nothing selected yet — Enter must do nothing.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('RUNNER'), findsNothing);

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('RUNNER'), findsOneWidget);
  });

  testWidgets('NumpadEnter also triggers start once a student is selected',
      (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (_students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
          {'subjects': <String>[]},
      peekSubjectOverride: ({required attemptId, required subject}) async =>
          {'fixed_variant': false},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pumpAndSettle();

    expect(find.text('RUNNER'), findsOneWidget);
  });

  testWidgets(
      'tapping a student card fires the background subject-peek prefetch',
      (tester) async {
    var availableSubjectsCalls = 0;
    var peekCalls = <String>[];
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (_students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async {
        availableSubjectsCalls++;
        return {
          'subjects': ['math', 'english']
        };
      },
      peekSubjectOverride: ({required attemptId, required subject}) async {
        peekCalls.add(subject);
        return {'fixed_variant': false};
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pumpAndSettle();

    expect(availableSubjectsCalls, equals(1));
    expect(peekCalls, containsAll(['math', 'english']));
  });
}
