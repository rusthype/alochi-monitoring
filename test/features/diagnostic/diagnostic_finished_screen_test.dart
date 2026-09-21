import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_finished_screen.dart';

// DiagnosticFinishedScreen now reads localeProvider (via
// ProviderScope.containerOf) to pick the display script for the student
// name greeting, so _wrap needs a real ProviderScope ancestor, matching the
// app's actual root (main.dart). Set in main()'s setUp.
late SharedPreferences _prefs;

Widget _wrap([Widget screen = const DiagnosticFinishedScreen()]) {
  final router = GoRouter(
    initialLocation: '/diagnostic_finished',
    routes: [
      GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('HOME'))),
      GoRoute(
        path: '/diagnostic_finished',
        builder: (context, state) => screen,
      ),
      GoRoute(
        path: '/diagnostic_student_select',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return Scaffold(
            body: Text('STUDENT_SELECT:${extra['schoolId']}:'
                '${extra['classLabel']}:${extra['schoolName']}:'
                '${extra['schoolCode']}:${extra['language']}:'
                '${extra['hasWebTest']}:${extra['webTestKey']}'),
          );
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
  });

  testWidgets('never shows score/percentage-like text', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();

    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining(RegExp(r'\d+\s*/\s*\d+')), findsNothing);

    // avoid stray timers after test ends
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('renders title, subtitle and info note', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();

    expect(find.text('Diagnostika yakunlandi'), findsOneWidget);
    expect(
      find.text("Rahmat! Natijalar o'qituvchiga yuboriladi."),
      findsOneWidget,
    );
    expect(
      find.text(
        "Natijalar maktab ma'muriyati va o'qituvchilar uchun tayyorlanmoqda.",
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('tapping the return button navigates home immediately',
      (tester) async {
    await tester.pumpWidget(_wrap());
    // let the entrance animation (600ms) fully settle before tapping, so the
    // tap isn't landing on a still-animating (near-zero-scale) hit-test area.
    // Note: pumpAndSettle() can't be used here — the particle/pulse
    // controllers repeat forever and never "settle".
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Bosh sahifaga qaytish'), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    // pump for a short duration only — well short of the 15s auto-return
    // timer — so navigation can only be caused by the button tap itself.
    // Long enough to let the route's page-transition animation finish.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('auto-returns home after the 15s countdown elapses',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();

    expect(find.text('HOME'), findsNothing);

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('shows personalized greeting when studentName is set',
      (tester) async {
    await tester.pumpWidget(
        _wrap(const DiagnosticFinishedScreen(studentName: 'ALIYEV VALI OGLI')));
    await tester.pump();
    expect(find.textContaining('Vali'), findsOneWidget); // patronymic stripped
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('hides subjects pill when subjectsCompleted is empty',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();
    expect(find.byIcon(Icons.menu_book_rounded), findsNothing);
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('shows subjects pill with count when non-empty', (tester) async {
    await tester.pumpWidget(_wrap(const DiagnosticFinishedScreen(
        subjectsCompleted: ['math', 'english'])));
    await tester.pump();
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('pause button toggles to resume label', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();
    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticFinishedScreen)))!;
    expect(find.text(l10n.diagnosticFinishedPauseBtn), findsOneWidget);
    await tester.tap(find.text(l10n.diagnosticFinishedPauseBtn));
    await tester.pump();
    expect(find.text(l10n.diagnosticFinishedResumeBtn), findsOneWidget);
    // pausing must actually stop the countdown from firing navigation
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets(
      'neutral title still renders when studentName is null (no regression)',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();
    expect(find.text('Diagnostika yakunlandi'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets(
      'tapping return with full class context navigates to student-select '
      'for that class, not home', (tester) async {
    await tester.pumpWidget(_wrap(const DiagnosticFinishedScreen(
      schoolId: 'sch-1',
      schoolName: 'Maktab 1',
      schoolCode: 'M1',
      classLabel: '5-A',
      language: 'ru',
      hasWebTest: true,
      webTestKey: 'wt-1',
    )));
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('HOME'), findsNothing);
    expect(
      find.text('STUDENT_SELECT:sch-1:5-A:Maktab 1:M1:ru:true:wt-1'),
      findsOneWidget,
    );
  });

  testWidgets(
      'the 15s auto-return countdown also navigates to student-select when '
      'class context is provided', (tester) async {
    await tester.pumpWidget(_wrap(const DiagnosticFinishedScreen(
      schoolId: 'sch-1',
      schoolName: 'Maktab 1',
      schoolCode: 'M1',
      classLabel: '5-A',
      language: 'ru',
      hasWebTest: true,
      webTestKey: 'wt-1',
    )));
    await tester.pump();

    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsNothing);
    expect(
      find.text('STUDENT_SELECT:sch-1:5-A:Maktab 1:M1:ru:true:wt-1'),
      findsOneWidget,
    );
  });
}
