import 'dart:async';

import 'package:alochi_monitoring/core/api/api_client.dart' show ApiException;
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_test_runner_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_bottom_nav.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_option_card.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_question_card.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_question_dots.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/widgets/app_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _question({
  String id = 'q1',
  String text = 'Savol matni',
  String a = 'Variant A',
  String b = 'Variant B',
  String c = 'Variant C',
  String d = 'Variant D',
  String imageUrl = '',
  String? correctDisplayLetter,
}) {
  return {
    'question_id': id,
    'question_text': text,
    'option_a': a,
    'option_b': b,
    'option_c': c,
    'option_d': d,
    'image_url': imageUrl,
    'svg_visual': '',
    if (correctDisplayLetter != null)
      'correct_display_letter': correctDisplayLetter,
  };
}

/// Wraps a start-attempt/next-question fixture with the two fields the
/// backend now always includes (see diagnostic/views.py + fixed_variant.py).
Map<String, dynamic> _withMeta(
  Map<String, dynamic> resp, {
  int? durationMinutes,
  bool isFixedVariant = false,
}) {
  return {
    ...resp,
    if (durationMinutes != null) 'duration_minutes': durationMinutes,
    'is_fixed_variant': isFixedVariant,
  };
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('uz'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

/// Same as [_wrap] but with a real GoRouter, for tests whose path finishes
/// the test and navigates to '/diagnostic_finished' (context.pushReplacement
/// throws "No GoRouter found" under a plain MaterialApp).
Widget _wrapWithRouter(Widget child, {void Function(Object?)? onFinished}) {
  final router = GoRouter(
    initialLocation: '/runner',
    routes: [
      GoRoute(path: '/runner', builder: (_, __) => child),
      GoRoute(
          path: '/diagnostic_finished',
          builder: (_, state) {
            onFinished?.call(state.extra);
            return const SizedBox(key: Key('finished'));
          }),
    ],
  );
  return MaterialApp.router(
    locale: const Locale('uz'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('extractDiagnosticOptions', () {
    test('reads option_a..option_d into A..D items', () {
      final items = extractDiagnosticOptions(_question());
      expect(items.map((e) => e.key), ['A', 'B', 'C', 'D']);
      expect(items.map((e) => e.text),
          ['Variant A', 'Variant B', 'Variant C', 'Variant D']);
    });

    test('drops blank options', () {
      final q = _question();
      q['option_d'] = '';
      final items = extractDiagnosticOptions(q);
      expect(items.length, 3);
    });
  });

  group('DiagnosticTestRunnerScreen', () {
    // DiagnosticTestRunnerScreen now starts the real HeartbeatService/
    // ProctorService singletons in initState() (live proctoring — see
    // _initProctoring()). ProctorService.start() arms a real (non-fake-clock)
    // Timer on macOS/Windows. The test framework's post-test invariant check
    // runs BEFORE tearDown() (right when the test body returns), so the
    // widget must be explicitly unmounted (triggering its own dispose(),
    // which stops both services) at the end of each test body instead.
    Future<void> unmount(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox());

    testWidgets('renders 4 option cards, no TextField, for a math question',
        (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return {
            'position': 1,
            'total_questions': 5,
            'subject': subject,
            'question': _question(),
          };
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // _initProctoring()'s HeartbeatService.startTest() resolves package
      // info via a platform channel the very first time any test in this
      // process calls it (cached afterwards) — that first resolution can
      // outlast a couple of zero-duration pump()s, so advance real time a
      // little to let it (and its .timeout() timer) settle before this test
      // ends (tests below happen to pump enough via tap()s not to need this).
      await tester.pump(const Duration(seconds: 4));

      expect(find.byType(DiagnosticOptionCard), findsNWidgets(4));
      expect(find.text('Variant A'), findsOneWidget);
      expect(find.text('Variant B'), findsOneWidget);
      expect(find.text('Variant C'), findsOneWidget);
      expect(find.text('Variant D'), findsOneWidget);
      // Multiple-choice-only contract: never a free-text input for math.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'selecting an option submits selected: "B" and updates the '
        'answered counter', (tester) async {
      String? captured;
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return {
            'position': 1,
            'total_questions': 5,
            'subject': subject,
            'question': _question(id: 'q1'),
          };
        },
        submitAnswerOverride: (
            {required attemptId,
            required questionId,
            required selected}) async {
          captured = selected;
          return {
            'position': 2,
            'total_questions': 5,
            'subject': 'math',
            'question': _question(id: 'q2', text: 'Ikkinchi savol'),
          };
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Header counter starts at position 1 before answering.
      expect(find.text('Savol 1 / 5'), findsOneWidget);

      // Selecting an option submits it directly — no separate CTA button
      // (DiagnosticOptionCard's onTap wiring mirrors what EngineOptionRow
      // used to do).
      await tester.tap(find.text('Variant B'));
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();

      expect(captured, 'B');
      expect(find.text('Ikkinchi savol'), findsOneWidget);
      // Header counter advances to the next question's position.
      expect(find.text('Savol 2 / 5'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('renders an image when image_url is present', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return {
            'position': 1,
            'total_questions': 5,
            'subject': subject,
            'question': _question(imageUrl: 'https://example.com/q.png'),
          };
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // _startSubject now awaits the first question's image (best-effort,
      // short timeout) before revealing it — give the real (failing, no
      // network in test) download a moment to resolve/time out.
      await tester.pump(const Duration(seconds: 4));

      expect(find.byType(AppNetworkImage), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
        'finished+next_subject moves to the next subject\'s first question '
        'instead of the finished screen', (tester) async {
      var startCalls = 0;
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 1,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          startCalls++;
          return {
            'position': 1,
            'total_questions': 5,
            'subject': subject,
            'question': _question(id: 'q-$subject', text: 'Savol ($subject)'),
          };
        },
        submitAnswerOverride: (
            {required attemptId,
            required questionId,
            required selected}) async {
          return {'finished': true, 'next_subject': 'english'};
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Variant A'));
      await tester.pump(); // shows the transition message

      expect(find.text('Savol (math)'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      await tester.pump();

      expect(find.text('Savol (english)'), findsOneWidget);
      expect(startCalls, 2);
      await unmount(tester);
    });

    testWidgets(
        'DiagnosticBottomNav is not rendered when is_fixed_variant is false '
        '(adaptive CAT flow)', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 30,
            'subject': subject,
            'question': _question(),
          }, isFixedVariant: false);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(find.byType(DiagnosticBottomNav), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'DiagnosticBottomNav is rendered when is_fixed_variant is true '
        '(fixed-variant math bank)', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 30,
            'subject': subject,
            'question': _question(),
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(find.byType(DiagnosticBottomNav), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
        'header shows a countdown derived from duration_minutes on the '
        'start-attempt response', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 5,
            'subject': subject,
            'question': _question(),
          }, durationMinutes: 20);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('20:00'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await unmount(tester);
    });

    List<Map<String, dynamic>> fullPackageQuestions(int count) => [
          for (var i = 1; i <= count; i++)
            _question(id: 'q$i', text: 'Savol $i')
        ];

    testWidgets(
        'full-package mode: tapping a question dot jumps position with no '
        'extra network calls', (tester) async {
      var submitCalls = 0;
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 3,
            'subject': subject,
            'questions': fullPackageQuestions(3),
          }, isFixedVariant: true);
        },
        submitAnswerOverride: (
            {required attemptId,
            required questionId,
            required selected}) async {
          submitCalls++;
          throw StateError(
              'submitAnswer must not be called in full-package mode');
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(find.text('Savol 1'), findsOneWidget);

      await tester.tap(find.text('03'));
      await tester.pump();

      expect(find.text('Savol 3'), findsOneWidget);
      expect(submitCalls, 0);
      await unmount(tester);
    });

    testWidgets('selecting an option in full-package mode does not submit',
        (tester) async {
      var submitCalls = 0;
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'questions': fullPackageQuestions(2),
          }, isFixedVariant: true);
        },
        submitAnswerOverride: (
            {required attemptId,
            required questionId,
            required selected}) async {
          submitCalls++;
          throw StateError(
              'submitAnswer must not be called in full-package mode');
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.text('Variant B'));
      await tester.pump();

      expect(submitCalls, 0);
      expect(find.text('Savol 1'), findsOneWidget); // still on same question
      await unmount(tester);
    });

    testWidgets(
        'last-question button shows "next subject" label, not "finish", '
        'when another subject follows', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math', 'ingliz']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'questions': fullPackageQuestions(2),
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.text('02'));
      await tester.pump();

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;
      expect(find.text(l10n.nextSubjectButton), findsOneWidget);
      expect(find.text(l10n.finishTestButton), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'last-question button still shows "finish" label when it is the '
        'only/last subject', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'questions': fullPackageQuestions(2),
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.text('02'));
      await tester.pump();

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;
      expect(find.text(l10n.finishTestButton), findsOneWidget);
      expect(find.text(l10n.nextSubjectButton), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'selecting an option auto-advances to the next question after 500ms',
        (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'questions': fullPackageQuestions(2),
          }, isFixedVariant: true);
        },
        submitAnswerOverride: (
            {required attemptId,
            required questionId,
            required selected}) async {
          throw StateError(
              'submitAnswer must not be called in full-package mode');
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.text('Variant B'));
      await tester.pump();
      expect(find.text('Savol 1'), findsOneWidget); // not yet advanced

      await tester.pump(const Duration(milliseconds: 499));
      expect(find.text('Savol 1'), findsOneWidget); // still not yet

      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Savol 2'), findsOneWidget); // auto-advanced

      // Last question: selecting must NOT schedule a further auto-advance.
      await tester.tap(find.text('Variant B'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Savol 2'), findsOneWidget); // stays put

      await unmount(tester);
    });

    testWidgets(
        'unanswered questions show the finish-confirmation dialog; '
        'confirming calls finishAttempt exactly once', (tester) async {
      var finishCalls = 0;
      List<Map<String, dynamic>>? capturedAnswers;
      await tester.pumpWidget(_wrapWithRouter(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'questions': fullPackageQuestions(2),
          }, isFixedVariant: true);
        },
        finishAttemptOverride: ({required attemptId, required answers}) async {
          finishCalls++;
          capturedAnswers = answers;
          return {'finished': true};
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      // Answer only the first question, leave the second unanswered.
      await tester.tap(find.text('Variant A'));
      await tester.pump();

      // "Testni yakunlash" only replaces "Keyingi" on the last question.
      await tester.tap(find.text('02'));
      await tester.pump();

      await tester.tap(find.text('Testni yakunlash'));
      await tester.pump();

      // Confirmation dialog appears (1 question unanswered).
      expect(find.text('Tugatish?'), findsOneWidget);
      expect(finishCalls, 0);

      await tester.tap(find.text('Tugatish'));
      await tester.pump();
      await tester.pump();

      expect(finishCalls, 1);
      expect(capturedAnswers?.length, 1);
      expect(capturedAnswers?.first['question_id'], 'q1');
      expect(capturedAnswers?.first['selected'], 'A');
      await unmount(tester);
    });

    testWidgets(
        'all questions answered: finish skips the dialog and calls '
        'finishAttempt once', (tester) async {
      var finishCalls = 0;
      await tester.pumpWidget(_wrapWithRouter(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 1,
            'subject': subject,
            'questions': fullPackageQuestions(1),
          }, isFixedVariant: true);
        },
        finishAttemptOverride: ({required attemptId, required answers}) async {
          finishCalls++;
          return {'finished': true};
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.text('Variant A'));
      await tester.pump();

      await tester.tap(find.text('Testni yakunlash'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Tugatish?'), findsNothing);
      expect(finishCalls, 1);
      await unmount(tester);
    });

    testWidgets(
        'early-finish button is shown on non-last questions and hidden on '
        'the last one', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'questions': fullPackageQuestions(2),
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;
      // Position 1/2: not the last question — the early-finish label (which
      // reuses finishTestButton's string) is the only "Testni yakunlash"
      // text on screen, since the last-question Finish button isn't shown.
      expect(find.text(l10n.finishTestButton), findsOneWidget);

      await tester.tap(find.text('02'));
      await tester.pump();

      // Position 2/2: last question — the last-question Finish button now
      // covers it, the early-finish button must not duplicate it.
      expect(find.text(l10n.finishTestButton), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'tapping early-finish asks to confirm, then defers to the normal '
        'finish flow (which re-warns about unanswered questions)',
        (tester) async {
      var finishCalls = 0;
      await tester.pumpWidget(_wrapWithRouter(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'questions': fullPackageQuestions(2),
          }, isFixedVariant: true);
        },
        finishAttemptOverride: ({required attemptId, required answers}) async {
          finishCalls++;
          return {'finished': true};
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;

      // Nothing answered yet, still on question 1 of 2 (not the last one).
      await tester.tap(find.text(l10n.finishTestButton));
      await tester.pump();

      // Early-finish's own "are you sure" gate.
      expect(find.text(l10n.earlyFinishConfirmTitle), findsOneWidget);
      expect(finishCalls, 0);

      await tester.tap(find.text(l10n.earlyFinishConfirmButton));
      await tester.pump();

      // Defers straight into _confirmAndFinishPackage, which re-warns since
      // both questions are unanswered — no duplicate warning was built here.
      expect(find.text(l10n.finishConfirmTitle), findsOneWidget);
      expect(finishCalls, 0);

      await tester.tap(find.text(l10n.finishTest));
      await tester.pump();
      await tester.pump();

      expect(finishCalls, 1);
      await unmount(tester);
    });

    // NOTE: a widget-level test asserting the finish-failure path actually
    // lands a row in OfflineQueue's `local_queue` table was attempted here
    // and removed — `OfflineQueue.db` opens the real sqflite plugin (not
    // sqflite_common_ffi, which this file only wires up for
    // Windows/Linux), and that plugin has no platform-channel binding under
    // plain `flutter test` on this host: the native call hangs instead of
    // throwing, timing out the whole suite. Not feasible from this harness;
    // see diagnostic_test_runner_screen.dart's `_confirmAndFinishPackage`
    // for the reviewed production logic instead (mirrors
    // submitQuestionReport/submitLocalResultFull's exact permanent/
    // retryable classification already exercised by production traffic).

    testWidgets(
        'fixed-variant finish with next_subject advances to the next '
        'subject instead of ending the attempt', (tester) async {
      var startCalls = 0;
      Object? capturedExtra;
      await tester.pumpWidget(_wrapWithRouter(
        DiagnosticTestRunnerScreen(
          attemptId: 'att-1',
          studentName: 'Aliyev Ali',
          grade: 3,
          language: 'uz',
          availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
              {
            'subjects': ['math']
          },
          startAttemptOverride: ({required attemptId, required subject}) async {
            startCalls++;
            return _withMeta({
              'position': 1,
              'total_questions': 1,
              'subject': subject,
              'questions': fullPackageQuestions(1),
            }, isFixedVariant: true);
          },
          finishAttemptOverride: (
              {required attemptId, required answers}) async {
            return {'finished': true, 'next_subject': 'english'};
          },
        ),
        onFinished: (extra) => capturedExtra = extra,
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(startCalls, 1);

      await tester.tap(find.text('Variant A'));
      await tester.pump();

      await tester.tap(find.text('Testni yakunlash'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      await tester.pump();

      // Advanced into a second fixed-variant subject instead of finishing.
      expect(startCalls, 2);
      expect(capturedExtra, isNull);
      await unmount(tester);
    });

    testWidgets(
        'transient finish-call failure with a next subject available '
        'starts that subject instead of ending the test', (tester) async {
      var startCalls = 0;
      Object? capturedExtra;
      await tester.pumpWidget(_wrapWithRouter(
        DiagnosticTestRunnerScreen(
          attemptId: 'att-1',
          studentName: 'Aliyev Ali',
          grade: 3,
          language: 'uz',
          availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
              {
            'subjects': ['math', 'english']
          },
          startAttemptOverride: ({required attemptId, required subject}) async {
            startCalls++;
            return _withMeta({
              'position': 1,
              'total_questions': 1,
              'subject': subject,
              'questions': fullPackageQuestions(1),
            }, isFixedVariant: true);
          },
          finishAttemptOverride: (
              {required attemptId, required answers}) async {
            // Transient failure (timeout/dropped connection), not a
            // definitive server rejection.
            throw const ApiException(0, 'timeout');
          },
          enqueueLocalOverride: (payload, token) async {},
        ),
        onFinished: (extra) => capturedExtra = extra,
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(startCalls, 1);

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;

      await tester.tap(find.text('Variant A'));
      await tester.pump();
      await tester.tap(find.text(l10n.nextSubjectButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Moved on to 'english' locally instead of ending the diagnostic.
      expect(startCalls, 2);
      expect(capturedExtra, isNull);
      await unmount(tester);
    });

    testWidgets(
        'a later subject also prefers a real start-attempt call over a '
        'stale peeked package instead of silently reusing it (regression: '
        'previously only the FIRST subject was protected against the '
        'no_variant_number bug class)', (tester) async {
      var englishStartCalls = 0;
      await tester.pumpWidget(_wrapWithRouter(
        DiagnosticTestRunnerScreen(
          attemptId: 'att-1',
          studentName: 'Aliyev Ali',
          grade: 3,
          language: 'uz',
          availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
              {
            'subjects': ['math', 'english']
          },
          // Simulates DiagnosticStudentSelectScreen's bulk "download whole
          // class" prefetch already having peeked BOTH subjects ahead of
          // time via kiosk/peek/ (dry_run) — 'english' has a stale peeked
          // package cached from initState that was never confirmed by a
          // real kiosk/start/ call.
          prefetchedSubjects: {
            'english': _withMeta({
              'position': 1,
              'total_questions': 1,
              'subject': 'english',
              'questions': [
                _question(id: 'peeked-e1', text: 'Peeked ingliz savoli')
              ],
            }, isFixedVariant: true),
          },
          startAttemptOverride: ({required attemptId, required subject}) async {
            if (subject == 'english') {
              englishStartCalls++;
              return _withMeta({
                'position': 1,
                'total_questions': 1,
                'subject': 'english',
                'questions': [
                  _question(id: 'live-e1', text: 'Live ingliz savoli')
                ],
              }, isFixedVariant: true);
            }
            return _withMeta({
              'position': 1,
              'total_questions': 1,
              'subject': 'math',
              'questions': fullPackageQuestions(1),
            }, isFixedVariant: true);
          },
          finishAttemptOverride: (
              {required attemptId, required answers}) async {
            // math's finish call fails offline — the exact scenario this
            // whole offline-queue feature exists for.
            throw const ApiException(0, 'no internet');
          },
          enqueueLocalOverride: (payload, token) async {},
        ),
        onFinished: (extra) {},
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;
      await tester.tap(find.text('Variant A'));
      await tester.pump();
      await tester.tap(find.text(l10n.nextSubjectButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(englishStartCalls, 1);
      expect(find.text('Live ingliz savoli'), findsOneWidget);
      expect(find.text('Peeked ingliz savoli'), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'transient finish-call failure with no next subject left still '
        'ends the test', (tester) async {
      Object? capturedExtra;
      await tester.pumpWidget(_wrapWithRouter(
        DiagnosticTestRunnerScreen(
          attemptId: 'att-1',
          studentName: 'Aliyev Ali',
          grade: 3,
          language: 'uz',
          availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
              {
            'subjects': ['math']
          },
          startAttemptOverride: ({required attemptId, required subject}) async {
            return _withMeta({
              'position': 1,
              'total_questions': 1,
              'subject': subject,
              'questions': fullPackageQuestions(1),
            }, isFixedVariant: true);
          },
          finishAttemptOverride: (
              {required attemptId, required answers}) async {
            throw const ApiException(0, 'timeout');
          },
          enqueueLocalOverride: (payload, token) async {},
        ),
        onFinished: (extra) => capturedExtra = extra,
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.text('Variant A'));
      await tester.pump();
      await tester.tap(find.text('Testni yakunlash'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // 'math' was the only/last subject -> genuinely ends the test.
      final extraMap = capturedExtra as Map<String, dynamic>?;
      expect(extraMap?['subjectsCompleted'], ['math']);
      await unmount(tester);
    });

    testWidgets(
        'both subjects appear in subjectsCompleted extra after full CAT '
        'completion', (tester) async {
      Object? capturedExtra;
      var submitCalls = 0;
      await tester.pumpWidget(_wrapWithRouter(
        DiagnosticTestRunnerScreen(
          attemptId: 'att-1',
          studentName: 'Aliyev Ali',
          grade: 1,
          language: 'uz',
          availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
              {
            'subjects': ['math']
          },
          startAttemptOverride: ({required attemptId, required subject}) async {
            return {
              'position': 1,
              'total_questions': 1,
              'subject': subject,
              'question': _question(id: 'q-$subject', text: 'Savol ($subject)'),
            };
          },
          submitAnswerOverride: (
              {required attemptId,
              required questionId,
              required selected}) async {
            submitCalls++;
            if (submitCalls == 1) {
              return {'finished': true, 'next_subject': 'english'};
            }
            return {'finished': true, 'next_subject': ''};
          },
        ),
        onFinished: (extra) => capturedExtra = extra,
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Answer math's question -> triggers subject transition to english.
      await tester.tap(find.text('Variant A'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      await tester.pump();

      expect(find.text('Savol (english)'), findsOneWidget);

      // Answer english's question -> finishes the whole test.
      await tester.tap(find.text('Variant A'));
      await tester.pump();
      await tester.pump();

      final extraMap = capturedExtra as Map<String, dynamic>?;
      expect(extraMap?['subjectsCompleted'], ['math', 'english']);
      await unmount(tester);
    });

    testWidgets(
        'fixed-variant header shows a grade pill and hides the CAT-only '
        'subject-pill/answered-counter row', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'questions': fullPackageQuestions(2),
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(find.text('3-sinf'), findsOneWidget);
      expect(find.text('javoblandi'), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'DiagnosticQuestionDots renders above the question card for a '
        'fixed-variant attempt', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'questions': fullPackageQuestions(2),
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(find.byType(DiagnosticQuestionDots), findsOneWidget);
      final dotsY = tester.getTopLeft(find.byType(DiagnosticQuestionDots)).dy;
      final cardY = tester.getTopLeft(find.byType(DiagnosticQuestionCard)).dy;
      expect(dotsY, lessThan(cardY));
      await unmount(tester);
    });

    testWidgets(
        'first question hides/disables Previous; last question shows '
        'Finish instead of Next', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'questions': fullPackageQuestions(2),
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      final prevButton =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(prevButton.onPressed, isNull);
      expect(find.text('Keyingi'), findsOneWidget);
      // "Testni yakunlash" DOES appear here, but as the early-finish button
      // (Icons.flag_outlined) — not the last-question Finish button.
      expect(find.text('Testni yakunlash'), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsOneWidget);

      await tester.tap(find.text('02'));
      await tester.pump();

      final prevButton2 =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(prevButton2.onPressed, isNotNull);
      // Last question: only the Finish button remains, the early-finish
      // button is hidden so there is no duplicate.
      expect(find.text('Testni yakunlash'), findsOneWidget);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      expect(find.text('Keyingi'), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'error while starting a later subject: Retry re-starts that subject '
        '(not the first) and shows a generic message, not raw backend text',
        (tester) async {
      final startCalls = <String>[];
      var mathAnswered = false;
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math', 'english']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          startCalls.add(subject);
          // 'english' fails its first TWO attempts: the background
          // prefetch kicked off right after 'math' finishes (so it never
          // lands in _prefetchedSubjectPackages), and the live attempt made
          // by _startSubject when the transition actually happens. It
          // succeeds on manual retry (3rd attempt).
          if (subject == 'english' &&
              startCalls.where((s) => s == 'english').length <= 2) {
            throw const ApiException(400, 'math allaqachon yakunlangan');
          }
          return _withMeta({
            'position': 1,
            'total_questions': 1,
            'subject': subject,
            'question_id': '${subject}_q1',
            'question_text': 'Savol ($subject)',
            'option_a': 'A',
            'option_b': 'B',
            'option_c': 'C',
            'option_d': 'D',
          });
        },
        submitAnswerOverride: (
            {required attemptId,
            required questionId,
            required selected}) async {
          mathAnswered = true;
          return {
            'finished': true,
            'next_subject': 'english',
          };
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      // Answer the math question -> triggers the subject transition ->
      // startAttempt('english') which fails on its first attempt.
      await tester.tap(find.text('A').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      // subject-transition screen, then english start kicks off
      await tester.pump(const Duration(milliseconds: 1600));
      expect(mathAnswered, isTrue);
      // No eager bootstrap prefetch anymore — 'english' is only attempted
      // once 'math' actually finishes: first the background prefetch fired
      // from `_submit`'s finished+next_subject branch, then the live
      // attempt `_startSubject` makes for the transition. Both fail.
      expect(startCalls, ['math', 'english', 'english']);

      // Generic message shown, not the raw backend text.
      expect(find.text('math allaqachon yakunlangan'), findsNothing);
      expect(
          find.text('Server xatosi. Qayta urinib ko\'ring.'), findsOneWidget);

      await tester.tap(find.text('Qayta urinish'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Retry re-attempted 'english', never re-triggered 'math'.
      expect(startCalls, ['math', 'english', 'english', 'english']);
      expect(find.text('Savol (english)'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
        'a successfully background-prefetched subject transition makes no '
        'new live startAttempt call for that subject', (tester) async {
      final startCalls = <String>[];
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math', 'english']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          startCalls.add(subject);
          return _withMeta({
            'position': 1,
            'total_questions': 1,
            'subject': subject,
            'question_id': '${subject}_q1',
            'question_text': 'Savol ($subject)',
            'option_a': 'A',
            'option_b': 'B',
            'option_c': 'C',
            'option_d': 'D',
          });
        },
        submitAnswerOverride: (
            {required attemptId,
            required questionId,
            required selected}) async {
          return {
            'finished': true,
            'next_subject': 'english',
          };
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // No eager bootstrap prefetch anymore — only 'math' has started.
      expect(startCalls, ['math']);

      await tester.tap(find.text('A').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 1600));

      // 'english' was background-prefetched the moment 'math' finished (see
      // `_submit`), so the subject transition used that prefetched package —
      // no 2nd 'english' startAttempt call.
      expect(startCalls, ['math', 'english']);
      expect(find.text('Savol (english)'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
        'bootstrap failure (nothing cached yet) auto-retries once '
        'connectivity comes back, with no manual Retry tap', (tester) async {
      var subjectsCalls = 0;
      final connController =
          StreamController<List<ConnectivityResult>>.broadcast();
      addTearDown(connController.close);

      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        connectivityStreamOverride: connController.stream,
        availableSubjectsOverride: (grade, {String language = 'uz'}) async {
          subjectsCalls++;
          if (subjectsCalls == 1) {
            throw const ApiException(0, 'no internet');
          }
          return {
            'subjects': ['math']
          };
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return _withMeta({
            'position': 1,
            'total_questions': 1,
            'subject': subject,
            'questions': fullPackageQuestions(1),
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // First fetch failed — generic error view shown, only 1 call so far.
      expect(subjectsCalls, 1);
      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;
      expect(find.text(l10n.serverErrorRetry), findsOneWidget);

      // Connectivity comes back — no manual Retry tap needed.
      connController.add([ConnectivityResult.wifi]);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(subjectsCalls, 2);
      expect(find.text(l10n.serverErrorRetry), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'a successful manual retry after a bootstrap failure cancels the '
        'auto-retry listener, so a later connectivity blip does not '
        'spuriously re-invoke whatever _retryAction has since become',
        (tester) async {
      var subjectsCalls = 0;
      var startCalls = 0;
      final connController =
          StreamController<List<ConnectivityResult>>.broadcast();
      addTearDown(connController.close);

      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        connectivityStreamOverride: connController.stream,
        availableSubjectsOverride: (grade, {String language = 'uz'}) async {
          subjectsCalls++;
          if (subjectsCalls == 1) {
            throw const ApiException(0, 'no internet');
          }
          return {
            'subjects': ['math']
          };
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          startCalls++;
          return _withMeta({
            'position': 1,
            'total_questions': 1,
            'subject': subject,
            'questions': fullPackageQuestions(1),
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // First fetch failed — auto-retry listener is now armed.
      expect(subjectsCalls, 1);
      expect(startCalls, 0);

      // Manual retry succeeds (e.g. a stale connectivity reading that never
      // actually fires the listener) — this must cancel the stale
      // subscription, not just move on.
      await tester.tap(find.text('Qayta urinish'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(subjectsCalls, 2);
      expect(startCalls, 1);
      expect(find.byType(DiagnosticQuestionCard), findsOneWidget);

      // A later, unrelated connectivity blip must NOT re-invoke whatever
      // `_retryAction` has since become (`_startSubject('math')` at this
      // point) — the bug this test guards against was a spurious duplicate
      // network call/submission mid-test from a stale listener.
      connController.add([ConnectivityResult.wifi]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(subjectsCalls, 2);
      expect(startCalls, 1);
      await unmount(tester);
    });

    testWidgets(
        '_startSubject auto-retries via connectivity once online again after '
        'a network failure with no prefetched package', (tester) async {
      var startAttemptCalls = 0;
      final connController =
          StreamController<List<ConnectivityResult>>.broadcast();
      addTearDown(connController.close);

      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        connectivityStreamOverride: connController.stream,
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          startAttemptCalls++;
          if (startAttemptCalls == 1) {
            throw const ApiException(0, 'no internet');
          }
          return _withMeta({
            'position': 1,
            'total_questions': 1,
            'subject': subject,
            'questions': fullPackageQuestions(1),
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // First live start-call failed offline, nothing prefetched — generic
      // error view shown, only 1 call so far.
      expect(startAttemptCalls, 1);
      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;
      expect(find.text(l10n.serverErrorRetry), findsOneWidget);

      // Connectivity comes back — no manual Retry tap needed.
      connController.add([ConnectivityResult.wifi]);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(startAttemptCalls, 2);
      expect(find.text(l10n.serverErrorRetry), findsNothing);
      await unmount(tester);
    });

    testWidgets(
        'header countdown is seeded from remaining_seconds when present, '
        'overriding duration_minutes', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          return {
            ..._withMeta({
              'position': 1,
              'total_questions': 5,
              'subject': subject,
              'question': _question(),
            }, durationMinutes: 20),
            // Backend now also sends remaining_seconds — must win over the
            // 20-minute duration_minutes value (which would show 20:00).
            'remaining_seconds': 90,
          };
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('01:30'), findsOneWidget);
      expect(find.textContaining('20:00'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await unmount(tester);
    });

    testWidgets(
        'prefetchedSubjects does NOT skip the real first-subject start call '
        '(would never persist variant_number — see kiosk/finish 400 '
        'no_variant_number regression)', (tester) async {
      var startCalls = 0;
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        prefetchedSubjects: {
          'math': _withMeta({
            'position': 1,
            'total_questions': 3,
            'subject': 'math',
            'questions': [
              _question(id: 'q1'),
              _question(id: 'q2'),
              _question(id: 'q3'),
            ],
          }, isFixedVariant: true),
        },
        // The first subject must always go through a real kiosk/start/ call
        // (this is what persists `attempt.variant_number` server-side) —
        // a peeked (dry_run) package alone is never enough. Return a valid
        // response instead of throwing.
        startAttemptOverride: ({required attemptId, required subject}) async {
          startCalls++;
          return _withMeta({
            'position': 1,
            'total_questions': 3,
            'subject': 'math',
            'questions': [
              _question(id: 'q1'),
              _question(id: 'q2'),
              _question(id: 'q3'),
            ],
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The real call now DOES happen, exactly once — it must never be
      // skipped in favor of the warm peek cache for the first subject.
      expect(startCalls, 1);
      expect(find.byType(DiagnosticQuestionCard), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await unmount(tester);
    });

    testWidgets(
        'first subject prefers the LIVE start-attempt response over a '
        'stale peeked package when online (production no_variant_number '
        'regression: peek is dry_run and never persists variant_number)',
        (tester) async {
      var startCalls = 0;
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        // A stale peeked package — must be ignored while the device is
        // online, since it was never persisted server-side.
        prefetchedSubjects: {
          'math': _withMeta({
            'position': 1,
            'total_questions': 3,
            'subject': 'math',
            'questions': [_question(id: 'peeked-q1', text: 'Peeked savol')],
          }, isFixedVariant: true),
        },
        // The real, persisted response — must be what actually renders.
        startAttemptOverride: ({required attemptId, required subject}) async {
          startCalls++;
          return _withMeta({
            'position': 1,
            'total_questions': 5,
            'subject': 'math',
            'questions': [_question(id: 'live-q1', text: 'Live savol')],
          }, isFixedVariant: true);
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(startCalls, 1);
      expect(find.text('Live savol'), findsOneWidget);
      expect(find.text('Peeked savol'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await unmount(tester);
    });

    testWidgets(
        'bootstrap falls back to prefetchedAllSubjects + a cached package '
        'when the live availableSubjects call fails offline (fresh, '
        'non-resumed attempt)', (tester) async {
      var subjectsCalls = 0;
      var startCalls = 0;
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        // The live call always fails (device went offline right after the
        // student card was tapped) — this must NOT strand the attempt when
        // the student-select screen already resolved the subject list and
        // warmed 'math' via kiosk/peek/.
        availableSubjectsOverride: (grade, {String language = 'uz'}) async {
          subjectsCalls++;
          throw const ApiException(0, 'no internet');
        },
        prefetchedAllSubjects: const ['math', 'english'],
        prefetchedSubjects: {
          'math': _withMeta({
            'position': 1,
            'total_questions': 3,
            'subject': 'math',
            'questions': [
              _question(id: 'q1'),
              _question(id: 'q2'),
              _question(id: 'q3'),
            ],
          }, isFixedVariant: true),
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          startCalls++;
          throw Exception('must not be called — subject was prefetched');
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Started straight from the cached package — no live start-attempt
      // call, and no generic error/retry dead-end shown.
      expect(subjectsCalls, 1);
      expect(startCalls, 0);
      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;
      expect(find.text(l10n.serverErrorRetry), findsNothing);
      expect(find.byType(DiagnosticQuestionCard), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await unmount(tester);
    });

    testWidgets(
        'bootstrap still shows the generic error when availableSubjects '
        'fails and no prefetched fallback is available', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async {
          throw const ApiException(0, 'no internet');
        },
        // No prefetchedAllSubjects/prefetchedSubjects at all — nothing to
        // fall back to, so the old hard-error behavior must still apply.
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;
      expect(find.text(l10n.serverErrorRetry), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
        '429 (rate limit) during answer submit falls to the retry banner, '
        'not the stale-state self-heal that would just 429 again',
        (tester) async {
      var startCalls = 0;
      var submitCalls = 0;
      await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        grade: 3,
        language: 'uz',
        availableSubjectsOverride: (grade, {String language = 'uz'}) async => {
          'subjects': ['math']
        },
        startAttemptOverride: ({required attemptId, required subject}) async {
          startCalls++;
          return _withMeta({
            'position': 1,
            'total_questions': 2,
            'subject': subject,
            'question_id': 'q1',
            'question_text': 'Savol 1',
            'option_a': 'A',
            'option_b': 'B',
            'option_c': 'C',
            'option_d': 'D',
          });
        },
        submitAnswerOverride: (
            {required attemptId,
            required questionId,
            required selected}) async {
          submitCalls++;
          throw const ApiException(429, "Ko'p urinish, biroz kuting");
        },
      )));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      expect(startCalls, 1);
      await tester.tap(find.text('A').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // A 429 must NOT be treated as a client rejection of THIS answer's
      // content — the self-heal (_startSubject re-fetch) would very likely
      // just 429 again inside the same throttle window. It falls to the
      // generic retry banner instead, with no extra startAttempt call.
      expect(startCalls, 1);
      expect(submitCalls, 1);
      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;
      expect(find.text(l10n.serverErrorRetry), findsOneWidget);

      await tester.tap(find.text(l10n.retry));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Retry re-attempts the exact same submit, not a fresh startAttempt.
      expect(startCalls, 1);
      expect(submitCalls, 2);
      await unmount(tester);
    });

    testWidgets(
        '429 (rate limit) on the finish call queues the answers and moves '
        'on like a transient network failure, ending the test when there is '
        'no next subject (not the "already finished" self-heal remap)',
        (tester) async {
      Object? capturedExtra;
      var enqueueCalls = 0;
      Map<String, dynamic>? capturedPayload;
      await tester.pumpWidget(_wrapWithRouter(
        DiagnosticTestRunnerScreen(
          attemptId: 'att-1',
          studentName: 'Aliyev Ali',
          grade: 3,
          language: 'uz',
          availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
              {
            'subjects': ['math']
          },
          startAttemptOverride: ({required attemptId, required subject}) async {
            return _withMeta({
              'position': 1,
              'total_questions': 1,
              'subject': subject,
              'questions': [_question(id: 'q1', correctDisplayLetter: 'A')],
            }, isFixedVariant: true);
          },
          finishAttemptOverride: (
              {required attemptId, required answers}) async {
            // The diagnostic_guest throttle scope is shared by every kiosk
            // endpoint — a busy QA session can plausibly exhaust it right on
            // a legitimate finish call.
            throw const ApiException(429, "Ko'p urinish, biroz kuting");
          },
          enqueueLocalOverride: (payload, token) async {
            enqueueCalls++;
            capturedPayload = payload;
          },
        ),
        onFinished: (extra) => capturedExtra = extra,
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.text('Variant A'));
      await tester.pump();
      await tester.tap(find.text('Testni yakunlash'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // Queued for later sync and ended the test locally — did NOT run the
      // self-heal remap (which would re-call startAttempt/finishAttempt and,
      // on failure, dead-end on the generic error banner instead of
      // navigating away).
      expect(enqueueCalls, 1);
      final extraMap = capturedExtra as Map<String, dynamic>?;
      expect(extraMap?['subjectsCompleted'], ['math']);
      // The queued finish payload carries its own self-scoring answer key —
      // built from the ALREADY-downloaded package's correct_display_letter
      // fields — so a genuinely-never-synced attempt can still be locally
      // scored, export-time-only, later (see DiagnosticExportService).
      final answerKey =
          capturedPayload?['_offline_answer_key'] as Map<String, dynamic>?;
      expect(answerKey, isNotNull);
      expect(answerKey!['subject'], 'math');
      expect(answerKey['answers'], {'q1': 'A'});
      await unmount(tester);
    });
  });
}
