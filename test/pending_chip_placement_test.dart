// The teacher's pending-results chip is on the login, group-select and
// student-roster screens, driven by the real offline queue; absent when empty.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/auth/login_screen.dart';
import 'package:alochi_monitoring/features/session/group_select_screen.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/features/session/test_session.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Api extends MonitoringApi {
  @override
  Future<bool> ping() async => true;
  @override
  Future<List<Map<String, dynamic>>> fetchGroups(String schoolCode,
          {String? schoolId}) async =>
      [
        {'id': 'g1', 'name': '5-A'}
      ];
  @override
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId,
          {String? testKey}) async =>
      [
        {'id': 's1', 'student_code': 'S-1', 'name': 'Ali V'}
      ];
}

const _session = TestSession(
  testKey: 'mon:chip',
  title: 'T',
  runnerType: 'engine',
  schoolCode: '1',
  schoolLabel: '1',
  testGrade: 5,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitoringApi savedApi;
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    savedApi = api;
    api = _Api();
    SharedPreferences.setMockInitialValues({});
    TestCatalogService.resetKnownMissingForTest();
    TestCache.enterMemoryMode();
    tmp = Directory.systemTemp.createTempSync('chip_place_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
  });
  tearDown(() async {
    api = savedApi;
    TestCache.exitMemoryMode();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> enqueue(WidgetTester tester, int n) => tester.runAsync(() async {
        for (var i = 0; i < n; i++) {
          await OfflineQueue.enqueueLocal({'n': i}, 'tok$i');
        }
      });

  Widget app(Widget home) => MaterialApp(
        theme: AppTheme.theme,
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      );

  Future<void> bigScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('group select: chip with count and send button', (tester) async {
    await bigScreen(tester);
    await enqueue(tester, 2);
    await tester.pumpWidget(
        app(const GroupSelectScreen(schoolCode: '1', schoolLabel: '1')));
    await settle(tester);
    final t = AppLocalizations.of(tester.element(find.byType(Scaffold).last))!;
    expect(find.text(t.pendingResultsChip(2)), findsOneWidget);
    expect(find.text(t.pendingResultsSendNow), findsOneWidget);
  });

  testWidgets('group select: nothing pending -> no chip', (tester) async {
    await bigScreen(tester);
    await tester.pumpWidget(
        app(const GroupSelectScreen(schoolCode: '1', schoolLabel: '1')));
    await settle(tester);
    final t = AppLocalizations.of(tester.element(find.byType(Scaffold).last))!;
    expect(find.text(t.pendingResultsSendNow), findsNothing);
  });

  testWidgets('student roster: chip shown', (tester) async {
    await bigScreen(tester);
    await enqueue(tester, 3);
    await tester.pumpWidget(app(const StudentEntryScreen(
      session: _session,
      preselectedGroup: {'id': 'g1', 'name': '5-A'},
    )));
    await settle(tester);
    final t = AppLocalizations.of(tester.element(find.byType(Scaffold).last))!;
    expect(find.text(t.pendingResultsChip(3)), findsOneWidget);
    expect(find.text(t.pendingResultsSendNow), findsOneWidget);
  });

  testWidgets('login: chip shown', (tester) async {
    await bigScreen(tester);
    addTearDown(ConnectivityService.instance.dispose);
    final prefs = await SharedPreferences.getInstance();
    await enqueue(tester, 1);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: app(const LoginScreen()),
    ));
    await settle(tester);
    final t = AppLocalizations.of(tester.element(find.byType(Scaffold).last))!;
    expect(find.text(t.pendingResultsChip(1)), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
