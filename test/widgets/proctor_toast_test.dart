import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/widgets/proctor_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(ProctorToastController c) => MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: SizedBox(key: Key('body'))),
            ProctorToastStack(controller: c),
          ],
        ),
      ),
    );

void main() {
  late ProctorToastController c;
  setUp(() => c = ProctorToastController());

  testWidgets(
      'warning shows adminWarning prefix + message, top-right, then '
      'auto-dismisses', (tester) async {
    await tester.pumpWidget(_host(c));
    final l10n =
        AppLocalizations.of(tester.element(find.byKey(const Key('body'))))!;

    c.push(ProctorToastKind.warning, 'Diqqat', const Duration(seconds: 10));
    await tester.pump();

    final text = find.text('${l10n.adminWarning}: Diqqat');
    expect(text, findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    final box = tester.getRect(find.byType(Container).last);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(box.right, screen.width - 12);
    expect(box.top, greaterThanOrEqualTo(12));

    await tester.pump(const Duration(seconds: 9));
    expect(text, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(text, findsNothing);
  });

  testWidgets('extended toast shows the bare message and its own icon', (
    tester,
  ) async {
    await tester.pumpWidget(_host(c));
    c.push(ProctorToastKind.extended, '+2 daqiqa', const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('+2 daqiqa'), findsOneWidget);
    expect(find.byIcon(Icons.alarm_add_rounded), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('+2 daqiqa'), findsNothing);
  });

  testWidgets('does not block taps underneath', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                ),
              ),
              ProctorToastStack(controller: c),
            ],
          ),
        ),
      ),
    );
    c.push(ProctorToastKind.warning, 'x', const Duration(seconds: 10));
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.textContaining('x')));
    expect(taps, 1);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('dispose cancels pending timers', (tester) async {
    c.push(ProctorToastKind.warning, 'x', const Duration(seconds: 10));
    c.dispose();
    // A leaked timer would fail the framework's pending-timer invariant.
  });
}
