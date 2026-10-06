import 'package:alochi_monitoring/core/router/app_router.dart';
import 'package:alochi_monitoring/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

// Regression for the kiosk auto-logout crash: InactivityWrapper sits above
// MaterialApp.router and used GoRouter.of(context) -> "No GoRouter found in
// context" after 30 min. Drives the REAL app + REAL router through the
// default timeout.
void main() {
  testWidgets('real app returns to / after 30 min idle without throwing',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: await appTestOverrides());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AlochiMonitoringApp(),
      ),
    );
    await tester.pump();

    final router = container.read(goRouterProvider);
    String loc() => router.routerDelegate.currentConfiguration.uri.toString();

    // Pure-UI route reachable without login.
    router.go('/diagnostic_session_setup');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(loc(), '/diagnostic_session_setup');
    expect(tester.takeException(), isNull);

    // Past InactivityWrapper's default 30-minute timeout.
    await tester.pump(const Duration(minutes: 31));
    await tester.pump(); // CredentialCache.clear() await
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(loc(), '/');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
