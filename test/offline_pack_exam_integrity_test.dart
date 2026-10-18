// Exam integrity: a student is mid-exam on a USB pack and the internet comes
// back. Nothing may reach the real server, the session must not switch, and
// answers must keep landing in the pack's HMAC chain.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_package_api.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The REAL server, reachable, recording every call that would leave the PC.
class _RecordingRealApi extends MonitoringApi {
  final calls = <String>[];

  @override
  Future<bool> ping() async {
    calls.add('ping');
    return true;
  }

  @override
  Future<bool> pingHealth(
      {Duration timeout = const Duration(seconds: 2)}) async {
    calls.add('pingHealth');
    return true;
  }

  @override
  Future<int> flushOfflineQueue() async {
    calls.add('flushOfflineQueue');
    return 0;
  }

  @override
  Future<Map<String, dynamic>> submitLocalResultFull(
      Map<String, dynamic> payload, String token) async {
    calls.add('submitLocalResultFull');
    return {'synced': true};
  }

  @override
  Future<bool> uploadCrashReport(String jsonBody) async {
    calls.add('uploadCrashReport');
    return true;
  }
}

void main() {
  const dir = 'test/fixtures/offline';
  late Directory tmp;
  late MonitoringApi savedApi;
  late OfflineKeys savedKeys;
  late _RecordingRealApi real;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('exam_integrity_');
    savedApi = api;
    savedKeys = OfflineKeys.current;
    real = _RecordingRealApi();
    api = real;
    OfflineKeys.current = OfflineKeys(
      signingPem: File('$dir/test_signing_public.pem').readAsStringSync(),
      resultsPem: File('$dir/test_results_public.pem').readAsStringSync(),
    );
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    await DiagnosticAnswerStore.openInMemory();
  });

  tearDown(() async {
    SyncService.instance.dispose();
    SyncService.instance.probeFlushOverride = null;
    SyncService.instance.probeDebounce = const Duration(seconds: 2);
    OfflinePackSession.close();
    api = savedApi;
    OfflineKeys.current = savedKeys;
    await DiagnosticAnswerStore.reset();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test(
      'internet returns mid-exam on a pack: no call on the real api, no '
      'auto-exit, answers still land in the pack chain', () async {
    final media = Directory(p.join(tmp.path, 'media'))..createSync();
    final pack = await PackLoader(keys: OfflineKeys.current).open(
        File('$dir/golden.alochipack').readAsBytesSync(), '12345678',
        mediaDir: media);
    final session = await OfflinePackSession.open(pack, media);
    final packApi = api;
    expect(packApi, isA<OfflinePackageApi>());

    // Pending work, so a flush really reaches its network gate.
    await DiagnosticAnswerStore.saveAnswer(
      attemptId: 'att-1',
      subject: 'math',
      questionIndex: 1,
      questionId: 'q1',
      selectedOption: 'B',
    );

    // Real-server probe flips offline -> online (what ConnectivityService now
    // reports for a pack session), through the real edge-triggered flush.
    final svc = SyncService.instance..probeDebounce = Duration.zero;
    var flushStarts = 0;
    svc.flushing.addListener(() {
      if (svc.flushing.value) flushStarts++;
    });
    SignalReading r(SignalTier t) =>
        SignalReading(tier: t, latencyMs: 1, measuredAt: DateTime(2026));
    svc.handleProbeReading(r(SignalTier.none));
    svc.handleProbeReading(r(SignalTier.good)); // the edge
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (flushStarts == 0 && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    while (svc.flushing.value) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(flushStarts, 1, reason: 'the online edge must trigger a flush');

    // (a) nothing went to the real server; the flush stops at the swapped api.
    expect(real.calls, isEmpty);
    expect(await svc.flushNowWithResult(), SyncFlushOutcome.noNetwork);
    expect(real.calls, isEmpty);
    expect(await DiagnosticAnswerStore.attemptsWithPending(), ['att-1']);

    // (b) no auto-exit / switch.
    expect(OfflinePackSession.current, same(session));
    expect(identical(api, packApi), isTrue);

    // (c) an answer submitted through the pack api still lands in the chain.
    final res = await api.submitLocalResultFull(
        {'test_key': 'golden_test_1', 'student_id': 'S1', 'pct': 80}, 'tok-1');
    expect(res['synced'], isTrue);
    expect(await PackResultsDb.hasKey(pack.packUuid, 'tok-1'), isTrue);
    expect(real.calls, isEmpty);
  });
}
