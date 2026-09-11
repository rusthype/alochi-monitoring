import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_test_runner_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_bottom_nav.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_option_card.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_question_card.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_question_dots.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/widgets/app_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Map<String, dynamic> _question({
  String id = 'q1',
  String text = 'Savol matni',
  String a = 'Variant A',
  String b = 'Variant B',
  String c = 'Variant C',
  String d = 'Variant D',
  String imageUrl = '',
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
Widget _wrapWithRouter(Widget child) {
  final router = GoRouter(
    initialLocation: '/runner',
    routes: [
      GoRoute(path: '/runner', builder: (_, __) => child),
      GoRoute(
          path: '/diagnostic_finished',
          builder: (_, __) => const SizedBox(key: Key('finished'))),
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

    testWidgets('selecting an option submits selected: "B" and updates the '
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
            'question':
                _question(id: 'q-$subject', text: 'Savol ($subject)'),
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
          for (var i = 1; i <= count; i++) _question(id: 'q$i', text: 'Savol $i')
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
          throw StateError('submitAnswer must not be called in full-package mode');
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
          throw StateError('submitAnswer must not be called in full-package mode');
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
        finishAttemptOverride: (
            {required attemptId, required answers}) async {
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
        finishAttemptOverride: (
            {required attemptId, required answers}) async {
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
      expect(find.text('Testni yakunlash'), findsNothing);

      await tester.tap(find.text('02'));
      await tester.pump();

      final prevButton2 =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(prevButton2.onPressed, isNotNull);
      expect(find.text('Testni yakunlash'), findsOneWidget);
      expect(find.text('Keyingi'), findsNothing);
      await unmount(tester);
    });
  });
}
