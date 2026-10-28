// Session flow hardening of the proctor roster screen: a failed launch never
// locks the Start button or shows raw exception text, a failed roster refresh
// after a test keeps the roster, a failed first load shows a retry banner (not
// "no students"), and two failed prepares redraw the student's variant.
import 'dart:convert';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/roster_done_store.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/features/session/test_session.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testKey = 'mon:flow';

const _session = TestSession(
  testKey: _testKey,
  title: 'T',
  runnerType: 'engine',
  schoolCode: '999',
  schoolLabel: '999',
  testGrade: 5,
);

final _cachedTest = jsonEncode({
  'title': 'T',
  'grade': 5,
  'version': 1,
  'parts': ['Math'],
  'variants': {
    '1': {
      'Math': [
        {
          'type': 'text_choice',
          'q': 'x',
          'opts': ['a', 'b'],
          'ans': 0
        }
      ]
    }
  },
});

class _RosterApi extends MonitoringApi {
  _RosterApi(this.students);
  final List<Map<String, dynamic>> students;
  Object? failWith;
  int calls = 0;
  @override
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId,
      {String? testKey}) async {
    calls++;
    final f = failWith;
    if (f != null) throw f;
    return students;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitoringApi savedApi;

  setUp(() {
    savedApi = api;
    SharedPreferences.setMockInitialValues({});
    TestCatalogService.resetKnownMissingForTest();
    TestCache.enterMemoryMode();
  });

  tearDown(() {
    api = savedApi;
    TestCache.exitMemoryMode();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpRoster(WidgetTester tester) async {
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
    await settle(tester);
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).last))!;

  InkWell startButton(WidgetTester tester) => tester.widget<InkWell>(
      find.byWidgetPredicate(
          (w) => w is InkWell && w.borderRadius == BorderRadius.circular(30)));

  testWidgets('first roster load failure: retry banner, not "no students"',
      (tester) async {
    final fake = _RosterApi([
      {'id': 's1', 'student_code': 'S-1', 'name': 'Valiyev Ali'},
    ])..failWith = const ApiException(503, 'RAW DEBUG TEXT');
    api = fake;
    await pumpRoster(tester);
    final t = l10n(tester);

    expect(find.text(t.loadStudentsError), findsOneWidget);
    expect(find.text(t.noStudentsInGroup), findsNothing);
    expect(find.textContaining('RAW DEBUG TEXT'), findsNothing);
    expect(find.text(t.retry), findsOneWidget);

    fake.failWith = null;
    await tester.tap(find.text(t.retry));
    await settle(tester);
    expect(find.textContaining('Ali'), findsOneWidget);
    expect(find.text(t.loadStudentsError), findsNothing);
  });

  testWidgets('a genuinely empty group still says so (no retry banner)',
      (tester) async {
    api = _RosterApi([]);
    await pumpRoster(tester);
    final t = l10n(tester);
    expect(find.text(t.noStudentsInGroup), findsOneWidget);
    expect(find.text(t.loadStudentsError), findsNothing);
  });

  testWidgets('launch failure resets Start, shows a localized toast and '
      'keeps the roster; the done badge comes from the local record',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = _RosterApi([
      {'id': 's1', 'student_code': 'S-1', 'name': 'Ali V'},
      {'id': 's2', 'student_code': 'S-2', 'name': 'Bobur K'},
    ]);
    api = fake;
    // Fully cached test without images -> launchRunner goes all the way to
    // GoRouter.of(context), which throws (no router in this tree).
    await tester.runAsync(
        () => TestCache.upsert(_testKey, 'T', 5, 1, _cachedTest));
    await pumpRoster(tester);
    final t = l10n(tester);

    await tester.tap(find.textContaining('Bobur'));
    for (var i = 0; i < 20 && startButton(tester).onTap == null; i++) {
      await settle(tester);
    }
    expect(startButton(tester).onTap, isNotNull);

    // Another student's attempt was recorded locally; the server is down now.
    await tester.runAsync(() => RosterDoneStore.add(_testKey, 'S-1'));
    fake.failWith = const ApiException(0, 'RAW DEBUG TEXT', code: kApiNetwork);

    await tester.tap(find.text(t.startTest));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await settle(tester);
    }

    // Generic localized toast (errorOccurred without its trailing ": ").
    expect(find.text(t.errorOccurred.replaceFirst(RegExp(r'[:\s]+$'), '')),
        findsOneWidget);
    // Roster survived the failed refresh, both students still listed.
    expect(find.textContaining('Ali'), findsOneWidget);
    expect(find.textContaining('Bobur'), findsOneWidget);
    expect(find.text(t.noStudentsInGroup), findsNothing);
    expect(find.textContaining('RAW DEBUG TEXT'), findsNothing);
    // Local record shows the done badge even though the server refresh failed.
    expect(find.text(t.rosterDoneBadge), findsOneWidget);
    // Raw exception text never reaches the student.
    expect(find.textContaining('GoRouter'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('two failed prepares for a student redraw their variant',
      (tester) async {
    api = _RosterApi([
      {'id': 's1', 'student_code': 'S-1', 'name': 'Ali V'},
    ]);
    final many = jsonDecode(_cachedTest) as Map<String, dynamic>;
    many['variants'] = {
      for (var v = 1; v <= 60; v++)
        '$v': (many['variants'] as Map)['1'],
    };
    await tester.runAsync(
        () => TestCache.upsert(_testKey, 'T', 5, 1, jsonEncode(many)));
    final catalog = _FailingCatalog();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StudentEntryScreen(
        session: _session,
        preselectedGroup: const {'id': 'g1', 'name': '5-A'},
        catalog: catalog,
      ),
    ));
    await tester.pump();
    await settle(tester);

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.textContaining('Ali'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 4)); // toast gone
    }
    final v = catalog.variants;
    expect(v, hasLength(6));
    expect(v[0], v[1], reason: 'one failure keeps the drawn variant');
    expect(v.toSet().length, greaterThan(1),
        reason: 'after 2 failures another variant is drawn');
  });
}

class _FailingCatalog extends TestCatalogService {
  _FailingCatalog() : super(MonitoringApi());
  final variants = <int>[];
  @override
  Future<bool> ensureVariantImages(Map<String, dynamic> cached, int variant,
      {void Function(int done, int total)? onProgress}) async {
    variants.add(variant);
    return false;
  }
}
