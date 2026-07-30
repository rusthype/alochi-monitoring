// test/sentence_free_text_widget_test.dart
// Widget tests for SentenceFreeTextWidget (free-text alternative to
// SentenceOrderWidget, used only for the English World "Writing" section —
// see question_widgets.dart's doc-comment and test_engine.dart's
// sectionName == 'Writing' branch). Verifies that:
//   * it renders a plain TextField with no tappable chip elements,
//   * typing pushes onChanged and writes into the controller (same
//     controller-injection contract as SentenceOrderWidget),
//   * the static prompt text is built from Question.words,
//   * pre-filled controller text (resume / section-switch) round-trips into
//     the TextField.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/question_widgets.dart';

Question _q({String words = 'in / They / bedroom / are / the'}) => Question(
      type: QuestionType.sentenceOrder,
      words: words,
      strAns: "They're in the bedroom.",
    );

Widget _host(
  TextEditingController controller,
  void Function(String) onChanged, {
  Question? question,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SentenceFreeTextWidget(
          index: 0,
          question: question ?? _q(),
          controller: controller,
          onChanged: onChanged,
        ),
      ),
    );

void main() {
  testWidgets('renders a plain TextField and no tappable chip elements',
      (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(_host(controller, (_) {}));

    expect(find.byType(TextField), findsOneWidget);
    // No SentenceOrderWidget chip machinery (add/remove icons) present.
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsNothing);
  });

  testWidgets('typing calls onChanged and writes into the controller',
      (tester) async {
    final controller = TextEditingController();
    String? emitted;

    await tester.pumpWidget(_host(controller, (v) => emitted = v));

    await tester.enterText(find.byType(TextField), 'they are in the bedroom');
    await tester.pump();

    expect(controller.text, 'they are in the bedroom');
    expect(emitted, 'they are in the bedroom');
  });

  testWidgets('prompt text is derived from Question.words', (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(_host(controller, (_) {},
        question: _q(words: 'in / They / bedroom / are / the')));

    expect(
      find.textContaining('They'),
      findsWidgets,
    );
    expect(find.textContaining('bedroom'), findsWidgets);
    expect(find.textContaining('are'), findsWidgets);
    // Static prompt only — none of the words are individually tappable.
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsNothing);
  });

  testWidgets('pre-filled controller text is shown in the TextField',
      (tester) async {
    final controller = TextEditingController(text: 'They are in the bedroom');

    await tester.pumpWidget(_host(controller, (_) {}));

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'They are in the bedroom');
    expect(find.text('They are in the bedroom'), findsOneWidget);
  });

  testWidgets('typed prompt words get struck through as the pupil types',
      (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(_host(controller, (_) {},
        question: _q(words: "he's / opening / present / a / ?")));

    // "present" and "?" are deliberately left out of the typed text.
    await tester.enterText(find.byType(TextField), "he's opening a");
    await tester.pump();

    // Find the RichText that renders the prompt row (contains 'opening').
    final richText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((rt) => rt.text.toPlainText().contains('opening'));

    bool isStruckThrough(String word) {
      var found = false;
      void visit(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text == word &&
              span.style?.decoration == TextDecoration.lineThrough) {
            found = true;
          }
          span.children?.forEach(visit);
        }
      }

      visit(richText.text);
      return found;
    }

    expect(isStruckThrough("he's"), isTrue);
    expect(isStruckThrough('opening'), isTrue);
    expect(isStruckThrough('a'), isTrue);
    // Not typed yet — must render without the strike-through.
    expect(isStruckThrough('present'), isFalse);
  });
}
