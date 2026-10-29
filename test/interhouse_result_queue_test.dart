// An interhouse result the server REJECTED (400/409/422 -> permanent +
// rejected) must still be queued, so the queue holds it in `rejected_results`
// instead of losing the finished exam. A plain permanent drop is not queued.
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/models/models.dart';
import 'package:alochi_monitoring/features/interhouse/interhouse_result_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _result = TestResult(
  packageId: 'pkg',
  variant: 1,
  mathScore: 0,
  engScore: 2,
  totalPct: 50,
  answers: {},
  deviceId: 'dev',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('ih_queue_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
  });
  tearDown(() async {
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test('rejected result is queued and ends up held, not lost', () async {
    final synced = await queueUnsyncedInterhouseResult(
        {'synced': false, 'permanent': true, 'rejected': true}, _result);
    expect(synced, false);
    expect(await OfflineQueue.pendingCount(), 1);
    await OfflineQueue.flush((r, t) async => {
          'synced': false,
          'permanent': true,
          'rejected': true,
          'reject_reason': 'http_400',
        });
    expect(await OfflineQueue.rejectedCount(), 1);
  });

  test('retryable is queued, synced and plain permanent drop are not',
      () async {
    expect(
        await queueUnsyncedInterhouseResult(
            {'synced': false, 'retryable': true}, _result),
        false);
    expect(await OfflineQueue.pendingCount(), 1);
    expect(await queueUnsyncedInterhouseResult({'synced': true}, _result), true);
    expect(
        await queueUnsyncedInterhouseResult(
            {'synced': false, 'permanent': true}, _result),
        false);
    expect(await OfflineQueue.pendingCount(), 1);
  });
}
