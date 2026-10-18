// Regression: after using an offline pack the login screen kept saying
// "offline" even with working internet, because the connectivity probe called
// the global `api`, which the open pack session had swapped for
// OfflinePackageApi (ping() == false). The probe must hit the REAL client, and
// the login screen must show a banner with a one-tap exit while a pack is open.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_package_api.dart';
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

/// The "real" server: reachable.
class _FakeOnlineApi extends MonitoringApi {
  @override
  Future<bool> ping() async => true;

  @override
  Future<bool> pingHealth(
          {Duration timeout = const Duration(seconds: 2)}) async =>
      true;
}

void main() {
  const dir = 'test/fixtures/offline';
  late Directory tmp;
  late MonitoringApi savedApi;
  late OfflineKeys savedKeys;
  late _FakeOnlineApi online;

  setUp(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('login_banner_');
    savedApi = api;
    savedKeys = OfflineKeys.current;
    online = _FakeOnlineApi();
    api = online;
    OfflineKeys.current = OfflineKeys(
      signingPem: File('$dir/test_signing_public.pem').readAsStringSync(),
      resultsPem: File('$dir/test_results_public.pem').readAsStringSync(),
    );
  });

  tearDown(() async {
    exitOfflineMode();
    api = savedApi;
    OfflineKeys.current = savedKeys;
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<void> openGoldenPack(WidgetTester tester) => tester.runAsync(() async {
        await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
        final media = Directory(p.join(tmp.path, 'media'))..createSync();
        final pack = await PackLoader(keys: OfflineKeys.current).open(
            File('$dir/golden.alochipack').readAsBytesSync(), '12345678',
            mediaDir: media);
        await OfflinePackSession.open(pack, media);
      });

  Future<void> pumpLogin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    addTearDown(ConnectivityService.instance.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.theme,
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LoginScreen(),
      ),
    ));
    // First probe: fake ping resolves immediately.
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
      'pack open + real server reachable: chip online, banner offers exit',
      (tester) async {
    await openGoldenPack(tester);
    expect(api, isA<OfflinePackageApi>());
    await pumpLogin(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(LoginScreen)))!;

    expect(find.text(l10n.serverConnected), findsOneWidget);
    expect(find.text(l10n.offlineMode), findsNothing);
    expect(
        find.byKey(const ValueKey('offline-session-banner')), findsOneWidget);
    expect(find.text(l10n.offlineSessionBannerOnlineHint), findsOneWidget);
    expect(find.text(l10n.usbExitMode), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'exit action restores the real api and the login screen is normal',
      (tester) async {
    await openGoldenPack(tester);
    await pumpLogin(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(LoginScreen)))!;

    await tester.tap(find.byKey(const ValueKey('offline-session-banner-exit')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(OfflinePackSession.isActive, isFalse);
    expect(isOfflineModeOpen, isFalse);
    expect(identical(api, online), isTrue);
    expect(await api.ping(), isTrue);
    expect(find.byKey(const ValueKey('offline-session-banner')), findsNothing);
    expect(find.text(l10n.serverConnected), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('no session open: no banner', (tester) async {
    await pumpLogin(tester);
    expect(find.byKey(const ValueKey('offline-session-banner')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
