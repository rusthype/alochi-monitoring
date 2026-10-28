// When the server cannot be reached (network / timeout / 5xx) the roster
// screen shows the last good roster of the group from this PC, labelled
// "Oflayn ro'yxat" with a Retry; a real server "no" (404) or an empty cache
// still shows the error banner. An empty answer never replaces a good cache.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/features/session/test_session.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _session = TestSession(
  testKey: 'mon:roster',
  title: 'T',
  runnerType: 'engine',
  schoolCode: '999',
  schoolLabel: '999',
  testGrade: 5,
);

class _RosterApi extends MonitoringApi {
  List<Map<String, dynamic>> students = [];
  Object? failWith;
  @override
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId,
      {String? testKey}) async {
    final f = failWith;
    if (f != null) throw f;
    return students;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitoringApi savedApi;
  late _RosterApi fake;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    savedApi = api;
    fake = _RosterApi();
    api = fake;
    SharedPreferences.setMockInitialValues({});
    TestCatalogService.resetKnownMissingForTest();
    TestCache.exitMemoryMode();
    dir = Directory.systemTemp.createTempSync('roster_fallback_');
    TestCache.pathOverride = '${dir.path}/tc.db';
  });
  tearDown(() async {
    api = savedApi;
    await TestCache.resetForTest();
    dir.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpRoster(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

  final good = [
    {'id': 's1', 'student_code': 'S-1', 'name': 'Valiyev Ali', 'done': true},
    {'id': 's2', 'student_code': 'S-2', 'name': 'Karimov Bobur', 'done': false},
  ];

  testWidgets('a good load is remembered; offline shows it with the banner',
      (tester) async {
    fake.students = good;
    await pumpRoster(tester); // online: caches
    expect(find.textContaining('Valiyev'), findsOneWidget);
    expect(find.byKey(const Key('offlineRosterBanner')), findsNothing);

    // Next visit: the network is down.
    await tester.pumpWidget(const SizedBox());
    fake.failWith = const ApiException(0, 'x', code: kApiNetwork);
    await pumpRoster(tester);
    final t = l10n(tester);

    expect(find.textContaining('Valiyev'), findsOneWidget);
    expect(find.textContaining('Karimov'), findsOneWidget);
    expect(find.text(t.offlineRosterBanner), findsOneWidget);
    expect(find.text(t.loadStudentsError), findsNothing);
    // The cached `done` flag still marks the finished student.
    expect(find.text(t.rosterDoneBadge), findsOneWidget);

    // Retry after the connection came back replaces it with the live list.
    fake
      ..failWith = null
      ..students = [
        {'id': 's3', 'student_code': 'S-3', 'name': 'Sobirov Sardor'}
      ];
    await tester.tap(find.text(t.retry));
    await settle(tester);
    expect(find.textContaining('Sobirov'), findsOneWidget);
    expect(find.textContaining('Valiyev'), findsNothing);
    expect(find.text(t.offlineRosterBanner), findsNothing);
  });

  testWidgets('5xx and timeouts also fall back to the cache', (tester) async {
    await tester.runAsync(() => TestCache.putRoster('g1', 'mon:roster', good));
    for (final err in [
      const ApiException(503, 'x'),
      const ApiException(0, 'x', code: kApiTimeout),
    ]) {
      fake.failWith = err;
      await pumpRoster(tester);
      expect(find.textContaining('Valiyev'), findsOneWidget, reason: '$err');
      expect(find.text(l10n(tester).offlineRosterBanner), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a real 404 is not answered with the cache', (tester) async {
    await tester.runAsync(() => TestCache.putRoster('g1', 'mon:roster', good));
    fake.failWith = const ApiException(404, 'gone');
    await pumpRoster(tester);
    final t = l10n(tester);
    expect(find.textContaining('Valiyev'), findsNothing);
    expect(find.text(t.loadStudentsError), findsOneWidget);
    expect(find.text(t.offlineRosterBanner), findsNothing);
  });

  testWidgets('no cache: the error banner with retry (unchanged)',
      (tester) async {
    fake.failWith = const ApiException(0, 'x', code: kApiNetwork);
    await pumpRoster(tester);
    final t = l10n(tester);
    expect(find.text(t.loadStudentsError), findsOneWidget);
    expect(find.text(t.offlineRosterBanner), findsNothing);
  });

  testWidgets('an empty answer never replaces a good cached roster',
      (tester) async {
    fake.students = good;
    await pumpRoster(tester);
    await tester.pumpWidget(const SizedBox());

    fake.students = []; // server answers with an empty list once
    await pumpRoster(tester);
    expect(find.text(l10n(tester).noStudentsInGroup), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    fake.failWith = const ApiException(0, 'x', code: kApiNetwork);
    await pumpRoster(tester);
    expect(find.textContaining('Valiyev'), findsOneWidget);
  });
}
