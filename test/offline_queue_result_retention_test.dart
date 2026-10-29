// Results must never be lost: OfflineQueue.purgeStale never deletes result
// rows (neither by failed-attempt count nor by wall-clock age), and SyncService backs off instead
// of hammering a failing server every 10 s.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/models/models.dart';
import 'package:alochi_monitoring/core/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
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

class _StuckApi extends MonitoringApi {
  int flushes = 0;
  @override
  Future<bool> ping() async => true;
  @override
  Future<int> flushOfflineQueue() async {
    flushes++;
    return 0; // server keeps answering 5xx: nothing leaves the queue
  }
}

void main() {
  late Directory tmp;
  final day = const Duration(days: 1).inMilliseconds;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('queue_retention_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    await DiagnosticAnswerStore.openInMemory();
  });
  tearDown(() async {
    SyncService.instance.dispose();
    await DiagnosticAnswerStore.reset();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  group('purgeStale', () {
    test('a result with 50 failed attempts is NOT deleted', () async {
      await OfflineQueue.enqueue(_result, token: 't1');
      await OfflineQueue.enqueueLocal({'student_id': 's'}, 't2');
      final d = await OfflineQueue.db;
      await d.update('queue', {'attempts': 50});
      await d.update('local_queue', {'attempts': 50});

      await OfflineQueue.purgeStale();

      expect(await OfflineQueue.pendingCount(), 1);
      expect(await OfflineQueue.pendingLocalCount(), 1);
    });

    test('result rows are never deleted by age, whatever the clock says',
        () async {
      // Contract change (audit wave 3): the 30-day wall-clock purge is gone.
      // `created` comes from a PC clock that can be reset to 2000 / stepped by
      // NTP, which used to wipe unsent exams in the first purge after a
      // failed flush.
      await OfflineQueue.enqueue(_result, token: 'old');
      await OfflineQueue.enqueueLocal({'student_id': 'b'}, 'lold');
      final d = await OfflineQueue.db;
      final now = DateTime.now().millisecondsSinceEpoch;
      await d.update('queue', {'created': now - 400 * day});
      await d.update('local_queue', {'created': now - 400 * day});

      expect(await OfflineQueue.purgeStale(), 0);
      // The clock jumped years ahead (or `created` was stamped at 2000).
      expect(await OfflineQueue.purgeStale(nowMs: now + 5000 * day), 0);

      expect((await d.query('queue')).single['token'], 'old');
      expect((await d.query('local_queue')).single['token'], 'lold');
    });

    test('flush keeps counting attempts but a failing flush never deletes',
        () async {
      await OfflineQueue.enqueue(_result, token: 't1');
      for (var i = 0; i < 15; i++) {
        await OfflineQueue.flush((r, t) async =>
            {'synced': false, 'retryable': true});
        await OfflineQueue.purgeStale();
      }
      final rows = await (await OfflineQueue.db).query('queue');
      expect(rows, hasLength(1));
      expect(rows.single['attempts'], 15);
    });
  });

  test('an undecryptable row is neither counted as an attempt nor deleted',
      () async {
    final d = await OfflineQueue.db;
    await d.insert('queue', {
      'payload': 'ENC1:AAAAAAAAAAAAAAAAAAAAAA==:bm90LXJlYWw=',
      'created': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
      'token': 'bad',
    });
    await d.insert('local_queue', {
      'payload': 'ENC1:AAAAAAAAAAAAAAAAAAAAAA==:bm90LXJlYWw=',
      'created': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
      'token': 'bad2',
    });
    var called = false;
    await OfflineQueue.flush((r, t) async {
      called = true;
      return {'synced': true};
    });
    await OfflineQueue.flushLocal((r, t) async {
      called = true;
      return {'synced': true};
    });
    await OfflineQueue.purgeStale();
    expect(called, isFalse);
    expect((await d.query('queue')).single['attempts'], 0);
    expect((await d.query('local_queue')).single['attempts'], 0);
    expect(await OfflineQueue.peekLocalQueue(), isEmpty);
    expect(OfflineQueue.lastPeekUnreadable, 1);
  });

  group('SyncService backoff', () {
    late MonitoringApi saved;
    setUp(() => saved = api);
    tearDown(() => api = saved);

    test('flush without progress doubles the interval up to 5 min, success '
        'resets it', () async {
      final fake = _StuckApi();
      api = fake;
      await OfflineQueue.enqueue(_result, token: 't1');
      final svc = SyncService.instance;
      expect(svc.currentInterval, const Duration(seconds: 10));

      await svc.flushNow();
      expect(svc.currentInterval, const Duration(seconds: 20));
      await svc.flushNow();
      expect(svc.currentInterval, const Duration(seconds: 40));
      for (var i = 0; i < 10; i++) {
        await svc.flushNow();
      }
      expect(svc.currentInterval, const Duration(seconds: 320));

      await (await OfflineQueue.db).delete('queue'); // server accepted it
      await svc.flushNow(); // nothing pending any more
      // nothing pending -> early return keeps the last value; a real
      // successful flush (rows left the queue) must reset:
      await OfflineQueue.enqueue(_result, token: 't2');
      api = _DrainingApi();
      await svc.flushNow();
      expect(svc.currentInterval, const Duration(seconds: 10));
    });

    test('connectivity coming back resets the backoff', () async {
      api = _StuckApi();
      await OfflineQueue.enqueue(_result, token: 't1');
      final svc = SyncService.instance;
      await svc.flushNow();
      await svc.flushNow();
      expect(svc.currentInterval, greaterThan(const Duration(seconds: 10)));
      svc.resetBackoff();
      expect(svc.currentInterval, const Duration(seconds: 10));
    });
  });
}

class _DrainingApi extends MonitoringApi {
  @override
  Future<bool> ping() async => true;
  @override
  Future<int> flushOfflineQueue() async {
    await (await OfflineQueue.db).delete('queue');
    return 1;
  }
}
