import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_test_runner_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_options_grid.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_tactile_option_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Matches _kDockMaxWidth in diagnostic_test_runner_screen.dart — the real
// dock width the grid renders inside of in production.
const double _dockMaxWidth = 760;

List<DiagnosticOptionItem> _shortOptions() => const [
      DiagnosticOptionItem(key: 'A', text: '12'),
      DiagnosticOptionItem(key: 'B', text: '25'),
      DiagnosticOptionItem(key: 'C', text: '30'),
      DiagnosticOptionItem(key: 'D', text: '45'),
    ];

// Real-world example from the bug report: exceeds the old 8-char cutoff
// (13-16 chars) but fits comfortably in 2 lines at dock width.
List<DiagnosticOptionItem> _comparisonOptions() => const [
      DiagnosticOptionItem(key: 'A', text: '76 001 > 76 004'),
      DiagnosticOptionItem(key: 'B', text: '8 137 > 8 140'),
      DiagnosticOptionItem(key: 'C', text: '90 511 < 100 749'),
      DiagnosticOptionItem(key: 'D', text: '90 511 > 100 749'),
    ];

// Second real-world example from the bug report.
List<DiagnosticOptionItem> _remainderOptions() => const [
      DiagnosticOptionItem(key: 'A', text: '10, остаток 6'),
      DiagnosticOptionItem(key: 'B', text: '11, остаток 1'),
      DiagnosticOptionItem(key: 'C', text: '10, остаток 5'),
      DiagnosticOptionItem(key: 'D', text: '9, остаток 13'),
    ];

List<DiagnosticOptionItem> _longOptions() => const [
      DiagnosticOptionItem(key: 'A', text: '12'),
      DiagnosticOptionItem(
          key: 'B',
          text:
              'Bu ancha uzunroq javob matni bo\'lib, ikkita qatorga ham sig\'maydi'),
      DiagnosticOptionItem(key: 'C', text: '30'),
      DiagnosticOptionItem(key: 'D', text: '45'),
    ];

Future<void> _pumpGrid(
    WidgetTester tester, List<DiagnosticOptionItem> options) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _dockMaxWidth,
          child: DiagnosticOptionsGrid(
            options: options,
            selectedOption: null,
            interactive: true,
            onSelect: (_) {},
          ),
        ),
      ),
    ),
  ));
}

void main() {
  test('shouldUseGrid true for 4 short options at dock width', () {
    expect(DiagnosticOptionsGrid.shouldUseGrid(_shortOptions(), 269), isTrue);
  });

  test('shouldUseGrid false when textWidth is non-positive', () {
    expect(DiagnosticOptionsGrid.shouldUseGrid(_shortOptions(), 0), isFalse);
  });

  test('shouldUseGrid false when option count != 4', () {
    expect(
      DiagnosticOptionsGrid.shouldUseGrid(_shortOptions().sublist(0, 3), 269),
      isFalse,
    );
  });

  testWidgets(
      'lays cards out as a 2x2 grid (content-sized, not GridView) for short options',
      (tester) async {
    await _pumpGrid(tester, _shortOptions());
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

  testWidgets(
      'lays out the "76 001 > 76 004"-style comparison options as a 2x2 grid',
      (tester) async {
    await _pumpGrid(tester, _comparisonOptions());
    expect(find.byType(GridView), findsNothing);
    final topLefts = find
        .byType(DiagnosticTactileOptionCard)
        .evaluate()
        .map((e) => tester.getTopLeft(find.byWidget(e.widget)))
        .toList();
    expect(topLefts[0].dy, topLefts[1].dy);
    expect(topLefts[0].dx, isNot(topLefts[1].dx));
    expect(topLefts[2].dy, topLefts[3].dy);
    expect(topLefts[0].dy, isNot(topLefts[2].dy));
  });

  testWidgets(
      'lays out the "10, остаток 6"-style remainder options as a 2x2 grid',
      (tester) async {
    await _pumpGrid(tester, _remainderOptions());
    expect(find.byType(GridView), findsNothing);
    final topLefts = find
        .byType(DiagnosticTactileOptionCard)
        .evaluate()
        .map((e) => tester.getTopLeft(find.byWidget(e.widget)))
        .toList();
    expect(topLefts[0].dy, topLefts[1].dy);
    expect(topLefts[0].dx, isNot(topLefts[1].dx));
    expect(topLefts[2].dy, topLefts[3].dy);
    expect(topLefts[0].dy, isNot(topLefts[2].dy));
  });

  testWidgets('stacks cards in a single vertical column for long options',
      (tester) async {
    await _pumpGrid(tester, _longOptions());
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
