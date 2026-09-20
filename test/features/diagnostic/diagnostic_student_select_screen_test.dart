import 'dart:async';

import 'package:alochi_monitoring/core/db/diagnostic_package_cache.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_student_select_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _students = <Map<String, dynamic>>[
  {'attempt_id': 'att-1', 'student_name': 'Aliyev Ali', 'session_grade': 4},
];

Widget _wrap(Widget screen, {void Function(Object? extra)? onNavigate}) {
  final router = GoRouter(
    initialLocation: '/select',
    routes: [
      GoRoute(path: '/select', builder: (_, __) => screen),
      GoRoute(
        path: '/diagnostic_test_runner',
        builder: (_, state) {
          onNavigate?.call(state.extra);
          return const Scaffold(body: Text('RUNNER'));
        },
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
  // Fresh in-memory DB per test (not setUpAll/tearDownAll) — several of
  // these tests reuse the same 'att-1' attempt_id, and a DB shared across
  // the whole file let one test's disk writes leak into the next.
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DiagnosticPackageCache.openInMemory();
  });

  tearDown(() => DiagnosticPackageCache.reset());

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
      'tapping a student card immediately warms the peek cache from disk, '
      'before any network call resolves', (tester) async {
    // Simulates "app was fully closed and reopened" — a previous session
    // already peeked 'math' for this attempt and it's sitting on disk.
    await DiagnosticPackageCache.putSubjectList('att-1', ['math']);
    await DiagnosticPackageCache.put('att-1', 'math', {
      'fixed_variant': true,
      'questions': [
        {'question_id': 'q1', 'question_text': 'Savol 1'}
      ],
    });

    // Both network calls hang forever — proves the runner is reachable with
    // a warm subject list/peek package WITHOUT waiting on the network.
    final availableSubjectsGate = Completer<Map<String, dynamic>>();
    final peekGate = Completer<Map<String, dynamic>>();

    Object? capturedExtra;
    await tester.pumpWidget(_wrap(
      DiagnosticStudentSelectScreen(
        schoolId: 's1',
        schoolName: 'Maktab 1',
        classLabel: '4-A',
        language: 'uz',
        listStudentsOverride: (schoolId, classLabel) async =>
            (_students, false),
        availableSubjectsOverride: (grade, {String language = 'uz'}) =>
            availableSubjectsGate.future,
        peekSubjectOverride: ({required attemptId, required subject}) =>
            peekGate.future,
      ),
      onNavigate: (extra) => capturedExtra = extra,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    // Let the disk-read microtasks flush WITHOUT ever letting the (hung)
    // network Completers resolve.
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('RUNNER'), findsOneWidget);
    final extra = capturedExtra as Map<String, dynamic>;
    expect(extra['prefetchedAllSubjects'], ['math']);
    final prefetched =
        extra['prefetchedSubjects'] as Map<String, Map<String, dynamic>>;
    expect(prefetched['math']!['fixed_variant'], isTrue);
  });
}
