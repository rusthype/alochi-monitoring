// An open USB pack decides the login tab: a diagnostic-only pack lands on
// "Диагностика" (monitoring tab disabled), a monitoring-only pack stays on the
// monitoring login (diagnostic tab disabled), no pack leaves both usable.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/features/auth/login_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeOnlineApi extends MonitoringApi {
  @override
  Future<bool> ping() async => true;

  @override
  Future<bool> pingHealth({
    Duration timeout = const Duration(seconds: 2),
  }) async => true;
}

const _monitoringTab = ValueKey('login-tab-student');
const _diagnosticTab = ValueKey('login-tab-diagnostic');

void main() {
  late Directory tmp;
  late MonitoringApi savedApi;

  setUp(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('login_pack_tab_');
    savedApi = api;
    api = _FakeOnlineApi();
  });

  tearDown(() async {
    OfflinePackSession.close();
    api = savedApi;
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<void> openPack(WidgetTester tester, List<String> testTypes) =>
      tester.runAsync(() async {
        await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
        await OfflinePackSession.open(
          LoadedPack(
            manifest: PackManifest(
              formatVersion: 1,
              packUuid: '00000000-0000-4000-8000-0000000000a1',
              schoolId: '00000000-0000-4000-8000-0000000000b2',
              schoolCode: '999',
              createdAt: DateTime.utc(2026, 1, 1),
              expiresAt: DateTime.utc(2099, 1, 1),
              kdfIter: 1,
              kdfSalt: Uint8List(16),
              files: const {},
            ),
            tests: [
              for (var i = 0; i < testTypes.length; i++)
                {'key': 't$i', 'type': testTypes[i]},
            ],
            groups: const [],
            students: const [],
            chainKey: Uint8List(32),
          ),
          Directory(p.join(tmp.path, 'media')),
        );
      });

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    addTearDown(ConnectivityService.instance.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.theme,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  bool enabled(WidgetTester tester, Key key) =>
      tester.widget<InkWell>(find.byKey(key)).onTap != null;

  testWidgets(
    'diagnostic-only pack: diagnostic panel, monitoring tab disabled',
    (tester) async {
      await openPack(tester, ['diagnostic']);
      await pumpLogin(tester);
      expect(find.byKey(const ValueKey('diagnostic-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('login-form')), findsNothing);
      expect(enabled(tester, _monitoringTab), isFalse);
      expect(enabled(tester, _diagnosticTab), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('monitoring-only pack: login form, diagnostic tab disabled', (
    tester,
  ) async {
    await openPack(tester, ['test', 'test']);
    await pumpLogin(tester);
    expect(find.byKey(const ValueKey('login-form')), findsOneWidget);
    expect(find.byKey(const ValueKey('diagnostic-panel')), findsNothing);
    expect(enabled(tester, _monitoringTab), isTrue);
    expect(enabled(tester, _diagnosticTab), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('no pack: both tabs enabled and switchable', (tester) async {
    await pumpLogin(tester);
    expect(find.byKey(const ValueKey('login-form')), findsOneWidget);
    expect(enabled(tester, _monitoringTab), isTrue);
    expect(enabled(tester, _diagnosticTab), isTrue);
    await tester.tap(find.byKey(_diagnosticTab));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('diagnostic-panel')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pack opened while login is shown switches the tab', (
    tester,
  ) async {
    await pumpLogin(tester);
    expect(find.byKey(const ValueKey('login-form')), findsOneWidget);
    await openPack(tester, ['diagnostic']);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('diagnostic-panel')), findsOneWidget);
    expect(enabled(tester, _monitoringTab), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
