import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_test_runner_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_options_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<DiagnosticOptionItem> _shortOptions() => const [
      DiagnosticOptionItem(key: 'A', text: '12'),
      DiagnosticOptionItem(key: 'B', text: '25'),
      DiagnosticOptionItem(key: 'C', text: '30'),
      DiagnosticOptionItem(key: 'D', text: '45'),
    ];

List<DiagnosticOptionItem> _longOptions() => const [
      DiagnosticOptionItem(key: 'A', text: '12'),
      DiagnosticOptionItem(key: 'B', text: 'Bu ancha uzunroq javob matni'),
      DiagnosticOptionItem(key: 'C', text: '30'),
      DiagnosticOptionItem(key: 'D', text: '45'),
    ];

void main() {
  test('shouldUseGrid true for 4 short options', () {
    expect(DiagnosticOptionsGrid.shouldUseGrid(_shortOptions()), isTrue);
  });

  test('shouldUseGrid false when any option is long', () {
    expect(DiagnosticOptionsGrid.shouldUseGrid(_longOptions()), isFalse);
  });

  test('shouldUseGrid false when option count != 4', () {
    expect(
      DiagnosticOptionsGrid.shouldUseGrid(_shortOptions().sublist(0, 3)),
      isFalse,
    );
  });

  testWidgets('renders GridView for short options', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiagnosticOptionsGrid(
          options: _shortOptions(),
          selectedOption: null,
          interactive: true,
          onSelect: (_) {},
        ),
      ),
    ));
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('renders Column for long options', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiagnosticOptionsGrid(
          options: _longOptions(),
          selectedOption: null,
          interactive: true,
          onSelect: (_) {},
        ),
      ),
    ));
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(Column), findsWidgets);
  });
}
