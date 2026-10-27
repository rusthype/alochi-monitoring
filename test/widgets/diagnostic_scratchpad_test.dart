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

  group('adapts to window size without overlapping the bottom dock', () {
    for (final size in const [
      Size(1280, 720),
      Size(1920, 1080),
      Size(1024, 600),
    ]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(DiagnosticScratchpad(onClose: () {})));

        final rect =
            tester.getRect(find.byKey(const Key('diagnosticScratchpadDialog')));
        expect(rect.bottom,
            lessThanOrEqualTo(size.height - kDiagnosticBottomNavReserve));
        expect(rect.width, lessThanOrEqualTo(kDiagnosticScratchpadMaxWidth));
        // Roomy windows should use most of the space, not a fixed small box.
        expect(rect.width, greaterThan(size.width * 0.6));
        // Canvas buttons stay fully on screen.
        for (final label in ['Tozalash']) {
          final b = tester.getRect(find.widgetWithText(OutlinedButton, label));
          expect(b.bottom,
              lessThanOrEqualTo(size.height - kDiagnosticBottomNavReserve));
        }
        expect(find.widgetWithText(OutlinedButton, 'Tozalash'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
