// Roster `attempts_remaining`: a done student whose attempt limit is used up
// gets an info dialog instead of the retake confirm; absent / >0 keeps the
// retake confirm; a student who has not taken the test starts as usual.
import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/features/session/test_session.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testKey = 'mon:attempts';

const _session = TestSession(
  testKey: _testKey,
  title: 'T',
  runnerType: 'engine',
  schoolCode: '999',
  schoolLabel: '999',
  testGrade: 5,
);

class _RosterApi extends MonitoringApi {
  _RosterApi(this.students);
  final List<Map<String, dynamic>> students;
  int fetches = 0;
  @override
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId,
      {String? testKey}) async {
    fetches++;
    return students;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitoringApi savedApi;

  setUp(() {
    savedApi = api;
    SharedPreferences.setMockInitialValues({});
    TestCache.enterMemoryMode();
  });

  tearDown(() {
    api = savedApi;
    TestCache.exitMemoryMode();
  });

  Future<AppLocalizations> startFor(
      WidgetTester tester, Map<String, dynamic> row) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    api = _RosterApi([row]);
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StudentEntryScreen(
        session: _session,
        preselectedGroup: {'id': 'g1', 'name': '5-A'},
      ),
    ));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 400));
    final t = AppLocalizations.of(tester.element(find.byType(Scaffold).last))!;
    await tester.tap(find.textContaining('Ali'));
    await tester.pump();
    await tester.tap(find.text(t.startTest));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    return t;
  }

  Map<String, dynamic> row({bool done = true, Object? left = _absent}) => {
        'id': 's1',
        'student_code': 'S-1',
        'name': 'Valiyev Ali',
        'done': done,
        if (!identical(left, _absent)) 'attempts_remaining': left,
      };

  testWidgets(
      'done + attempts_remaining 0 -> info dialog, no retake, no launch',
      (tester) async {
    final t = await startFor(tester, row(left: 0));
    expect(find.text(t.testAttemptsExhaustedTitle), findsOneWidget);
    expect(find.text(t.testAttemptsExhaustedBody), findsOneWidget);
    expect(find.text(t.testRetakeBody), findsNothing);
    expect(find.text(t.diagnosticRetakeConfirm), findsNothing);
    final errorText = t.errorOccurred.replaceFirst(RegExp(r'[:\s]+$'), '');
    expect(find.text(errorText), findsNothing);

    await tester.tap(find.text(t.okBtn));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(t.testAttemptsExhaustedTitle), findsNothing);
    // Not launched: the roster was not reloaded and no launch error toast.
    expect((api as _RosterApi).fetches, 1);
    expect(find.text(errorText), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  for (final c in <String, Object?>{'1': 1, 'absent': _absent}.entries) {
    testWidgets('done + attempts_remaining ${c.key} -> retake confirm',
        (tester) async {
      final t = await startFor(tester, row(left: c.value));
      expect(find.text(t.testRetakeBody), findsOneWidget);
      expect(find.text(t.testAttemptsExhaustedTitle), findsNothing);
      await tester.tap(find.text(t.cancel));
      await tester.pump(const Duration(milliseconds: 400));
      expect((api as _RosterApi).fetches, 1);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });
  }

  testWidgets('not done (even with 0 left) -> normal start', (tester) async {
    final t = await startFor(tester, row(done: false, left: 0));
    expect(find.text(t.testRetakeBody), findsNothing);
    expect(find.text(t.testAttemptsExhaustedTitle), findsNothing);
    // The launch path ran (nothing cached -> it ends, then the roster
    // reloads).
    expect((api as _RosterApi).fetches, 2);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}

const Object _absent = Object();
