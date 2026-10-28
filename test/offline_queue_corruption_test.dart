// A corrupt monitoring_queue.db must never crash the app: the damaged file is
// moved aside as <name>.corrupt-<ts> (kept for support), a fresh queue is
// created, and the teacher gets one notice.
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('queue_corrupt_');
    OfflineQueue.takeRecoveryNotice(); // clear leftovers
  });
  tearDown(() async {
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test('garbage file: moved aside, fresh queue works, notice raised once',
      () async {
    final path = p.join(tmp.path, 'monitoring_queue.db');
    File(path).writeAsBytesSync(List<int>.generate(4096, (i) => (i * 7) % 251));

    await OfflineQueue.openAtPath(path);

    final aside = tmp
        .listSync()
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith('monitoring_queue.db.corrupt-'))
        .toList();
    expect(aside, hasLength(1));
    expect(aside.single.lengthSync(), 4096);

    expect(await OfflineQueue.totalPendingCount(), 0);
    await OfflineQueue.enqueueLocal({'a': 1}, 'tok');
    expect(await OfflineQueue.totalPendingCount(), 1);

    expect(OfflineQueue.takeRecoveryNotice(), isTrue);
    expect(OfflineQueue.takeRecoveryNotice(), isFalse);
  });

  test('a healthy file is left alone and raises no notice', () async {
    final path = p.join(tmp.path, 'monitoring_queue.db');
    await OfflineQueue.openAtPath(path);
    await OfflineQueue.enqueueLocal({'a': 1}, 'tok');
    await OfflineQueue.resetForTest();

    await OfflineQueue.openAtPath(path);
    expect(await OfflineQueue.pendingLocalCount(), 1);
    expect(tmp.listSync().where((f) => f.path.contains('.corrupt-')), isEmpty);
    expect(OfflineQueue.takeRecoveryNotice(), isFalse);
  });
}
