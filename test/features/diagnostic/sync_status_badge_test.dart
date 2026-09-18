import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/core/sync/sync_service.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/sync_status_badge.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('uz'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('pending > 0 shows the offline icon with a count badge',
      (tester) async {
    await tester.pumpWidget(_wrap(SyncStatusBadge(
      pendingCountOverride: () async => 3,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });

  testWidgets('pending == 0 shows the synced icon', (tester) async {
    await tester.pumpWidget(_wrap(SyncStatusBadge(
      pendingCountOverride: () async => 0,
    )));
    await tester.pump();

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
  });

  testWidgets('flushing shows a spinner regardless of pending count',
      (tester) async {
    SyncService.instance.flushing.value = true;
    addTearDown(() => SyncService.instance.flushing.value = false);

    await tester.pumpWidget(_wrap(SyncStatusBadge(
      pendingCountOverride: () async => 5,
    )));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });

  testWidgets('tapping the badge calls flushNowOverride', (tester) async {
    var flushed = false;
    await tester.pumpWidget(_wrap(SyncStatusBadge(
      pendingCountOverride: () async => 0,
      flushNowOverride: () async => flushed = true,
    )));
    await tester.pump();

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(flushed, isTrue);
  });
}
