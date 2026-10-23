import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_bottom_nav.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap({required bool isLast, required bool hasNextSubject}) =>
    MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DiagnosticBottomNav(
          onNext: () {},
          onFinish: () {},
          onEarlyFinish: () {},
          isLast: isLast,
          submitting: false,
          hasNextSubject: hasNextSubject,
        ),
      ),
    );

void main() {
  testWidgets('not last: plain next', (tester) async {
    await tester.pumpWidget(_wrap(isLast: false, hasNextSubject: true));
    expect(find.text('Keyingi'), findsOneWidget);
    expect(find.text("Keyingi testga o'tish"), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
  });

  testWidgets('last with following test: go-to-next-test label + skip icon',
      (tester) async {
    await tester.pumpWidget(_wrap(isLast: true, hasNextSubject: true));
    expect(find.text("Keyingi testga o'tish"), findsOneWidget);
    expect(find.text('Keyingi'), findsNothing);
    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('last final test: finish label + flag icon', (tester) async {
    await tester.pumpWidget(_wrap(isLast: true, hasNextSubject: false));
    expect(find.text('Testni tugatish'), findsOneWidget);
    expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
    expect(find.text('Keyingi'), findsNothing);
  });

  testWidgets('ru labels fit without overflow at narrow width', (tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DiagnosticBottomNav(
          onPrevious: () {},
          onNext: () {},
          onFinish: () {},
          onEarlyFinish: () {},
          isLast: true,
          submitting: false,
          hasNextSubject: true,
        ),
      ),
    ));
    expect(find.text('Перейти к следующему тесту'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
