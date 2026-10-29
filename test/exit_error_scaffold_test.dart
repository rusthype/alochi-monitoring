// A child must never get stuck on a dead-end screen of the exam flow
// (pack with no variants at all -> TestEngine has no sections; a mere key
// mismatch now falls back to the nearest variant instead).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

TestSpec _spec() => TestSpec.fromJson({
      'test_key': 'k',
      'title': 'T',
      'grade': 5,
      'version': 1,
      'parts': ['Math'],
      'variants': <String, dynamic>{},
    });

// the spec has no variants -> sections empty (no fallback possible).
Widget _engine() => TestEngine(
      spec: _spec(),
      variant: 1,
      firstName: 'I',
      lastName: 'F',
      school: '1',
      duration: const Duration(minutes: 5),
      onComplete: (_, __) {},
    );

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('not-found state pops back via button, AppBar arrow and Esc',
      (tester) async {
    for (final how in ['button', 'arrow', 'esc']) {
      await tester.pumpWidget(_app(Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(c)
                .push(MaterialPageRoute(builder: (_) => _engine())),
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      expect(find.text(l10n.testDataNotFoundMsg), findsOneWidget);
      expect(
          find.widgetWithText(ElevatedButton, l10n.backButton), findsOneWidget);

      if (how == 'button') {
        await tester.tap(find.widgetWithText(ElevatedButton, l10n.backButton));
      } else if (how == 'arrow') {
        await tester.tap(find.byType(BackButton));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget, reason: how);
      expect(find.text(l10n.testDataNotFoundMsg), findsNothing, reason: how);
    }
  });

  testWidgets('with nothing to pop the back button goes to /', (tester) async {
    final router = GoRouter(initialLocation: '/test', routes: [
      GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
      GoRoute(path: '/test', builder: (_, __) => _engine()),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    await tester.tap(find.widgetWithText(ElevatedButton, l10n.backButton));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });
}
