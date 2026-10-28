// A locked test card re-evaluates its lock by SERVER time and opens by itself
// when locked_until passes - no re-entry of the screen needed.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/server_clock.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/session/group_select_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _Api extends MonitoringApi {
  _Api(this.lockedUntil);
  final DateTime lockedUntil;
  @override
  Future<List<Map<String, dynamic>>> fetchGroups(String schoolCode,
          {String? schoolId}) async =>
      [
        {'id': 'g1', 'name': '5-A'}
      ];
  @override
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
          {String? groupId,
          String? schoolCode,
          String? schoolId,
          String? authToken}) async =>
      [
        {
          'test_key': 'mon:timer',
          'title': 'Timed test',
          'grade': 5,
          'version': 1,
          'locked_until': lockedUntil.toUtc().toIso8601String(),
        }
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitoringApi savedApi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerClock.resetForTest();
    savedApi = api;
    TestCatalogService.resetKnownMissingForTest();
    TestCache.enterMemoryMode();
  });
  tearDown(() {
    api = savedApi;
    ServerClock.resetForTest();
    TestCache.exitMemoryMode();
  });

  testWidgets('the lock lifts by itself at locked_until (server time)',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The PC clock is in 2000; the server says it is 2026.
    final serverStart = DateTime.utc(2026, 10, 29, 10, 0, 0);
    var elapsed = Duration.zero;
    final deviceStart = DateTime.utc(2000, 1, 1);
    ServerClock.deviceNow = () => deviceStart.add(elapsed);
    ServerClock.observe(HttpDate.format(serverStart));

    api = _Api(serverStart.add(const Duration(seconds: 90)));
    await tester.runAsync(
        () => TestCache.upsert('mon:timer', 'Timed test', 5, 1, _cachedTest));

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupSelectScreen(schoolCode: '1', schoolLabel: '1'),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('5-A'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    final t = AppLocalizations.of(tester.element(find.byType(Scaffold).last))!;
    expect(find.text(t.stillLocked), findsOneWidget);

    // 100 s pass (server time moves with the device clock).
    elapsed = const Duration(seconds: 100);
    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 61));
    expect(find.text(t.stillLocked), findsNothing);
    expect(find.text('Timed test'), findsOneWidget);
  });
}
