import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/core/widgets/inactivity_wrapper.dart';

// Regression: InactivityWrapper sits ABOVE MaterialApp.router, so it must use
// an explicitly injected GoRouter (GoRouter.of(context) threw in prod).
void main() {
  const timeout = Duration(milliseconds: 50);

  // CredentialCache.clear() hits flutter_secure_storage's platform channel;
  // stub it so the awaited call resolves inside the test's fake clock.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => null);
  });

  GoRouter makeRouter() => GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('root')),
        GoRoute(path: '/other', builder: (_, __) => const Text('other')),
      ]);

  Widget app(GoRouter router) => InactivityWrapper(
        router: router,
        timeout: timeout,
        child: MaterialApp.router(routerConfig: router),
      );

  String loc(GoRouter r) =>
      r.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('returns to / after timeout without throwing', (tester) async {
    final router = makeRouter();
    await tester.pumpWidget(app(router));
    router.go('/other');
    await tester.pump();
    // Go past the timeout, then let CredentialCache.clear() settle.
    await tester.pump(timeout + const Duration(milliseconds: 10));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(loc(router), '/');
  });

  testWidgets('pointer down resets the timer', (tester) async {
    final router = makeRouter();
    await tester.pumpWidget(app(router));
    router.go('/other');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final g = await tester.startGesture(const Offset(5, 5));
    await g.up();
    await tester.pump(const Duration(milliseconds: 30)); // 60ms total > timeout
    expect(loc(router), '/other');
    await tester.pump(timeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(loc(router), '/');
    expect(tester.takeException(), isNull);
  });
}
