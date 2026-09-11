import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_scratchpad.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('uz'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('shows a CustomPaint drawing surface', (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticScratchpad(onClose: () {})));
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('drag gesture adds a stroke (repainted after Clear)',
      (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticScratchpad(onClose: () {})));

    final canvasFinder = find.byKey(const Key('diagnosticScratchpadCanvas'));
    await tester.dragFrom(
      tester.getCenter(canvasFinder),
      const Offset(40, 0),
    );
    await tester.pump();

    // Once a stroke exists, Undo/Tozalash become enabled.
    final clearButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Tozalash'),
    );
    expect(clearButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Tozalash'));
    await tester.pump();

    final clearButtonAfter = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Tozalash'),
    );
    expect(clearButtonAfter.onPressed, isNull);
  });

  testWidgets('close button calls onClose', (tester) async {
    var closed = false;
    await tester
        .pumpWidget(_wrap(DiagnosticScratchpad(onClose: () => closed = true)));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(closed, isTrue);
  });
}
