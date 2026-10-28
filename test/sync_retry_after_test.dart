// SyncService honours the server's Retry-After (no automatic flush earlier)
// and spreads its ticks with 0-5 s jitter so a lab of PCs does not flush in
// lockstep. A queue row hit by 429 + Retry-After stops the rest of the flush.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/models/models.dart';
import 'package:alochi_monitoring/core/sync/server_backoff.dart';
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

class _CountingApi extends MonitoringApi {
  int pings = 0;
  int flushes = 0;
  @override
  Future<bool> ping() async {
    pings++;
    return true;
  }

  @override
  Future<int> flushOfflineQueue() async {
    flushes++;
    return 0;
  }
}

void main() {
  late Directory tmp;
  late MonitoringApi saved;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    saved = api;
    tmp = Directory.systemTemp.createTempSync('sync_retry_after_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    await DiagnosticAnswerStore.openInMemory();
    ServerBackoff.clear();
  });
  tearDown(() async {
    api = saved;
    SyncService.instance.dispose();
    SyncService.instance.jitterOverride = null;
    ServerBackoff.clear();
    await DiagnosticAnswerStore.reset();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test('the next tick is the normal interval plus 0-5 s jitter', () {
    final svc = SyncService.instance;
    final seen = <int>{};
    for (var i = 0; i < 200; i++) {
      final d = svc.nextDelay();
      expect(d, greaterThanOrEqualTo(svc.currentInterval));
      expect(d, lessThan(svc.currentInterval + const Duration(seconds: 5)));
      seen.add(d.inMilliseconds);
    }
    expect(seen.length, greaterThan(1), reason: 'jitter must vary');
  });

  test('the next tick is never earlier than the server Retry-After', () {
    final svc = SyncService.instance;
    svc.jitterOverride = () => Duration.zero;
    ServerBackoff.note(const Duration(minutes: 2));
    expect(svc.nextDelay(), greaterThanOrEqualTo(const Duration(seconds: 119)));
    ServerBackoff.clear();
    expect(svc.nextDelay(), const Duration(seconds: 10));
  });

  test('automatic flushes wait out Retry-After, a manual one does not',
      () async {
    final fake = _CountingApi();
    api = fake;
    await OfflineQueue.enqueue(_result, token: 't1');
    final svc = SyncService.instance;
    ServerBackoff.note(const Duration(minutes: 1));

    expect(await svc.flushAutomatic(), SyncFlushOutcome.busy);
    expect(fake.flushes, 0);

    await svc.flushNow(); // teacher pressed the button
    expect(fake.flushes, 1);
  });

  test('flush stops at the first row answered with Retry-After', () async {
    await OfflineQueue.enqueueLocal({'n': 1}, 'a');
    await OfflineQueue.enqueueLocal({'n': 2}, 'b');
    await OfflineQueue.enqueueLocal({'n': 3}, 'c');
    var calls = 0;
    final synced = await OfflineQueue.flushLocal((payload, token) async {
      calls++;
      return {'synced': false, 'permanent': false, 'retry_after_s': 30};
    });
    expect(synced, 0);
    expect(calls, 1);
    expect(ServerBackoff.active, isTrue);
    expect(await OfflineQueue.pendingLocalCount(), 3);
  });
}
