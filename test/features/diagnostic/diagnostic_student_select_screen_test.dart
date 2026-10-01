import 'dart:async';

import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_prefetch_cache.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_class_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_student_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_widgets.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _students = <Map<String, dynamic>>[
  {'attempt_id': 'att-1', 'student_name': 'Aliyev Ali', 'session_grade': 4},
];

/// Captures the `extra` map handed to `/diagnostic_test_runner` by the most
/// recent `_wrap()`'d pump, so tests can assert on it without disturbing the
/// existing `find.text('RUNNER')` navigation assertions.
Map<String, dynamic>? lastRunnerExtra;

// DiagnosticStudentSelectScreen now reads localeProvider (via
// ProviderScope.containerOf) to pick the display script for student names,
// so _wrap needs a real ProviderScope ancestor, matching the app's actual
// root (main.dart). Set in main()'s setUp.
late SharedPreferences _prefs;

Widget _wrap(Widget screen) {
  lastRunnerExtra = null;
  final router = GoRouter(
    initialLocation: '/select',
    routes: [
      GoRoute(path: '/select', builder: (_, __) => screen),
      GoRoute(
        path: '/diagnostic_test_runner',
        builder: (_, state) {
          lastRunnerExtra = state.extra as Map<String, dynamic>?;
          return const Scaffold(body: Text('RUNNER'));
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
    DiagnosticPrefetchCache.instance.reset();
  });

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
      'Ortga (back) goes to class-select with the same school context when '
      'there is nothing to pop — not the kiosk home/login screen '
      '(regression: diagnostic_finished_screen.dart\'s context.go() reset '
      'used to strand the operator on home, forcing a pincode re-entry)',
      (tester) async {
    Map<String, dynamic>? classSelectExtra;
    final router = GoRouter(
      // Single-entry stack — mirrors what diagnostic_finished_screen.dart's
      // context.go('/diagnostic_student_select', ...) leaves behind: no
      // school-select/class-select underneath to pop back into.
      initialLocation: '/select',
      routes: [
        GoRoute(
          path: '/select',
          builder: (_, __) => DiagnosticStudentSelectScreen(
            schoolId: 's1',
            schoolName: 'Maktab 1',
            schoolCode: 'M001',
            classLabel: '4-A',
            language: 'uz',
            listStudentsOverride: (schoolId, classLabel) async =>
                (_students, false),
          ),
        ),
        GoRoute(
          path: '/diagnostic_class_select',
          builder: (_, state) {
            classSelectExtra = state.extra as Map<String, dynamic>?;
            return const Scaffold(body: Text('CLASS_SELECT'));
          },
        ),
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
      ],
    );
    lastRunnerExtra = null;
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.matches.length, 1);

    await tester.tap(find.text('Ortga'));
    await tester.pumpAndSettle();

    expect(find.text('CLASS_SELECT'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);
    expect(
      classSelectExtra,
      {'schoolId': 's1', 'schoolName': 'Maktab 1', 'schoolCode': 'M001'},
    );
  });

  testWidgets(
      'the real DiagnosticClassSelectScreen, reached via that same '
      'nothing-to-pop fallback, sends its OWN Ortga to school-select -- not '
      'back into this roster (regression: 2026-10-01 ping-pong loop, where '
      'class-select\'s generic canPop()-pop landed back on student-select '
      'because the fallback above used to push() class-select on top of '
      'this still-live screen instead of go()\'ing to it)', (tester) async {
    final router = GoRouter(
      initialLocation: '/select',
      routes: [
        GoRoute(
          path: '/select',
          builder: (_, __) => DiagnosticStudentSelectScreen(
            schoolId: 's1',
            schoolName: 'Maktab 1',
            schoolCode: 'M001',
            classLabel: '4-A',
            language: 'uz',
            listStudentsOverride: (schoolId, classLabel) async =>
                (_students, false),
          ),
        ),
        GoRoute(
          path: '/diagnostic_class_select',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return DiagnosticClassSelectScreen(
              schoolId: extra['schoolId'] as String? ?? '',
              schoolName: extra['schoolName'] as String? ?? '',
              schoolCode: extra['schoolCode'] as String? ?? '',
            );
          },
        ),
        GoRoute(
          path: '/diagnostic_school_select',
          builder: (_, __) => const Scaffold(body: Text('SCHOOL_SELECT')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pumpAndSettle();

    // Step 1: student-select's own Ortga fallback (nothing to pop) lands on
    // the real class-select screen via go() -- a fresh single-entry stack.
    await tester.tap(find.text('Ortga'));
    await tester.pumpAndSettle();
    // DiagnosticTopBar renders its title via title.toUpperCase().
    expect(find.text('MAKTAB 1'), findsOneWidget); // class-select's title

    // Step 2: class-select's OWN Ortga, with nothing to pop either, must
    // reach school-select -- not bounce back to the student roster.
    await tester.tap(find.text('Ortga'));
    await tester.pumpAndSettle();
    expect(find.text('SCHOOL_SELECT'), findsOneWidget);
    expect(find.text('MAKTAB 1'), findsNothing);
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

  testWidgets(
      'a transient peek failure is retried and the student still ends up '
      'ready, not error', (tester) async {
    var callCount = 0;
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
        callCount++;
        if (callCount == 1) throw Exception('transient network blip');
        return {'fixed_variant': true, 'questions': []};
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(callCount, greaterThan(1));
  });

  testWidgets(
      'a peek failure that persists through every retry still ends up '
      'marked as error, and stops after exactly 3 attempts (regression '
      'guard against an infinite retry loop)', (tester) async {
    var callCount = 0;
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
        callCount++;
        throw Exception('permanent failure');
      },
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(callCount, equals(3));
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
      'bulk prefetch calls availableSubjects only ONCE for the whole class, '
      'not once per student (2026-09-20 incident: this call had no backend '
      'throttle_scope of its own, so N students x 1 call each could exceed '
      'the shared classroom IP\'s rate limit and 429 the last few students)',
      (tester) async {
    final students = <Map<String, dynamic>>[
      {'attempt_id': 'att-1', 'student_name': 'Aliyev Ali', 'session_grade': 4},
      {
        'attempt_id': 'att-2',
        'student_name': 'Valiyev Vali',
        'session_grade': 4
      },
      {
        'attempt_id': 'att-3',
        'student_name': 'Karimov Karim',
        'session_grade': 4
      },
    ];
    var availableSubjectsCalls = 0;
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      listStudentsOverride: (schoolId, classLabel) async => (students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async {
        availableSubjectsCalls++;
        return {
          'subjects': ['math']
        };
      },
      peekSubjectOverride: ({required attemptId, required subject}) async =>
          {'fixed_variant': true, 'questions': []},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.download_for_offline_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(3));
    expect(availableSubjectsCalls, 1);
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

  testWidgets('offline badge clears automatically once connectivity comes back',
      (tester) async {
    var listCalls = 0;
    final connController =
        StreamController<List<ConnectivityResult>>.broadcast();
    addTearDown(connController.close);

    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      connectivityStreamOverride: connController.stream,
      listStudentsOverride: (schoolId, classLabel) async {
        listCalls++;
        return (_students, listCalls == 1);
      },
      availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
          {'subjects': <String>[]},
      peekSubjectOverride: ({required attemptId, required subject}) async =>
          {'fixed_variant': false},
    )));
    await tester.pumpAndSettle();

    // First load came from cache — badge showing.
    expect(find.byType(DiagnosticOfflineBadge), findsOneWidget);

    // Connectivity comes back — screen re-fetches, this time fresh.
    connController.add([ConnectivityResult.wifi]);
    await tester.pumpAndSettle();

    expect(listCalls, 2);
    expect(find.byType(DiagnosticOfflineBadge), findsNothing);
  });

  testWidgets(
      'a selected student stays selected after a reconnect-triggered reload',
      (tester) async {
    var listCalls = 0;
    final connController =
        StreamController<List<ConnectivityResult>>.broadcast();
    addTearDown(connController.close);

    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      classLabel: '4-A',
      language: 'uz',
      connectivityStreamOverride: connController.stream,
      listStudentsOverride: (schoolId, classLabel) async {
        listCalls++;
        return (_students, listCalls == 1);
      },
      availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
          {'subjects': <String>[]},
      peekSubjectOverride: ({required attemptId, required subject}) async =>
          {'fixed_variant': false},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    connController.add([ConnectivityResult.wifi]);
    await tester.pumpAndSettle();

    expect(listCalls, 2);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets(
      'tapping a student to start their test includes schoolId, hasWebTest '
      'and webTestKey in the extra passed to /diagnostic_test_runner',
      (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
      schoolId: 's1',
      schoolName: 'Maktab 1',
      schoolCode: 'M1',
      classLabel: '4-A',
      language: 'uz',
      // hasWebTest: false so tapping starts the CAT test directly, without
      // the CAT-vs-web bottom sheet — that choice flow is exercised by
      // other tests, not the concern here.
      hasWebTest: false,
      webTestKey: 'wt-9',
      listStudentsOverride: (schoolId, classLabel) async => (_students, false),
      availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
          {'subjects': <String>[]},
      peekSubjectOverride: ({required attemptId, required subject}) async =>
          {'fixed_variant': false},
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aliyev Ali'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('RUNNER'), findsOneWidget);
    expect(lastRunnerExtra, isNotNull);
    expect(lastRunnerExtra!['schoolId'], 's1');
    expect(lastRunnerExtra!['hasWebTest'], false);
    expect(lastRunnerExtra!['webTestKey'], 'wt-9');
  });

  group('roster attempt-status badge', () {
    Future<void> pumpWithStatus(
        WidgetTester tester, Map<String, dynamic> student) async {
      await tester.pumpWidget(_wrap(DiagnosticStudentSelectScreen(
        schoolId: 's1',
        schoolName: 'Maktab 1',
        classLabel: '4-A',
        language: 'uz',
        listStudentsOverride: (schoolId, classLabel) async =>
            ([student], false),
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        peekSubjectOverride: ({required attemptId, required subject}) async =>
            {'fixed_variant': true, 'questions': []},
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('completed shows the completed badge, never a score',
        (tester) async {
      await pumpWithStatus(tester, {
        'attempt_id': 'att-1',
        'student_name': 'Aliyev Ali',
        'session_grade': 4,
        'status': 'completed',
      });
      expect(find.textContaining('Topshirildi'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('in_progress shows the in-progress badge', (tester) async {
      await pumpWithStatus(tester, {
        'attempt_id': 'att-1',
        'student_name': 'Aliyev Ali',
        'session_grade': 4,
        'status': 'in_progress',
      });
      expect(find.textContaining('Jarayonda'), findsOneWidget);
    });

    testWidgets(
        'partial shows the next-subject badge using next_subject',
        (tester) async {
      await pumpWithStatus(tester, {
        'attempt_id': 'att-1',
        'student_name': 'Aliyev Ali',
        'session_grade': 4,
        'status': 'partial',
        'next_subject': 'english',
      });
      expect(find.textContaining('Ingliz tili qoldi'), findsOneWidget);
    });

    testWidgets('partial with no next_subject falls back to a generic label',
        (tester) async {
      await pumpWithStatus(tester, {
        'attempt_id': 'att-1',
        'student_name': 'Aliyev Ali',
        'session_grade': 4,
        'status': 'partial',
      });
      expect(find.textContaining('Davom etmoqda'), findsOneWidget);
    });

    testWidgets('not_started renders no attempt-status badge at all',
        (tester) async {
      await pumpWithStatus(tester, {
        'attempt_id': 'att-1',
        'student_name': 'Aliyev Ali',
        'session_grade': 4,
        'status': 'not_started',
      });
      expect(find.textContaining('Topshirildi'), findsNothing);
      expect(find.textContaining('Jarayonda'), findsNothing);
      expect(find.textContaining('qoldi'), findsNothing);
      expect(find.textContaining('Davom etmoqda'), findsNothing);
    });
  });
}
