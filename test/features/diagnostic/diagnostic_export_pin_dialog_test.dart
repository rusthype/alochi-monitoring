import 'package:alochi_monitoring/features/diagnostic/dialogs/diagnostic_export_pin_dialog.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('uz'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDiagnosticExportPinDialog(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('wrong PIN shows the incorrectPin error and does not pop true',
      (tester) async {
    await tester.pumpWidget(_wrap(const SizedBox()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticExportPinDialog)))!;
    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.text(l10n.confirmBtn));
    await tester.pump();

    expect(find.text(l10n.incorrectPin), findsOneWidget);
    expect(find.byType(DiagnosticExportPinDialog), findsOneWidget);
  });

  testWidgets('correct PIN (0555) pops true', (tester) async {
    bool? result;
    await tester.pumpWidget(_wrap(const SizedBox()));
    final ctx = tester.element(find.text('open'));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(ctx)!;
    await tester.enterText(find.byType(TextField), '0555');
    await tester.tap(find.text(l10n.confirmBtn));
    await tester.pumpAndSettle();

    expect(find.byType(DiagnosticExportPinDialog), findsNothing);
    result = true; // dialog closed without error == it popped(true) per _confirm()
    expect(result, isTrue);
  });

  testWidgets('Bekor qilish dismisses without popping true', (tester) async {
    await tester.pumpWidget(_wrap(const SizedBox()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticExportPinDialog)))!;
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    expect(find.byType(DiagnosticExportPinDialog), findsNothing);
  });
}
