import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_test_runner_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_options_grid.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_tactile_option_card.dart';
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

  testWidgets(
      'lays cards out as a 2x2 grid (content-sized, not GridView) for short options',
      (tester) async {
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
    // No GridView(childAspectRatio): a fixed aspect ratio guesses a cell
    // height that doesn't match the tactile card's real content height,
    // leaving its background "3D edge" exposed as a large gap (found via a
    // real local run). Two content-sized Rows avoid that entirely. Position
    // (not widget-type counting) is the robust check here, since each card
    // has its own internal Row too.
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(DiagnosticTactileOptionCard), findsNWidgets(4));
    final topLefts = find
        .byType(DiagnosticTactileOptionCard)
        .evaluate()
        .map((e) => tester.getTopLeft(find.byWidget(e.widget)))
        .toList();
    expect(topLefts[0].dy, topLefts[1].dy); // A/B share a row
    expect(topLefts[0].dx, isNot(topLefts[1].dx)); // side by side
    expect(topLefts[2].dy, topLefts[3].dy); // C/D share a row
    expect(topLefts[0].dy, isNot(topLefts[2].dy)); // rows are distinct
  });

  testWidgets('stacks cards in a single vertical column for long options',
      (tester) async {
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
    expect(find.byType(DiagnosticTactileOptionCard), findsNWidgets(4));
    final topLefts = find
        .byType(DiagnosticTactileOptionCard)
        .evaluate()
        .map((e) => tester.getTopLeft(find.byWidget(e.widget)))
        .toList();
    expect(topLefts.map((p) => p.dx).toSet(), hasLength(1)); // same column
    expect(topLefts.map((p) => p.dy).toSet(), hasLength(4)); // 4 distinct rows
  });
}
