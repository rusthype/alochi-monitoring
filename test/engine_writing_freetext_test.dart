// test/engine_writing_freetext_test.dart
// TestEngine._buildQuestionWidget's section-name branch for
// QuestionType.sentenceOrder (test_engine.dart): the English World
// "Writing" section renders free-text input (SentenceFreeTextWidget) so
// contraction-equivalence grading (answer_normalization.dart) can actually
// matter — tap-to-order chips (SentenceOrderWidget) only ever offer the
// canonical answer-key words. Every other section name (e.g. History
// chronology's "Sanalar") keeps the existing tap-to-order UI unchanged.
//
// Pattern follows engine_reading_inline_test.dart: builds a real TestEngine
// widget via SharedPreferences.setMockInitialValues({}) + studentId: '' (so
// crash-recovery never tries to resume a saved attempt).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/question_widgets.dart'
    show SentenceFreeTextWidget, SentenceOrderWidget;
import 'package:alochi_monitoring/l10n/app_localizations.dart';

Map<String, dynamic> _specJson(String sectionName) => {
      'test_key': 'writing_freetext_test_v1',
      'title': 'Writing Free-text Test',
      'grade': 5,
      'version': 1,
      'parts': [sectionName],
      'variants': {
        '1': {
          sectionName: [
            {
              'type': 'sentence_order',
              'words': 'in / They / bedroom / are / the',
              'ans': "They're in the bedroom.",
            },
          ],
        },
      },
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'section named "Writing" renders SentenceFreeTextWidget, not '
      'SentenceOrderWidget', (WidgetTester tester) async {
    final spec = TestSpec.fromJson(_specJson('Writing'));

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TestEngine(
        spec: spec,
        variant: 1,
        firstName: 'Ism',
        lastName: 'Familiya',
        school: '56',
        studentId: '', // manual-entry — never resumes a saved attempt
        duration: const Duration(minutes: 10),
        onComplete: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SentenceFreeTextWidget), findsOneWidget);
    expect(find.byType(SentenceOrderWidget), findsNothing);

    // Unmount to cancel TestEngine's countdown Timer before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a History-style section name (e.g. "Sanalar") keeps '
      'SentenceOrderWidget, not SentenceFreeTextWidget',
      (WidgetTester tester) async {
    final spec = TestSpec.fromJson(_specJson('Sanalar'));

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TestEngine(
        spec: spec,
        variant: 1,
        firstName: 'Ism',
        lastName: 'Familiya',
        school: '56',
        studentId: '', // manual-entry — never resumes a saved attempt
        duration: const Duration(minutes: 10),
        onComplete: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SentenceOrderWidget), findsOneWidget);
    expect(find.byType(SentenceFreeTextWidget), findsNothing);

    // Unmount to cancel TestEngine's countdown Timer before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
