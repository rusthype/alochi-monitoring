// test/engine_sentences_list_words_test.dart
// English tests ship `sentence_order.words` as a JSON LIST (sections
// "Writing" and "Sentences"); History chronology ("Xronologiya") ships a
// '/'-joined STRING. Question.fromJson must split the list into proper prompt
// segments, and TestEngine must render free-text typing (not chips) whenever
// the words came from a list, regardless of section name.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_scorer.dart';
import 'package:alochi_monitoring/core/engine/question_widgets.dart'
    show SentenceFreeTextWidget, SentenceOrderWidget;
import 'package:alochi_monitoring/l10n/app_localizations.dart';

Map<String, dynamic> _specJson(String section, Object words, String ans) => {
      'test_key': 'sentences_list_words_v1',
      'title': 'Sentences list-words',
      'grade': 5,
      'version': 1,
      'parts': [section],
      'variants': {
        '1': {
          section: [
            {'type': 'sentence_order', 'words': words, 'ans': ans},
          ],
        },
      },
    };

Future<void> _pump(WidgetTester tester, TestSpec spec) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TestEngine(
      spec: spec,
      variant: 1,
      firstName: 'Ism',
      lastName: 'Familiya',
      school: '56',
      studentId: '',
      duration: const Duration(minutes: 10),
      onComplete: (_, __) {},
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Question.fromJson words', () {
    test('list -> joined with " / ", wordsFromList true', () {
      final q = Question.fromJson({
        'type': 'sentence_order',
        'words': ['is', 'a', 'It', 'ball'],
        'ans': 'It is a ball.',
      });
      expect(q.words, 'is / a / It / ball');
      expect(q.wordsFromList, isTrue);
    });

    test('string stays untouched, wordsFromList false', () {
      final q = Question.fromJson({
        'type': 'sentence_order',
        'words': 'A / B / C',
        'ans': 'A B C',
      });
      expect(q.words, 'A / B / C');
      expect(q.wordsFromList, isFalse);
    });
  });

  group('engine widget choice', () {
    testWidgets('"Sentences" + list words -> free text, 4 separate segments',
        (tester) async {
      await _pump(
          tester,
          TestSpec.fromJson(_specJson(
              'Sentences', ['is', 'a', 'It', 'ball'], 'It is a ball.')));

      expect(find.byType(SentenceFreeTextWidget), findsOneWidget);
      expect(find.byType(SentenceOrderWidget), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      // The prompt is one Text.rich: four segments joined by ' / '.
      expect(find.text('is / a / It / ball', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('[is', findRichText: true), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"Xronologiya" + string words -> chips', (tester) async {
      await _pump(
          tester,
          TestSpec.fromJson(
              _specJson('Xronologiya', 'A / B / C', 'A B C')));

      expect(find.byType(SentenceOrderWidget), findsOneWidget);
      expect(find.byType(SentenceFreeTextWidget), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"Writing" is unchanged (free text, list or string)',
        (tester) async {
      await _pump(
          tester,
          TestSpec.fromJson(_specJson(
              'Writing', ['in', 'They', 'bedroom', 'are', 'the'],
              "They're in the bedroom.")));
      expect(find.byType(SentenceFreeTextWidget), findsOneWidget);
      expect(find.byType(SentenceOrderWidget), findsNothing);
      await tester.pumpWidget(const SizedBox());

      await _pump(
          tester,
          TestSpec.fromJson(
              _specJson('Writing', 'in / They / bedroom', 'They in bedroom.')));
      expect(find.byType(SentenceFreeTextWidget), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('scoring of typed answers (Sentences section, list words)', () {
    TestSpec spec(String ans) => TestSpec.fromJson(
        _specJson('Sentences', ['is', 'a', 'It', 'ball'], ans));

    test('typed "It is a ball." is correct', () {
      final r = TestScorer.score(
          spec('It is a ball.'), '1', {'Sentences/0': 'It is a ball.'});
      expect(r.totalCorrect, 1);
    });

    test('wrong order is incorrect', () {
      final r = TestScorer.score(
          spec('It is a ball.'), '1', {'Sentences/0': 'a ball is It.'});
      expect(r.totalCorrect, 0);
    });

    test('contraction equivalence still works', () {
      final r = TestScorer.score(
          spec("They're in the bedroom."), '1',
          {'Sentences/0': 'They are in the bedroom'});
      expect(r.totalCorrect, 1);
    });
  });
}
