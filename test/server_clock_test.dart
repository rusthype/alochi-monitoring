// Time locks follow SERVER time: the offset is learned from the HTTP Date
// header of any successful API answer and persisted. A PC clock reset to 2000
// must not lock every scheduled test; a clock running ahead must not open one
// early.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/server_clock.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/session/runner_dispatch.dart';
import 'package:alochi_monitoring/features/session/test_session.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _serverNow = DateTime.utc(2026, 10, 29, 10, 0, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitoringApi savedApi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerClock.resetForTest();
    savedApi = api;
    TestCache.enterMemoryMode();
    TestCatalogService.resetKnownMissingForTest();
  });
  tearDown(() {
    api = savedApi;
    ServerClock.resetForTest();
    TestCache.exitMemoryMode();
  });

  test('without any observation it is the device clock', () {
    final dev = DateTime.utc(2026, 10, 29, 9, 0, 0);
    ServerClock.deviceNow = () => dev;
    expect(ServerClock.now(), dev);
    expect(ServerClock.isFuture(dev.add(const Duration(seconds: 1))), isTrue);
    expect(ServerClock.isFuture(dev.subtract(const Duration(seconds: 1))),
        isFalse);
  });

  test('device clock reset to 2000: a lock that already lifted stays open',
      () {
    ServerClock.deviceNow = () => DateTime.utc(2000, 1, 1);
    // Unlocked an hour ago by server time.
    final lockedUntil = _serverNow.subtract(const Duration(hours: 1));
    expect(lockedUntil.isAfter(ServerClock.deviceNow()), isTrue,
        reason: 'the raw device clock would call it locked');
    ServerClock.observe(HttpDate.format(_serverNow));
    expect(ServerClock.isFuture(lockedUntil), isFalse);
    expect(ServerClock.isFuture(_serverNow.add(const Duration(hours: 1))),
        isTrue);
  });

  test('device clock ahead: a lock that still holds is not opened early', () {
    ServerClock.deviceNow = () => _serverNow.add(const Duration(days: 3));
    final lockedUntil = _serverNow.add(const Duration(hours: 1));
    expect(lockedUntil.isAfter(ServerClock.deviceNow()), isFalse,
        reason: 'the raw device clock would call it open');
    ServerClock.observe(HttpDate.format(_serverNow));
    expect(ServerClock.isFuture(lockedUntil), isTrue);
    expect(ServerClock.until(lockedUntil), const Duration(hours: 1));
  });

  test('garbage Date headers are ignored', () {
    ServerClock.deviceNow = () => _serverNow;
    ServerClock.observe('not a date');
    ServerClock.observe('');
    ServerClock.observe(null);
    expect(ServerClock.offset, Duration.zero);
  });

  test('the offset survives a restart (persisted in prefs)', () async {
    ServerClock.deviceNow = () => DateTime.utc(2000, 1, 1);
    ServerClock.observe(HttpDate.format(_serverNow));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final learned = ServerClock.offset;
    expect(learned, isNot(Duration.zero));

    ServerClock.resetForTest(); // "restart"
    ServerClock.deviceNow = () => DateTime.utc(2000, 1, 1);
    expect(ServerClock.offset, Duration.zero);
    await ServerClock.ensureLoaded();
    expect(ServerClock.offset, learned);
    expect(ServerClock.now().year, 2026);
  });

  test('any successful API answer teaches the clock; a portal page does not',
      () async {
    ServerClock.deviceNow = () => DateTime.utc(2000, 1, 1);
    final a = MonitoringApi();
    await http.runWithClient(() => a.ping(), () => MockClient((_) async {
          return http.Response('{"status":"ok"}', 200, headers: {
            'content-type': 'application/json',
            'date': HttpDate.format(_serverNow),
          });
        }));
    expect(ServerClock.now().year, 2026);

    ServerClock.resetForTest();
    ServerClock.deviceNow = () => DateTime.utc(2000, 1, 1);
    await http.runWithClient(() => a.ping(), () => MockClient((_) async {
          return http.Response('<html>login</html>', 200, headers: {
            'content-type': 'text/html',
            'date': HttpDate.format(_serverNow),
          });
        }));
    expect(ServerClock.offset, Duration.zero);
  });

  group('launchRunner lock check', () {
    Future<void> pumpLaunch(WidgetTester tester, DateTime lockedUntil) async {
      // The catalog refresh is what remembers locked_until per test.
      api = _CatalogApi({
        'test_key': 'mon:lock',
        'title': 'T',
        'grade': 5,
        'version': 1,
        'locked_until': lockedUntil.toIso8601String(),
      });
      await tester.runAsync(() => testCatalogService.refresh());
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return const Scaffold(body: SizedBox());
        }),
      ));
      await tester.runAsync(() => launchRunner(
            ctx,
            session: const TestSession(
              testKey: 'mon:lock',
              title: 'T',
              runnerType: 'engine',
              schoolCode: '1',
              schoolLabel: '1',
              testGrade: 5,
            ),
            firstName: 'A',
            lastName: 'B',
            studentGrade: 5,
          ));
      await tester.pump();
    }

    AppLocalizations l10n(WidgetTester tester) =>
        AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    testWidgets('PC clock in 2000: an already lifted lock is NOT "locked"',
        (tester) async {
      ServerClock.deviceNow = () => DateTime.utc(2000, 1, 1);
      ServerClock.observe(HttpDate.format(_serverNow));
      await pumpLaunch(tester, _serverNow.subtract(const Duration(hours: 1)));
      expect(find.text(l10n(tester).testLocked), findsNothing);
      // Went on to the next step instead (test not downloaded here).
      expect(find.text(l10n(tester).testNotInCache), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('PC clock 3 days ahead: a still-held lock stays locked',
        (tester) async {
      ServerClock.deviceNow = () => _serverNow.add(const Duration(days: 3));
      ServerClock.observe(HttpDate.format(_serverNow));
      await pumpLaunch(tester, _serverNow.add(const Duration(hours: 1)));
      expect(find.text(l10n(tester).testLocked), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });
}

class _CatalogApi extends MonitoringApi {
  _CatalogApi(this.item);
  final Map<String, dynamic> item;
  @override
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
          {String? groupId,
          String? schoolCode,
          String? schoolId,
          String? authToken}) async =>
      [item];
}
