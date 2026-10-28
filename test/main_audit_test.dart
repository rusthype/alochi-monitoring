// Audit E-01 / E-02 / C5 / B7: kiosk shortcuts are dead during a test, the
// error widget never prints exception text, and the inactivity logout waits
// for any runner and clears the previous student's session.

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/diagnostics/active_test_gate.dart';
import 'package:alochi_monitoring/core/router/app_router.dart';
import 'package:alochi_monitoring/core/widgets/command_palette.dart';
import 'package:alochi_monitoring/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

class _TrackingApi extends MonitoringApi {
  var cleared = 0;
  @override
  void clearToken() {
    cleared++;
    super.clearToken();
  }
}

Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
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
  await tester.pump(const Duration(milliseconds: 500));
  return container;
}

Future<void> _ctrlK(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  tearDown(ActiveTestGate.resetForTest);

  group('E-02 ErrorWidget placeholder', () {
    final details =
        FlutterErrorDetails(exception: StateError('secret internal failure'));

    testWidgets('release: no text at all', (tester) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: buildErrorPlaceholder(details, debug: false)));
      expect(find.byType(Text), findsNothing);
      expect(find.textContaining('secret'), findsNothing);
      expect(find.textContaining('Xatolik'), findsNothing);
    });

    testWidgets('debug: details are for the developer', (tester) async {
      await tester.pumpWidget(buildErrorPlaceholder(details, debug: true));
      expect(find.textContaining('secret internal failure'), findsOneWidget);
    });
  });

  group('E-01 shortcuts during a test', () {
    testWidgets('Ctrl+K opens the palette only when no test is active',
        (tester) async {
      await _pumpApp(tester);

      ActiveTestGate.active.value = true;
      await _ctrlK(tester);
      expect(find.byType(CommandPalette), findsNothing);
      expect(kioskShortcutsBlocked(), isTrue);

      ActiveTestGate.active.value = false;
      expect(kioskShortcutsBlocked(), isFalse);
      await _ctrlK(tester);
      expect(find.byType(CommandPalette), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('C5 / B7 inactivity logout', () {
    testWidgets('does not fire while a runner holds the test gate',
        (tester) async {
      final saved = api;
      final fake = _TrackingApi();
      api = fake;
      addTearDown(() => api = saved);
      final container = await _pumpApp(tester);
      final router = container.read(goRouterProvider);
      router.go('/diagnostic_session_setup');
      await tester.pump(const Duration(milliseconds: 500));

      // LoginScreen.initState already clears the previous student session.
      fake.cleared = 0;
      final release = ActiveTestGate.enter();
      await tester.pump(const Duration(minutes: 31));
      await tester.pump();
      expect(router.routerDelegate.currentConfiguration.uri.toString(),
          '/diagnostic_session_setup');
      expect(fake.cleared, 0);

      // Test ends: the next idle period logs out AND clears the session.
      release();
      await tester.pump(const Duration(minutes: 31));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
      expect(fake.cleared, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
