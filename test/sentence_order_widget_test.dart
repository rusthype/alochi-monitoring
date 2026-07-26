// test/sentence_order_widget_test.dart
// Widget tests for the tap-to-order SentenceOrderWidget (replaces the old
// free-text field). Verifies that:
//   * tapping segments in order writes the joined string into the controller
//     and pushes it via onChanged (so the engine's scoring path is unchanged),
//   * a partly-built answer is restored from existing controller text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/question_widgets.dart';

Question _q() => const Question(
      type: QuestionType.sentenceOrder,
      words: 'B / A / C',
      strAns: 'A / B / C',
    );

Widget _host(TextEditingController controller, void Function(String) onChanged) =>
    MaterialApp(
      home: Scaffold(
        body: SentenceOrderWidget(
          index: 0,
          question: _q(),
          controller: controller,
          onChanged: onChanged,
        ),
      ),
    );

void main() {
  testWidgets('tapping segments in order builds the joined answer', (tester) async {
    final controller = TextEditingController();
    String? emitted;

    await tester.pumpWidget(_host(controller, (v) => emitted = v));

    // All three scrambled segments start as tappable choices.
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);

    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.tap(find.text('B'));
    await tester.pump();
    await tester.tap(find.text('C'));
    await tester.pump();

    expect(controller.text, 'A / B / C');
    expect(emitted, 'A / B / C');
  });

  testWidgets('removing a chosen segment updates the controller', (tester) async {
    final controller = TextEditingController();
    String? emitted;

    await tester.pumpWidget(_host(controller, (v) => emitted = v));

    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.tap(find.text('B'));
    await tester.pump();
    expect(controller.text, 'A / B');

    // Remove the first chosen segment (A) via its ✕ button.
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pump();

    expect(controller.text, 'B');
    expect(emitted, 'B');
  });

  testWidgets('restores a partly-built answer from controller text', (tester) async {
    final controller = TextEditingController(text: 'A / B');
    String? emitted;

    await tester.pumpWidget(_host(controller, (v) => emitted = v));

    // A and B are already chosen, so only C remains as a choice — tapping it
    // completes the order.
    await tester.tap(find.text('C'));
    await tester.pump();

    expect(controller.text, 'A / B / C');
    expect(emitted, 'A / B / C');
  });
}
