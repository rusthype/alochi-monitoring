import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/router/app_router.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/session/session_providers.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/app_harness.dart';

// Regression: a general ("Umumiy") test has no schoolButtons, so
// SessionSetupScreen stores the TestSession in currentSessionProvider and
// does pushReplacement('/student_entry') WITHOUT extra. The route builder read
// extra['session'] -> null into a non-null TestSession param ->
// "type 'Null' is not a subtype of type 'TestSession'" (global error screen).
void main() {
  Future<(ProviderContainer, GoRouter)> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: await appTestOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const AlochiMonitoringApp(),
    ));
    await tester.pump();
    return (container, container.read(goRouterProvider));
  }

  Future<void> settle(WidgetTester tester) async {
    // Post-frame callback in SessionSetupScreen, then the route transition.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets(
      'general test (no schoolButtons): session_setup reaches '
      'StudentEntryScreen without a Null->TestSession crash', (tester) async {
    final (container, router) = await boot(tester);
    container.read(selectedCatalogEntryProvider.notifier).state =
        const CatalogEntry(
      testKey: 'general_1',
      title: 'General',
      grade: 5,
      version: 1,
      status: CatalogStatus.cachedOnly,
    );

    router.push('/session_setup', extra: {'testKey': 'general_1'});
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(StudentEntryScreen), findsOneWidget);
    expect(
        tester
            .widget<StudentEntryScreen>(find.byType(StudentEntryScreen))
            .session
            .testKey,
        'general_1');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bare /student_entry without extra bounce to /',
      (tester) async {
    final (_, router) = await boot(tester);
    String loc() => router.routerDelegate.currentConfiguration.uri.toString();

    for (final path in ['/student_entry', '/test', '/result']) {
      router.go(path);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: path);
      expect(loc(), '/', reason: path);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // The login "Schools" sheet lists the open pack's school-less "Golden" test;
  // tapping it used to white-screen. It must reach the roster picker, fed by
  // the pack's own groups.
  testWidgets('open golden pack: tapping its general test reaches the roster',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    const dir = 'test/fixtures/offline';
    final tmp = Directory.systemTemp.createTempSync('router_pack_');
    final savedKeys = OfflineKeys.current;
    final savedApi = api;
    addTearDown(() async {
      OfflinePackSession.close();
      api = savedApi;
      OfflineKeys.current = savedKeys;
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });
    OfflineKeys.current = OfflineKeys(
      signingPem: File('$dir/test_signing_public.pem').readAsStringSync(),
      resultsPem: File('$dir/test_results_public.pem').readAsStringSync(),
    );
    await tester.runAsync(() async {
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      final media = Directory(p.join(tmp.path, 'media'))..createSync();
      final pack = await PackLoader(keys: OfflineKeys.current).open(
          File('$dir/golden.alochipack').readAsBytesSync(), '12345678',
          mediaDir: media);
      await OfflinePackSession.open(pack, media);
    });

    final (container, router) = await boot(tester);
    container.read(selectedCatalogEntryProvider.notifier).state =
        const CatalogEntry(
      testKey: 'golden_test_1',
      title: 'Golden',
      grade: 5,
      version: 1,
      status: CatalogStatus.notDownloaded,
    );
    router.push('/session_setup', extra: {'testKey': 'golden_test_1'});
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(StudentEntryScreen), findsOneWidget);
    expect(await tester.runAsync(() => api.fetchGroups('')), isNotEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
