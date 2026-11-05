// A queued cloud `diagnostic_finish` row must always be replayed through the
// real online DiagnosticKioskApi: a pack / LAN session swapping the global
// `diagnosticKioskApi` for an offline stub (whose submitFinishOffline reports
// synced:true without sending anything) mid-flush used to delete the row
// unsent.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/diagnostic_history_db.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RecordingDiagApi extends DiagnosticKioskApi {
  _RecordingDiagApi(this.result);
  final Map<String, dynamic> result;
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<Map<String, dynamic>> submitFinishOffline(
      Map<String, dynamic> payload, String token,
      {String subject = ''}) async {
    bodies.add(payload);
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late DiagnosticKioskApi saved;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    saved = diagnosticKioskApi;
    tmp = Directory.systemTemp.createTempSync('diag_dispatch_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    await DiagnosticHistoryDb.openInMemory();
    await OfflineQueue.enqueueLocal({
      '_offlineKind': 'diagnostic_finish',
      'attempt_id': 'att-1',
      'answers': const [],
      '_offline_answer_key': {'subject': 'math', 'answers': const {}},
    }, 'tok-1');
  });
  tearDown(() async {
    diagnosticKioskApi = saved;
    parkedOnlineDiagnosticApi = null;
    await OfflineQueue.resetForTest();
    await DiagnosticHistoryDb.reset();
    tmp.deleteSync(recursive: true);
  });

  test('pack/LAN stub swapped in: the queued finish still goes through the '
      'parked online api and the row is not dropped as "synced"', () async {
    final online = _RecordingDiagApi({'synced': false, 'permanent': false});
    final stub = _RecordingDiagApi({'synced': true}); // offline stub behaviour
    parkedOnlineDiagnosticApi = online;
    diagnosticKioskApi = stub;

    final n = await MonitoringApi().flushOfflineQueue();

    expect(n, 0);
    expect(online.bodies, hasLength(1));
    expect(online.bodies.single['attempt_id'], 'att-1');
    expect(online.bodies.single.containsKey('_offline_answer_key'), isFalse);
    expect(stub.bodies, isEmpty);
    expect(await OfflineQueue.pendingLocalCount(), 1); // kept for retry
  });

  test('normal online mode (nothing parked) keeps using the global api',
      () async {
    final online = _RecordingDiagApi({'synced': true});
    diagnosticKioskApi = online;

    final n = await MonitoringApi().flushOfflineQueue();

    expect(n, 1);
    expect(online.bodies, hasLength(1));
    expect(await OfflineQueue.pendingLocalCount(), 0);
  });
}
