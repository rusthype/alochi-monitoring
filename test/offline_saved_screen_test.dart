// The offline result screen must never show a score (decision 2), and must be
// honest when the answers could not be stored.
import 'package:alochi_monitoring/features/offline/offline_saved_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  for (final locale in const [Locale('uz'), Locale('ru')]) {
    testWidgets('saved screen (${locale.languageCode}): no score, next button',
        (tester) async {
      var next = 0;
      await tester.pumpWidget(_wrap(
          OfflineSavedScreen(
              firstName: 'Ali', lastName: 'Valiyev', onNext: () => next++),
          locale));
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      expect(find.text(l10n.usbSavedTitle), findsOneWidget);
      expect(find.text('Valiyev Ali'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining(RegExp(r'\d+\s*/\s*\d+')), findsNothing);
      await tester.tap(find.text(l10n.nextStudent));
      expect(next, 1);
    });
  }

  testWidgets('failed save says so and offers retry instead of "saved"',
      (tester) async {
    var retried = 0;
    await tester.pumpWidget(_wrap(
        OfflineSavedScreen(
            firstName: 'Ali',
            lastName: 'Valiyev',
            onNext: () {},
            onRetry: () => retried++),
        const Locale('uz')));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(find.text(l10n.usbSavedTitle), findsNothing);
    expect(find.text(l10n.resultNotSavedError), findsOneWidget);
    await tester.tap(find.text(l10n.retry));
    expect(retried, 1);
  });
}
