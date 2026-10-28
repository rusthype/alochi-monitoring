// Monitoring roster: stays on the same group/test after a launch returns,
// "done" badge union (backend flag + local record), and the test-level
// "images on disk" badge (loading / ready / error + retry).
import 'dart:async';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/cache/test_image_store.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/roster_done_store.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/features/session/test_session.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testKey = 'mon:status';
const _img = 'https://img.test/q1.png';

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
  final List<String?> testKeys = [];
  @override
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId,
      {String? testKey}) async {
    testKeys.add(testKey);
    return students;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitoringApi savedApi;
  late Directory dir;

  setUp(() {
    savedApi = api;
    SharedPreferences.setMockInitialValues({});
    TestCatalogService.resetKnownMissingForTest();
    TestCache.enterMemoryMode();
    dir = Directory.systemTemp.createTempSync('roster_status_');
  });

  tearDown(() {
    api = savedApi;
    TestCache.exitMemoryMode();
    dir.deleteSync(recursive: true);
  });

  Future<void> pumpRoster(WidgetTester tester,
      {TestCatalogService? catalog}) async {
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
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).last))!;

  testWidgets('done badge = backend flag + local record; missing field ok',
      (tester) async {
    final fake = _RosterApi([
      {'id': 's1', 'student_code': 'S-1', 'name': 'Valiyev Ali', 'done': true},
      {'id': 's2', 'student_code': 'S-2', 'name': 'Karimov Bobur'},
      {'id': 's3', 'student_code': 'S-3', 'name': 'Sobirov Sher'}, // no `done`
    ]);
    api = fake;
    await tester.runAsync(() => RosterDoneStore.add(_testKey, 'S-2'));
    await pumpRoster(tester);

    expect(fake.testKeys, [_testKey]);
    expect(find.text(l10n(tester).rosterDoneBadge), findsNWidgets(2));
    // No cache row -> no readiness badge at all.
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('stays on the roster after the launch returns, reloads students',
      (tester) async {
    final fake = _RosterApi([
      {'id': 's1', 'student_code': 'S-1', 'name': 'Valiyev Ali'},
    ]);
    api = fake;
    await pumpRoster(tester);
    final t = l10n(tester);

    await tester.tap(find.textContaining('Ali'));
    await tester.pump();
    await tester.tap(find.text(t.startTest));
    await tester.pump();
    // Nothing cached -> launchRunner toasts and returns (the old code popped).
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(StudentEntryScreen), findsOneWidget);
    expect(find.textContaining('Ali'), findsOneWidget);
    expect(fake.testKeys.length, 2); // roster reloaded
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  group('test images badge', () {
    late bool fail;
    late Completer<void> gate;
    late TestImageStore store;
    late TestCatalogService svc;
    late Map<String, dynamic> data;

    setUp(() async {
      fail = false;
      gate = Completer<void>()..complete();
      store = TestImageStore(
        root: Directory('${dir.path}/imgs'),
        client: MockClient((req) async {
          await gate.future;
          return fail
              ? http.Response('x', 500)
              : http.Response.bytes([1, 2, 3], 200);
        }),
        timeout: const Duration(seconds: 2),
      );
      await store.init();
      svc = TestCatalogService(_RosterApi([]),
          store: store,
          retryDelay: Duration.zero,
          bgJitter: () => Duration.zero,
          bgBackoff: const [Duration.zero],
          bgYield: const Duration(milliseconds: 5));
      data = {
        'title': 'T',
        'variants': {
          '1': {
            'Math': [
              {'image_url': _img}
            ]
          }
        },
      };
      await TestCache.upsert(_testKey, 'T', 5, 1, '{"title":"T","variants":'
          '{"1":{"Math":[{"image_url":"$_img"}]}}}');
      api = _RosterApi([
        {'id': 's1', 'student_code': 'S-1', 'name': 'Valiyev Ali'},
      ]);
    });

    // Real IO (files) needs real time, fake timers need pumps: alternate.
    Future<void> settleIo(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('ready when every image is on disk', (tester) async {
      await tester.runAsync(() => svc.ensureUrls([_img]));
      await pumpRoster(tester, catalog: svc);
      await settleIo(tester);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('loading while the background job runs, then ready',
        (tester) async {
      gate = Completer<void>();
      await tester.runAsync(() async {
        unawaited(svc.backgroundPrefetch(_testKey, data));
      });
      await pumpRoster(tester, catalog: svc);
      await settleIo(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gate.complete();
      await settleIo(tester);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('error after a failed pass; tap retries and turns ready',
        (tester) async {
      fail = true;
      await tester.runAsync(() => svc.backgroundPrefetch(_testKey, data));
      await pumpRoster(tester, catalog: svc);
      await settleIo(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      fail = false;
      await tester.tap(find.byIcon(Icons.error_outline));
      await tester.pump();
      await settleIo(tester);
      await settleIo(tester);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });
}
