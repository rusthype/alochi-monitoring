import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_finished_screen.dart';

Widget _wrap() {
  final router = GoRouter(
    initialLocation: '/diagnostic_finished',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('HOME'))),
      GoRoute(
        path: '/diagnostic_finished',
        builder: (context, state) => const DiagnosticFinishedScreen(),
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
}
