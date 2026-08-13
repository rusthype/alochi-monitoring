// test/engine_finish_confirm_test.dart
// Regression test for two accidental-submit bugs in
// lib/core/engine/test_engine.dart:
//
// 1. _requestFinish() used to skip the confirmation dialog entirely when
//    every question was already answered (unanswered == 0), letting a
//    stray/misclick tap on "Finish" submit with zero confirmation.
// 2. _restoreAttempt() used to silently call _finishNow() when relaunched
//    after the persisted deadline had already passed, with no notice to
//    the student that their answers were auto-submitted.
//
// Pattern follows engine_writing_freetext_test.dart: builds a real
// TestEngine widget via SharedPreferences.setMockInitialValues({}).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

Map<String, dynamic> _specJson() => {
      'test_key': 'finish_confirm_test_v1',
      'title': 'Finish Confirm Test',
      'grade': 5,
      'version': 1,
      'parts': ['Math'],
      'variants': {
        '1': {
          'Math': [
            {
              'type': 'text_choice',
              'q': 'Q1',
              // Distinct from the "A/B/C…" option-letter label EngineOptionRow
              // renders next to each option — using 'A'/'B' as the option TEXT
              // too would make find.text('A') match both and throw "found 2
              // widgets" ambiguous-finder errors.
              'opts': ['Alpha', 'Beta'],
              'ans': 0,
            },
          ],
        },
      },
    };

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'all questions answered: tapping Finish still shows a confirm '
      'dialog, and Back cancels without submitting',
      (WidgetTester tester) async {
    final spec = TestSpec.fromJson(_specJson());
    var completed = false;

    await tester.pumpWidget(_wrap(TestEngine(
      spec: spec,
      variant: 1,
      firstName: 'Ism',
      lastName: 'Familiya',
      school: '56',
      studentId: '',
      duration: const Duration(minutes: 10),
      onComplete: (_) => completed = true,
    )));
    // Unmounts even on assertion failure — otherwise TestEngine's countdown
    // Timer.periodic keeps firing into the next test and pumpAndSettle()
    // there never settles.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpAndSettle();

    // Answer the only question so unanswered == 0.
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    await tester.tap(find.widgetWithText(ElevatedButton, l10n.finish));
    await tester.pumpAndSettle();

    // Dialog must appear even though every question was answered.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(l10n.finishConfirmAllAnsweredPrompt), findsOneWidget);
    expect(completed, isFalse);

    // Cancel via "Back" — must not submit.
    await tester.tap(find.widgetWithText(TextButton, l10n.back));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(completed, isFalse);

    // Confirming via the dialog's Finish button does submit.
    await tester.tap(find.widgetWithText(ElevatedButton, l10n.finish));
    await tester.pumpAndSettle();
    final dialogFinish = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, l10n.finish),
    );
    await tester.tap(dialogFinish);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
  });

  testWidgets(
      'relaunch after the persisted deadline already passed auto-submits '
      'and notifies via onExpiredAutoSubmit exactly once',
      (WidgetTester tester) async {
    const testKey = 'finish_confirm_test_v1';
    const studentId = 'S-EXPIRED-1';
    final pastDeadline =
        DateTime.now().millisecondsSinceEpoch - const Duration(minutes: 1).inMilliseconds;

    await AttemptStore.save(testKey, {
      'variant': 1,
      'answers': <String, dynamic>{},
      'started_at': pastDeadline - 60000,
      'deadline_epoch_ms': pastDeadline,
      'student_name': 'Ism Familiya',
      'student_id': studentId,
      'group_name': '',
    });

    final spec = TestSpec.fromJson(_specJson());
    var completed = false;
    var expiredNoticeCount = 0;

    await tester.pumpWidget(_wrap(TestEngine(
      spec: spec,
      variant: 1,
      firstName: 'Ism',
      lastName: 'Familiya',
      school: '56',
      studentId: studentId,
      duration: const Duration(minutes: 10),
      onComplete: (_) => completed = true,
      onExpiredAutoSubmit: () => expiredNoticeCount++,
    )));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpAndSettle();

    // Auto-submitted silently as far as onComplete is concerned, but the
    // host screen must have been told exactly once so it can notify the
    // student on the result screen.
    expect(completed, isTrue);
    expect(expiredNoticeCount, 1);
  });
}
