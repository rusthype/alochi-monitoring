// After a monitoring test the student must see the neutral thank-you screen
// (DiagnosticFinishedScreen), never the score. Covers the Math+English
// ResultScreen and the JSON-engine EngineResultScreen.
import 'package:alochi_monitoring/core/engine/test_scorer.dart';
import 'package:alochi_monitoring/core/models/models.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_finished_screen.dart';
import 'package:alochi_monitoring/features/result/result_screen.dart';
import 'package:alochi_monitoring/features/test/engine_host_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pushes [screen] on top of a 'PREV' page so a Navigator.pop is observable.
Widget _wrap(Widget screen) => MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => screen)),
            child: const Text('PREV'),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(_wrap(screen));
  await tester.tap(find.text('PREV'));
  await tester.pump(); // start route
  await tester.pump(const Duration(milliseconds: 700)); // settle transition
}

void _expectNoScore(WidgetTester tester) {
  expect(find.byType(DiagnosticFinishedScreen), findsOneWidget);
  expect(find.textContaining('%'), findsNothing);
  expect(find.textContaining(RegExp(r'\d+\s*/\s*\d+')), findsNothing);
  final l10n = AppLocalizations.of(
      tester.element(find.byType(DiagnosticFinishedScreen)))!;
  expect(find.text(l10n.testFinishedTitle), findsNothing); // name is set
  expect(find.textContaining('Diagnostika'), findsNothing);
  expect(find.text(l10n.nextStudent), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageCalls = <MethodCall>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storageCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
      storageCalls.add(call);
      return null;
    });
  });

  testWidgets('ResultScreen shows the finish screen, no score; button pops',
      (tester) async {
    await _open(
      tester,
      const ResultScreen(
        session: StudentSession(
            token: 't', studentId: '1', studentName: 'Valiyev Ali'),
        package: TestPackage(
            id: 'p',
            title: 'T',
            grade: 5,
            mathCount: 1,
            engCount: 1,
            variantCount: 1,
            questionCount: 2),
        result: TestResult(
            packageId: 'p',
            variant: 1,
            mathScore: 9,
            engScore: 8,
            totalPct: 85,
            answers: {},
            deviceId: 'd'),
        synced: true,
        xpEarned: 40,
      ),
    );
    _expectNoScore(tester);
    expect(find.textContaining('40'), findsNothing); // xp not shown

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // The old "Keyingi talaba" cleanup still runs: saved login/password wiped.
    expect(storageCalls.where((c) => c.method == 'delete'), isNotEmpty);
    expect(find.text('PREV'), findsOneWidget);
    expect(find.byType(DiagnosticFinishedScreen), findsNothing);
  });

  testWidgets('EngineResultScreen shows the finish screen, no score; pops',
      (tester) async {
    await _open(
      tester,
      const EngineResultScreen(
        firstName: 'Ali',
        lastName: 'Valiyev',
        school: '56',
        grade: 5,
        variant: 1,
        clientToken: 'tok',
        result: ScoredResult(
          testKey: 'k',
          sectionScores: [],
          totalCorrect: 7,
          totalQuestions: 10,
          totalPct: 70,
          rawAnswers: {},
        ),
      ),
    );
    _expectNoScore(tester);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('PREV'), findsOneWidget);
    // Drain the report-upload retry delays (2s+5s+10s) so no timer is left.
    await tester.pump(const Duration(seconds: 30));
  });
}
