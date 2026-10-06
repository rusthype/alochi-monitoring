import 'package:alochi_monitoring/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/app_harness.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: await appTestOverrides(),
        child: const AlochiMonitoringApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(AlochiMonitoringApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Unmount so screen timers are cancelled before the invariant check.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
