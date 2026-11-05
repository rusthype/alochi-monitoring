import 'dart:io';

import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_pin_verifier.dart';
import 'package:alochi_monitoring/features/diagnostic/dialogs/diagnostic_export_pin_dialog.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Future<DiagnosticPinResult> Function(String pin) verify,
    {void Function(bool?)? onResult}) {
  return MaterialApp(
    locale: const Locale('uz'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => onResult
              ?.call(await showDiagnosticExportPinDialog(context, verify: verify)),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<AppLocalizations> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return AppLocalizations.of(
      tester.element(find.byType(DiagnosticExportPinDialog)))!;
}

void main() {
  test('the hardcoded export PIN is gone', () {
    final src = File('lib/features/diagnostic/dialogs/diagnostic_export_pin_dialog.dart')
        .readAsStringSync();
    expect(src, isNot(contains('kDiagnosticExportPin')));
    expect(src, isNot(contains('0555')));
  });

  testWidgets('a rejected PIN shows the matching error and stays open',
      (tester) async {
    final typed = <String>[];
    var next = DiagnosticPinResult.wrong;
    bool? popped;
    await tester.pumpWidget(_wrap((pin) async {
      typed.add(pin);
      return next;
    }, onResult: (r) => popped = r));
    final l10n = await _open(tester);

    final expected = {
      DiagnosticPinResult.wrong: l10n.incorrectPin,
      DiagnosticPinResult.throttled: l10n.tooManyAttempts,
      DiagnosticPinResult.noInternet: l10n.connectionError,
      DiagnosticPinResult.error: l10n.serverErrorRetry,
    };
    for (final e in expected.entries) {
      next = e.key;
      await tester.enterText(find.byType(TextField), '1111');
      await tester.tap(find.text(l10n.confirmBtn));
      await tester.pumpAndSettle();
      expect(find.text(e.value), findsOneWidget, reason: '${e.key}');
      expect(find.byType(DiagnosticExportPinDialog), findsOneWidget);
    }
    expect(typed, everyElement('1111'));
    expect(popped, isNull);
  });

  testWidgets('an accepted PIN pops true', (tester) async {
    bool? popped;
    await tester.pumpWidget(
        _wrap((_) async => DiagnosticPinResult.ok, onResult: (r) => popped = r));
    final l10n = await _open(tester);
    await tester.enterText(find.byType(TextField), '4821');
    await tester.tap(find.text(l10n.confirmBtn));
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticExportPinDialog), findsNothing);
    expect(popped, isTrue);
  });

  testWidgets('Bekor qilish dismisses without popping true', (tester) async {
    bool? popped = true;
    var called = false;
    await tester.pumpWidget(_wrap((_) async {
      called = true;
      return DiagnosticPinResult.ok;
    }, onResult: (r) => popped = r));
    final l10n = await _open(tester);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticExportPinDialog), findsNothing);
    expect(popped, isNull);
    expect(called, isFalse);
  });
}
