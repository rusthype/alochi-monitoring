// The login screen's sync chip also resends held (rejected) and pending
// results, like PendingResultsChip's "send now".
import 'dart:convert';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/sync/sync_service.dart';
import 'package:alochi_monitoring/features/local_test/sync_images_button.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget w) => MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: w)),
      );

  setUp(() {
    // No images to download: questions.json is served as empty.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final bytes = utf8.encode('{}');
      return ByteData.sublistView(Uint8List.fromList(bytes));
    });
    OfflineQueue.pending.value = (count: 0, oldest: null);
    OfflineQueue.rejected.value = 0;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    OfflineQueue.pending.value = (count: 0, oldest: null);
    OfflineQueue.rejected.value = 0;
  });

  Future<void> press(WidgetTester tester) async {
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('rejected results: requeue + flush run, failure toast shown',
      (tester) async {
    OfflineQueue.rejected.value = 2;
    var requeued = 0, flushed = 0;
    await tester.pumpWidget(wrap(SyncImagesButton(
      requeueOverride: () async => ++requeued,
      flushOverride: () async {
        flushed++;
        return SyncFlushOutcome.noNetwork;
      },
    )));
    await press(tester);
    expect(requeued, 1);
    expect(flushed, 1);
    final t = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(find.text(t.pendingResultsNoNetworkToast), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('pending results alone are flushed too', (tester) async {
    OfflineQueue.pending.value = (count: 3, oldest: null);
    var flushed = 0;
    await tester.pumpWidget(wrap(SyncImagesButton(
      requeueOverride: () async => 0,
      flushOverride: () async {
        flushed++;
        OfflineQueue.pending.value = (count: 1, oldest: null);
        return SyncFlushOutcome.success;
      },
    )));
    await press(tester);
    expect(flushed, 1);
    final t = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(find.text(t.pendingResultsSentToast(2)), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('nothing held or pending: no resend', (tester) async {
    var flushed = 0;
    await tester.pumpWidget(wrap(SyncImagesButton(
      requeueOverride: () async => 0,
      flushOverride: () async {
        flushed++;
        return SyncFlushOutcome.success;
      },
    )));
    await press(tester);
    expect(flushed, 0);
  });
}
