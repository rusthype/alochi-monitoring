import 'dart:async';

import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_prefetch_cache.dart';
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
  setUp(() => DiagnosticPrefetchCache.instance.reset());

  testWidgets(
      'prefetch cache survives the State object being destroyed and '
      'recreated (context.go(\'/\') stack reset)', (tester) async {
    // First visit: prefetch att-1 to ready on this screen instance.
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (_students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
        'subjects': ['math']
      },
      peekSubjectOverride: ({required attemptId, required subject}) async =>
          {'fixed_variant': true, 'questions': []},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    // Simulate diagnostic_finished_screen.dart's context.go('/') destroying
    // this whole screen (and, pre-fix, its State-held cache with it), then
    // the operator navigating back into the same class — a brand-new State
    // object. Overrides that THROW if called prove no new network fetch
    // happens: the ready status must come from the surviving singleton.
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (_students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async {
        throw StateError('must not re-fetch: cache should have survived');
      },
      peekSubjectOverride: ({required attemptId, required subject}) async {
        throw StateError('must not re-peek: cache should have survived');
      },
    )));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

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

  testWidgets(
      'student card shows ready badge after a fixed-variant subject '
      'is successfully prefetched', (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (_students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
        'subjects': ['math']
      },
      peekSubjectOverride: ({required attemptId, required subject}) async =>
          {'fixed_variant': true, 'questions': []},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('student card shows error badge when a subject peek throws',
      (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (_students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
        'subjects': ['math']
      },
      peekSubjectOverride: ({required attemptId, required subject}) async {
        throw Exception('network down');
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets(
      'student card shows online-only badge (no ready check) for CAT-only '
      'subjects', (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (_students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
        'subjects': ['math']
      },
      peekSubjectOverride: ({required attemptId, required subject}) async =>
          {'fixed_variant': false},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.wifi_tethering), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });

  testWidgets(
      'Barcha testlarni yuklash button prefetches every visible student '
      'sequentially', (tester) async {
    final students = <Map<String, dynamic>>[
      {'attempt_id': 'att-1', 'student_name': 'Aliyev Ali', 'session_grade': 4},
      {
        'attempt_id': 'att-2',
        'student_name': 'Valiyev Vali',
        'session_grade': 4
      },
    ];
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
        'subjects': ['math']
      },
      peekSubjectOverride: ({required attemptId, required subject}) async =>
          {'fixed_variant': true, 'questions': []},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.download_for_offline_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
  });

  testWidgets(
      'Start waits for an in-flight prefetch before navigating to the runner',
      (tester) async {
    final completer = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (_students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
        'subjects': ['math']
      },
      peekSubjectOverride: ({required attemptId, required subject}) =>
          completer.future,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pump();

    await tester.tap(find.text('Diagnostikani boshlash'));
    await tester.pump();
    // Prefetch hali tugamagan — runner ekraniga hali o'tmagan bo'lishi kerak.
    expect(find.text('RUNNER'), findsNothing);

    completer.complete({'fixed_variant': true, 'questions': []});
    await tester.pumpAndSettle();

    expect(find.text('RUNNER'), findsOneWidget);
  });
}
