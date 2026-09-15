import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_tactile_option_card.dart';
import 'package:alochi_monitoring/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Color? _badgeColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(DiagnosticTactileOptionCard),
      matching: find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle &&
          (w.constraints?.maxWidth == 36 || w.constraints?.maxWidth == 22)),
    ),
  );
  return (container.decoration as BoxDecoration).color;
}

void main() {
  testWidgets('badge color matches letter A/B/C/D', (tester) async {
    const expected = {
      'A': AppColors.violetMuted,
      'B': AppColors.blueMuted,
      'C': AppColors.amberBorder,
      'D': AppColors.emeraldMuted,
    };
    for (final entry in expected.entries) {
      await tester.pumpWidget(_wrap(DiagnosticTactileOptionCard(
        label: entry.key,
        text: 'javob',
        selected: false,
        onTap: () {},
      )));
      expect(_badgeColor(tester), entry.value, reason: 'letter ${entry.key}');
    }
  });

  testWidgets('selected shows checkmark icon, unselected does not',
      (tester) async {
    await tester.pumpWidget(_wrap(const DiagnosticTactileOptionCard(
      label: 'A',
      text: 'javob',
      selected: false,
      onTap: _noop,
    )));
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await tester.pumpWidget(_wrap(const DiagnosticTactileOptionCard(
      label: 'A',
      text: 'javob',
      selected: true,
      onTap: _noop,
    )));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('tap calls onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(DiagnosticTactileOptionCard(
      label: 'B',
      text: 'javob',
      selected: false,
      onTap: () => tapped = true,
    )));
    await tester.tap(find.byType(DiagnosticTactileOptionCard));
    await tester.pump();
    expect(tapped, isTrue);
  });
}

void _noop() {}
