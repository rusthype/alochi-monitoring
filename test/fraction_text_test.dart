import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_option_card.dart';
import 'package:alochi_monitoring/shared/widgets/fraction_text.dart';

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: Center(child: w)));

int _stacked(WidgetTester t) => find
    .descendant(
        of: find.byType(FractionText), matching: find.byType(IntrinsicWidth))
    .evaluate()
    .length;

void main() {
  const style = TextStyle(fontSize: 20);

  testWidgets('33/5 is stacked', (t) async {
    await t.pumpWidget(_wrap(const FractionText('33/5', style: style)));
    expect(find.text('33'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('33/5'), findsNothing);
    expect(_stacked(t), 1);
  });

  testWidgets('mixed 7 3/5: whole + stacked', (t) async {
    await t.pumpWidget(_wrap(const FractionText('7 3/5', style: style)));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(_stacked(t), 1);
  });

  testWidgets('no fraction: plain Text, unchanged', (t) async {
    await t.pumpWidget(_wrap(const FractionText('Hello 42', style: style)));
    expect(find.text('Hello 42'), findsOneWidget);
    expect(_stacked(t), 0);
    expect(
        find.descendant(
            of: find.byType(FractionText), matching: find.byType(RichText)),
        findsOneWidget);
  });

  for (final s in ['12/05/2026', 'km/h', '1/2/3', '5/0', '3/5abc']) {
    testWidgets('untouched: $s', (t) async {
      await t.pumpWidget(_wrap(FractionText(s, style: style)));
      expect(find.text(s), findsOneWidget);
      expect(_stacked(t), 0);
    });
  }

  testWidgets('multiple fractions in one string', (t) async {
    await t.pumpWidget(_wrap(const FractionText('3/10 < 3/5', style: style)));
    expect(_stacked(t), 2);
    expect(find.text('10'), findsOneWidget);
    expect(find.textContaining('<', findRichText: true), findsOneWidget);
  });

  testWidgets('option row renders stacked mixed number', (t) async {
    await t.pumpWidget(_wrap(DiagnosticOptionCard(
        label: 'A', text: '6 3/5', selected: false, onTap: () {})));
    expect(find.text('6'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(_stacked(t), 1);
  });
}
