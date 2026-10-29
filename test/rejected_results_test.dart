// A 409 that REJECTS a result (max_attempts_exceeded, unknown body) must never
// be acked or deleted silently: the row moves to the terminal
// `rejected_results` table, is never retried or purged, shows in the teacher
// chip, and can be re-queued by the teacher. A 409 that says "already stored"
// stays an ack.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/models/models.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/widgets/pending_results_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _result = TestResult(
  packageId: 'pkg',
  variant: 1,
  mathScore: 1,
  engScore: 2,
  totalPct: 50,
  answers: {'1': 'a'},
  deviceId: 'dev',
);

http.Response _conflict(Map<String, dynamic> body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), 409,
    headers: {'content-type': 'application/json'});

Future<T> _with<T>(http.Response r, Future<T> Function() body) =>
    http.runWithClient(body, () => MockClient((_) async => r));

const _maxAttempts = {
  'error': 'max_attempts_exceeded',
  'detail': 'Bu test uchun urinishlar soni tugagan.',
  'attempts_used': 1,
  'max_attempts': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final a = MonitoringApi();

  group('API verdicts', () {
    test('/results/ 409 already_submitted is an ack', () async {
      final r = await _with(
          _conflict({'status': 'already_submitted', 'result_id': 'r1'}),
          () => a.submitResultFull(_result));
      expect(r['synced'], true);
      expect(r['rejected'], isNull);
    });
    test('/results/ 409 max_attempts_exceeded is a rejection', () async {
      final r = await _with(
          _conflict(_maxAttempts), () => a.submitResultFull(_result));
      expect(r['synced'], false);
      expect(r['rejected'], true);
      expect(r['reject_reason'], 'max_attempts_exceeded');
    });
    test('/results/ 409 with an unknown body is a rejection, not an ack',
        () async {
      final r = await _with(
          _conflict({'detail': 'nope'}), () => a.submitResultFull(_result));
      expect(r['synced'], false);
      expect(r['rejected'], true);
    });
    test('/result/ 409: duplicate is synced, max_attempts is rejected',
        () async {
      var r = await _with(_conflict({'ok': true, 'id': 'x', 'duplicate': true}),
          () => a.submitLocalResultFull({'x': 1}, 't'));
      expect(r['synced'], true);
      r = await _with(
          _conflict(_maxAttempts), () => a.submitLocalResultFull({'x': 1}, 't'));
      expect(r['synced'], false);
      expect(r['rejected'], true);
      expect(r['reject_reason'], 'max_attempts_exceeded');
    });
    test('a captive-portal HTML 409 stays retryable', () async {
      final r = await _with(
          http.Response('<html>login</html>', 409,
              headers: {'content-type': 'text/html'}),
          () => a.submitLocalResultFull({'x': 1}, 't'));
      expect(r['rejected'], isNull);
      expect(r['permanent'], false);
    });
  });

  group('OfflineQueue', () {
    late Directory tmp;
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('rejected_q_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    });
    tearDown(() async {
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    Future<Map<String, dynamic>> rejectedReply(
            TestResult r, String t) async =>
        {'synced': false, 'permanent': true, 'rejected': true,
         'reject_reason': 'max_attempts_exceeded'};

    test('a rejected result is held, not deleted, not retried, not purged',
        () async {
      await OfflineQueue.enqueue(_result, token: 't1');
      await OfflineQueue.enqueueLocal({'student_id': 's'}, 't2');
      var calls = 0;
      await OfflineQueue.flush((r, t) async {
        calls++;
        return rejectedReply(r, t);
      });
      await OfflineQueue.flushLocal((m, t) async {
        calls++;
        return rejectedReply(_result, t);
      });
      expect(calls, 2);
      expect(await OfflineQueue.totalPendingCount(), 0);
      expect(await OfflineQueue.rejectedCount(), 2);

      // No more auto-retries and the purge leaves them alone.
      await OfflineQueue.flush((r, t) async {
        calls++;
        return {'synced': true};
      });
      await OfflineQueue.flushLocal((m, t) async {
        calls++;
        return {'synced': true};
      });
      await OfflineQueue.purgeStale(
          nowMs: DateTime.now().millisecondsSinceEpoch + 4000 * 86400000);
      expect(calls, 2);
      expect(await OfflineQueue.rejectedCount(), 2);
      await OfflineQueue.refreshPending();
      expect(OfflineQueue.rejected.value, 2);
    });

    test('requeueRejected gives the same token another submit', () async {
      await OfflineQueue.enqueue(_result, token: 't1');
      await OfflineQueue.flush(rejectedReply);
      expect(await OfflineQueue.requeueRejected(), 1);
      expect(await OfflineQueue.rejectedCount(), 0);
      String? seen;
      final n = await OfflineQueue.flush((r, t) async {
        seen = t;
        return {'synced': true};
      });
      expect((n, seen), (1, 't1'));
    });

    test('a real 400 / 422 from the API is held, re-queued, and held again',
        () async {
      await OfflineQueue.enqueue(_result, token: 't1');
      await OfflineQueue.enqueueLocal({'student_id': 's'}, 't2');
      var online = 0, local = 0;
      final bad = http.Response.bytes(
          utf8.encode(jsonEncode({'error': 'invalid_payload'})), 400,
          headers: {'content-type': 'application/json'});
      Future<void> flushBoth() async {
        await http.runWithClient(() async {
          await OfflineQueue.flush((r, t) async {
            online++;
            return a.submitResultFull(r, idempotencyToken: t);
          });
          await OfflineQueue.flushLocal((m, t) async {
            local++;
            return a.submitLocalResultFull(m, t);
          });
        }, () => MockClient((_) async => bad));
      }

      await flushBoth();
      expect(await OfflineQueue.totalPendingCount(), 0);
      expect(await OfflineQueue.rejectedCount(), 2);

      // "Hozir yuborish": re-queue, then the server says 400 again. One
      // submit per row per flush - never a loop - and back in rejected.
      expect(await OfflineQueue.requeueRejected(), 2);
      await flushBoth();
      expect((online, local), (2, 2));
      expect(await OfflineQueue.totalPendingCount(), 0);
      expect(await OfflineQueue.rejectedCount(), 2);
    });

    test('a non-result permanent reply (no rejected flag) is still dropped',
        () async {
      await OfflineQueue.enqueueLocal({'_offlineKind': 'question_report'}, 'q');
      await OfflineQueue.flushLocal(
          (m, t) async => {'synced': false, 'permanent': true});
      expect(await OfflineQueue.totalPendingCount(), 0);
      expect(await OfflineQueue.rejectedCount(), 0);
    });

    test('opening a pre-change queue file keeps its rows (safe migration)',
        () async {
      await OfflineQueue.resetForTest();
      final path = p.join(tmp.path, 'old.db');
      final old = await openDatabase(path, version: 9);
      await old.execute('CREATE TABLE queue (id INTEGER PRIMARY KEY '
          'AUTOINCREMENT, payload TEXT NOT NULL, created INTEGER NOT NULL, '
          'attempts INTEGER NOT NULL DEFAULT 0, token TEXT)');
      await old.insert('queue',
          {'payload': 'plain', 'created': 1, 'attempts': 2, 'token': 'k'});
      await old.close();

      await OfflineQueue.openAtPath(path);
      final rows = await (await OfflineQueue.db).query('queue');
      expect(rows.single['token'], 'k');
      expect(rows.single['attempts'], 2);
      expect(await OfflineQueue.rejectedCount(), 0);
    });
  });

  group('chip', () {
    Widget wrap(Widget c) => MaterialApp(
          locale: const Locale('uz'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: c)),
        );

    testWidgets('shows the rejected line even with nothing pending',
        (tester) async {
      await tester.pumpWidget(wrap(PendingResultsChip(
        pendingCountOverride: () async => 0,
        oldestAgeOverride: () async => null,
        rejectedCountOverride: () async => 2,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('2 natija qabul qilinmadi'), findsOneWidget);
      expect(find.textContaining('yuborilmagan'), findsNothing);
    });

    testWidgets('shows pending and rejected lines together', (tester) async {
      await tester.pumpWidget(wrap(PendingResultsChip(
        pendingCountOverride: () async => 3,
        oldestAgeOverride: () async => const Duration(minutes: 5),
        rejectedCountOverride: () async => 1,
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('3 natija yuborilmagan'), findsOneWidget);
      expect(find.text('1 natija qabul qilinmadi'), findsOneWidget);
    });
  });
}
