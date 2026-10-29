// Scoring tolerance (numeric / text / yes-no) and English YES/NO labels.
import 'package:alochi_monitoring/core/engine/answer_normalization.dart';
import 'package:alochi_monitoring/core/engine/question_widgets.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_scorer.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TestSpec _spec(List<Map<String, dynamic>> qs) => TestSpec.fromJson({
      'test_key': 'norm',
      'title': 'norm',
      'grade': 5,
      'version': 1,
      'parts': ['S'],
      'variants': {
        '1': {'S': qs},
      },
    });

/// 1 when [given] scores correct against [ans] for a question of [type].
bool _ok(String type, String ans, dynamic given) {
  final spec = _spec([
    {'type': type, 'q': 'q', 'ans': ans, 'words': 'a / b'},
  ]);
  final r = TestScorer.score(spec, '1', {'S/0': given});
  return r.totalCorrect == 1;
}

void main() {
  group('numeric fill_blank', () {
    test('same value in any common spelling is correct', () {
      for (final g in ['3', ' 3 ', '3.0', '3,0', '3.00', '03', '+3']) {
        expect(_ok('fill_blank', '3', g), true, reason: '"$g" vs 3');
      }
      expect(_ok('fill_blank', '2.5', '2,5'), true);
      expect(_ok('fill_blank', '2,50', '2.5'), true);
      expect(_ok('fill_blank', '-1', '-1,0'), true);
    });
    test('different numbers are never equal', () {
      for (final g in ['3.1', '30', '0.3', '4', '3,01', '', '-3', '3a']) {
        expect(_ok('fill_blank', '3', g), false, reason: '"$g" vs 3');
      }
      expect(_ok('fill_blank', '0.3', '0.30000000000000004'), false);
      // beyond double precision: compared as text, not as doubles
      expect(
          _ok('fill_blank', '9007199254740992', '9007199254740993'), false);
    });
    test('canonicalNumber', () {
      expect(canonicalNumber('3,0'), '3');
      expect(canonicalNumber('-0,0'), '0');
      expect(canonicalNumber('007.50'), '7.5');
      expect(canonicalNumber('1.2.3'), isNull);
      expect(canonicalNumber('1 000'), isNull);
    });
  });

  group('text tolerance', () {
    test('trim, collapsed whitespace and case', () {
      expect(_ok('fill_blank', 'New York', '  new   YORK '), true);
      expect(_ok('spelling', 'Tashkent', 'tashkent'), true);
      expect(_ok('fill_blank', 'cat', 'cats'), false);
    });
  });

  group('yes_no', () {
    test('stored value scores whatever the display language', () {
      expect(_ok('yes_no', 'YES', 'YES'), true);
      expect(_ok('yes_no', 'yes', ' yes '), true);
      expect(_ok('yes_no', 'NO', 'NO'), true);
      expect(_ok('yes_no', 'YES', 'ДА'), true);
      expect(_ok('yes_no', 'NO', 'НЕТ'), true);
      expect(_ok('yes_no', 'YES', 'Ha'), true);
      expect(_ok('yes_no', 'NO', "Yo'q"), true);
    });
    test('the opposite answer is still wrong', () {
      expect(_ok('yes_no', 'YES', 'NO'), false);
      expect(_ok('yes_no', 'NO', 'ДА'), false);
      expect(_ok('yes_no', 'YES', 'maybe'), false);
    });
  });

  group('YES/NO labels follow the TEST language', () {
    Future<void> pump(WidgetTester tester, Locale ui, bool? english) async {
      const q = Question(type: QuestionType.yesNo, q: 'Is it?', yesNoAns: 'YES');
      Widget w = YesNoWidget(
          index: 1, question: q, answer: null, onSelect: (_) {});
      if (english != null) w = YesNoLabelScope(english: english, child: w);
      await tester.pumpWidget(MaterialApp(
        locale: ui,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: w),
      ));
    }

    testWidgets('English test under a Russian UI shows YES / NO',
        (tester) async {
      await pump(tester, const Locale('ru'), true);
      expect(find.text('YES'), findsOneWidget);
      expect(find.text('NO'), findsOneWidget);
      expect(find.text('ДА'), findsNothing);
    });
    testWidgets('a non-English test keeps the UI-language labels',
        (tester) async {
      await pump(tester, const Locale('ru'), false);
      expect(find.text('ДА'), findsOneWidget);
      expect(find.text('НЕТ'), findsOneWidget);
    });
    testWidgets('tapping reports the language-independent value',
        (tester) async {
      String? got;
      const q = Question(type: QuestionType.yesNo, q: 'Is it?', yesNoAns: 'YES');
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: YesNoWidget(
                index: 1, question: q, answer: null, onSelect: (v) => got = v)),
      ));
      await tester.tap(find.text('НЕТ'));
      expect(got, 'NO');
    });
    test('which subjects count as English', () {
      expect(YesNoLabelScope.englishFor('english'), true);
      expect(YesNoLabelScope.englishFor(null), true);
      expect(YesNoLabelScope.englishFor('combined'), true);
      expect(YesNoLabelScope.englishFor('math'), false);
      expect(YesNoLabelScope.englishFor('tarix'), false);
    });
  });
}
