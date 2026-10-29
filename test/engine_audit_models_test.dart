// Audit regression tests (E-04, E-05, E-06, E-13/E-16, E-02 parse, E-17, E-23):
// model parsing keeps index stability, reading sub-questions render and count
// consistently, duplicate sentence-order words stay available, scorer folds
// apostrophe variants, a malformed SVG shows the broken-image box.

import 'package:alochi_monitoring/core/engine/question_widgets.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_scorer.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _spec(dynamic section, {Map<String, dynamic>? extra}) => {
      'test_key': 'audit_t',
      'title': 'T',
      'grade': 5,
      'version': 1,
      'parts': ['S'],
      'variants': {
        '1': {'S': section}
      },
      ...?extra,
    };

Map<String, dynamic> _tc(String q, int ans) => {
      'type': 'text_choice',
      'q': q,
      'opts': ['a', 'b'],
      'ans': ans,
    };

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('E-06 / E-16 index stability', () {
    test('failed / non-object / unknown-type items keep their index', () {
      final spec = TestSpec.fromJson(_spec([
        _tc('first', 0),
        'garbage', // non-object
        {'type': 'does_not_exist', 'q': 'x'}, // unknown type
        _tc('fourth', 1),
      ]));
      final section = spec.sectionsForVariant('1').single;
      expect(section.questions.length, 4);
      expect(section.answerSlots.map((s) => s.key), ['S/0', 'S/3']);
      expect(section.questionCount, 2);
      expect(section.answerSlots.last.question.q, 'fourth');

      // The skipped items are excluded from the total, the keys still map.
      final r = TestScorer.score(spec, '1', {'S/0': 0, 'S/3': 1});
      expect(r.totalQuestions, 2);
      expect(r.totalCorrect, 2);
    });

    test('Map<dynamic,dynamic> items and sections are accepted', () {
      final dyn = <dynamic, dynamic>{
        'type': 'text_choice',
        'q': 'dyn',
        'opts': ['a', 'b'],
        'ans': 0,
      };
      final spec = TestSpec.fromJson(_spec([dyn]));
      expect(spec.sectionsForVariant('1').single.questionCount, 1);

      final reading = <dynamic, dynamic>{
        'title': 't',
        'text': 'x',
        'qs': [
          <dynamic, dynamic>{'type': 'yes_no', 'q': 'q', 'ans': 'YES'}
        ],
      };
      final spec2 = TestSpec.fromJson(_spec(reading));
      expect(spec2.sectionsForVariant('1').single.isReading, isTrue);
      expect(spec2.sectionsForVariant('1').single.questionCount, 1);
    });

    test('string-typed ans is parsed instead of dropping the question', () {
      final spec = TestSpec.fromJson(_spec([
        {
          'type': 'text_choice',
          'q': 'q',
          'opts': ['a', 'b'],
          'ans': '1'
        }
      ]));
      expect(TestScorer.score(spec, '1', {'S/0': 1}).totalCorrect, 1);
    });
  });

  group('E-02 numeric fields given as strings', () {
    test('grade / version / duration_minutes accept "5"', () {
      final spec = TestSpec.fromJson(_spec([
        _tc('q', 0)
      ], extra: {
        'grade': '5',
        'version': '3',
        'duration_minutes': '25',
      }));
      expect(spec.grade, 5);
      expect(spec.version, 3);
      expect(spec.durationMinutes, 25);
    });

    test('garbage numeric falls back to the defaults', () {
      final spec = TestSpec.fromJson(_spec([
        _tc('q', 0)
      ], extra: {
        'grade': 'abc',
        'version': 'NaN',
        'duration_minutes': null,
      }));
      expect(spec.grade, 0);
      // Contract change (audit wave 5, F3): a missing / garbage version is 0
      // = unknown everywhere (cache stores 0 too), no longer 1.
      expect(spec.version, 0);
      expect(spec.durationMinutes, isNull);
    });
  });

  group('E-05 reading sub-question rendering == counting', () {
    final readingJson = {
      'title': 'P',
      'text': 'passage',
      'qs': [
        {'type': 'yes_no', 'q': 'YN-Q', 'ans': 'YES'},
        {'type': 'spelling', 'scramble': 'SPELL-Q', 'ans': 'cat'},
        {
          'type': 'text_choice',
          'q': 'TC-Q',
          'opts': ['a', 'b'],
          'ans': 0
        },
      ],
    };

    test('unsupported nested types are not answer slots', () {
      final spec = TestSpec.fromJson(_spec(readingJson));
      final section = spec.sectionsForVariant('1').single;
      expect(section.questionCount, 2);
      // keys keep the original sub-index
      expect(section.answerSlots.map((s) => s.key), ['S/0', 'S/2']);
      final r = TestScorer.score(spec, '1', {'S/0': 'YES', 'S/2': 0});
      expect(r.totalQuestions, 2);
      expect(r.totalCorrect, 2);
    });

    testWidgets('only counted sub-questions render, numbered without gaps',
        (tester) async {
      final spec = TestSpec.fromJson(_spec(readingJson));
      final reading = spec.sectionsForVariant('1').single.readingContainer!;
      await tester.pumpWidget(_wrap(ReadingBlockWidget(
        reading: reading,
        answers: const {},
        onAnswer: (_, __) {},
      )));
      expect(find.text('YN-Q'), findsOneWidget);
      expect(find.text('TC-Q'), findsOneWidget);
      expect(find.text('SPELL-Q'), findsNothing);
      expect(find.byType(EngineQNum), findsNWidgets(2));
    });

    testWidgets('wrong-typed restored answers do not throw', (tester) async {
      final spec = TestSpec.fromJson(_spec(readingJson));
      final reading = spec.sectionsForVariant('1').single.readingContainer!;
      await tester.pumpWidget(_wrap(ReadingBlockWidget(
        reading: reading,
        // yes_no gets an int, text_choice a String (stale / corrupt restore)
        answers: const {'0': 3, '2': 'oops'},
        onAnswer: (_, __) {},
      )));
      expect(tester.takeException(), isNull);
    });
  });

  group('E-04 sentence_order duplicates', () {
    testWidgets('tapping one "the" leaves the other available', (tester) async {
      final q = Question.fromJson({
        'type': 'sentence_order',
        'words': 'the/cat/the/mat',
        'ans': 'the cat the mat',
      });
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      await tester.pumpWidget(_wrap(SentenceOrderWidget(
        index: 0,
        question: q,
        controller: ctrl,
        onChanged: (_) {},
      )));
      expect(find.text('the'), findsNWidgets(2));
      await tester.tap(find.text('the').first);
      await tester.pump();
      // one in the ordered list, one still in the pool
      expect(find.text('the'), findsNWidgets(2));
      expect(ctrl.text, 'the');
      // finish the sentence using the remaining "the"
      await tester.tap(find.text('cat').last);
      await tester.pump();
      await tester.tap(find.text('the').last);
      await tester.pump();
      await tester.tap(find.text('mat').last);
      await tester.pump();
      expect(ctrl.text, 'the cat the mat');
    });
  });

  group('E-17 apostrophe folding', () {
    test('U+2018, backtick and acute fold to a straight apostrophe', () {
      final spec = TestSpec.fromJson(_spec([
        {'type': 'fill_blank', 'q': 'q', 'ans': "o'qituvchi"}
      ]));
      for (final typed in ['o‘qituvchi', 'o`qituvchi', 'o´qituvchi']) {
        expect(TestScorer.score(spec, '1', {'S/0': typed}).totalCorrect, 1,
            reason: typed);
      }
    });
  });

  group('E-23 malformed inline SVG', () {
    testWidgets('shows the broken-image box instead of an empty gap',
        (tester) async {
      final q = Question.fromJson({
        'type': 'text_choice',
        'q': 'with svg',
        'opts': ['a', 'b'],
        'ans': 0,
        'svg': '<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0 L',
      });
      await tester.pumpWidget(_wrap(TextChoiceWidget(
        index: 0,
        question: q,
        answer: null,
        onSelect: (_) {},
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });
  });
}
