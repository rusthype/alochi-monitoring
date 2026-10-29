// The teacher-visible "N natija yuborilmagan" chip: hidden when nothing is
// pending, otherwise count (+ oldest age) and a "Hozir yuborish" button that
// flushes now, shows progress and reports the outcome in a toast.
import 'dart:async';
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/sync/sync_service.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/widgets/pending_results_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Widget _wrap(Widget chip) => MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: chip)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

  testWidgets('hidden when nothing is pending', (tester) async {
    await tester.pumpWidget(_wrap(PendingResultsChip(
      pendingCountOverride: () async => 0,
      oldestAgeOverride: () async => null,
    )));
    await settle(tester);
    expect(find.byType(TextButton), findsNothing);
    expect(find.textContaining('natija'), findsNothing);
  });

  testWidgets('shows count, oldest age and the send button', (tester) async {
    await tester.pumpWidget(_wrap(PendingResultsChip(
      pendingCountOverride: () async => 3,
      oldestAgeOverride: () async => const Duration(hours: 2, minutes: 5),
    )));
    await settle(tester);
    final t = l10n(tester);
    expect(find.text(t.pendingResultsChip(3)), findsOneWidget);
    expect(find.text(t.pendingResultsOldestHours(2)), findsOneWidget);
    expect(find.text(t.pendingResultsSendNow), findsOneWidget);
    expect(t.pendingResultsChip(3), '3 natija yuborilmagan');
  });

  testWidgets(
      'send now: progress while flushing, success toast with the '
      'number that left the queue', (tester) async {
    var pending = 3;
    final gate = Completer<SyncFlushOutcome>();
    await tester.pumpWidget(_wrap(PendingResultsChip(
      pendingCountOverride: () async => pending,
      oldestAgeOverride: () async => const Duration(minutes: 7),
      flushNowOverride: () {
        return gate.future;
      },
    )));
    await settle(tester);
    final t = l10n(tester);

    await tester.tap(find.text(t.pendingResultsSendNow));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(t.syncStatusSyncing), findsOneWidget);
    expect(find.text(t.pendingResultsSendNow), findsNothing);

    pending = 1; // two results reached the server
    gate.complete(SyncFlushOutcome.success);
    await settle(tester);
    expect(find.text(t.pendingResultsSentToast(2)), findsOneWidget);
    expect(find.text(t.pendingResultsChip(1)), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('no network: the toast says results are safe on the device',
      (tester) async {
    await tester.pumpWidget(_wrap(PendingResultsChip(
      pendingCountOverride: () async => 2,
      oldestAgeOverride: () async => null,
      flushNowOverride: () async => SyncFlushOutcome.noNetwork,
    )));
    await settle(tester);
    final t = l10n(tester);
    await tester.tap(find.text(t.pendingResultsSendNow));
    await settle(tester);
    expect(find.text(t.pendingResultsNoNetworkToast), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('server refused (nothing left the queue): failure toast',
      (tester) async {
    await tester.pumpWidget(_wrap(PendingResultsChip(
      pendingCountOverride: () async => 2,
      oldestAgeOverride: () async => null,
      flushNowOverride: () async => SyncFlushOutcome.success,
    )));
    await settle(tester);
    final t = l10n(tester);
    await tester.tap(find.text(t.pendingResultsSendNow));
    await settle(tester);
    expect(find.text(t.pendingResultsFailedToast), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a replaced corrupt queue file raises one teacher notice',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = Directory.systemTemp.createTempSync('chip_corrupt_');
    addTearDown(() async {
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });
    final path = p.join(tmp.path, 'monitoring_queue.db');
    File(path).writeAsBytesSync(List<int>.generate(2048, (i) => (i * 5) % 251));
    await tester.runAsync(() => OfflineQueue.openAtPath(path));

    await tester.pumpWidget(_wrap(PendingResultsChip(
      pendingCountOverride: () async => 0,
      oldestAgeOverride: () async => null,
    )));
    await settle(tester);
    final t = l10n(tester);
    expect(find.text(t.queueDbRecoveredToast), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(OfflineQueue.takeRecoveryNotice(), isFalse, reason: 'consumed');
  });

  testWidgets(
      'follows the real queue without any timer: appears on enqueue, '
      'disappears when the rows are gone', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = Directory.systemTemp.createTempSync('chip_events_');
    addTearDown(() async {
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });
    await tester
        .runAsync(() => OfflineQueue.openAtPath(p.join(tmp.path, 'q.db')));

    await tester.pumpWidget(_wrap(const PendingResultsChip()));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    final t = l10n(tester);
    expect(find.text(t.pendingResultsSendNow), findsNothing);

    await tester.runAsync(() => OfflineQueue.enqueueLocal({'a': 1}, 'x'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
    expect(find.text(t.pendingResultsChip(1)), findsOneWidget);

    await tester.runAsync(() async {
      await OfflineQueue.flushLocal((_, __) async => {'synced': true});
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    expect(find.text(t.pendingResultsSendNow), findsNothing);
  });

  group('OfflineQueue.oldestPendingAge', () {
    late Directory tmp;
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('chip_age_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    });
    tearDown(() async {
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    test('null when empty, else the age of the oldest row of either queue',
        () async {
      expect(await OfflineQueue.oldestPendingAge(), isNull);
      await OfflineQueue.enqueueLocal({'a': 1}, 'a');
      await OfflineQueue.enqueueLocal({'a': 2}, 'b');
      final d = await OfflineQueue.db;
      await d.update('local_queue', {'created': 1000000},
          where: 'token = ?', whereArgs: ['a']);
      await d.update('local_queue', {'created': 2000000},
          where: 'token = ?', whereArgs: ['b']);
      final age = await OfflineQueue.oldestPendingAge(nowMs: 4000000);
      expect(age, const Duration(milliseconds: 3000000));
    });
  });

  group('rejected-only banner', () {
    Widget chip(int pending, int rejected) => _wrap(PendingResultsChip(
          pendingCountOverride: () async => pending,
          oldestAgeOverride: () async => null,
          rejectedCountOverride: () async => rejected,
        ));

    testWidgets('auto-hides after ~10s when only rejected results remain',
        (tester) async {
      await tester.pumpWidget(chip(0, 2));
      await settle(tester);
      final t = l10n(tester);
      expect(find.text(t.pendingResultsRejected(2)), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(find.text(t.pendingResultsRejected(2)), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text(t.pendingResultsRejected(2)), findsNothing);
      expect(find.text(t.pendingResultsSendNow), findsNothing);
    });

    testWidgets('stays pinned while results are unsent', (tester) async {
      await tester.pumpWidget(chip(3, 1));
      await settle(tester);
      final t = l10n(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text(t.pendingResultsChip(3)), findsOneWidget);
      expect(find.text(t.pendingResultsRejected(1)), findsOneWidget);
    });

    testWidgets('a higher rejected count re-shows it once', (tester) async {
      var rejected = 1;
      await tester.pumpWidget(_wrap(PendingResultsChip(
        pendingCountOverride: () async => 0,
        oldestAgeOverride: () async => null,
        rejectedCountOverride: () async => rejected,
      )));
      await settle(tester);
      final t = l10n(tester);
      await tester.pump(const Duration(seconds: 11));
      expect(find.text(t.pendingResultsRejected(1)), findsNothing);

      rejected = 2;
      OfflineQueue.changes.value++; // chip re-reads on queue changes
      await settle(tester);
      expect(find.text(t.pendingResultsRejected(2)), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
      expect(find.text(t.pendingResultsRejected(2)), findsNothing);

      OfflineQueue.changes.value++; // unrelated rebuild: no re-pop
      await settle(tester);
      expect(find.text(t.pendingResultsRejected(2)), findsNothing);
    });
  });
}
