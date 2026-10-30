import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/widgets/pill_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Align(alignment: Alignment.topCenter, child: child)),
    );

void main() {
  testWidgets('title is uppercase, back fires onBack, back label is tooltip',
      (tester) async {
    var backs = 0;
    await tester.pumpWidget(_wrap(PillTopBar(
      title: 'Maktablar',
      onBack: () => backs++,
      trailing: '1/3',
    )));
    expect(find.text('MAKTABLAR'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('Ortga'), findsNothing);
    expect(find.byTooltip('Ortga'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    expect(backs, 1);
  });

  testWidgets('no onBack hides the arrow, no trailing hides the chip',
      (tester) async {
    await tester.pumpWidget(_wrap(const PillTopBar(title: 'x')));
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.byTooltip('Ortga'), findsNothing);
    expect(find.text('1/3'), findsNothing);
  });

  testWidgets('actions render with tooltip and fire', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(PillTopBar(
      title: 'x',
      actions: [
        PillTopBarAction(
          icon: Icons.refresh_rounded,
          tooltip: 'Yangilash',
          onPressed: () => taps++,
        ),
      ],
    )));
    expect(find.byTooltip('Yangilash'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    expect(taps, 1);
  });
}
