// Tests SyncService's new diagnostic-answer flush wiring (see
// _flushDiagnosticAnswers in sync_service.dart).
//
// NOTE on strategy: SyncService._flushAll/_flushDiagnosticAnswers talk to
// two hardcoded global singletons (`api` in api_client.dart,
// `diagnosticKioskApi` in diagnostic_kiosk_api.dart) that build their own
// http.get/http.post calls directly — there is no mockito, no MockClient,
// and no injectable HTTP seam anywhere in this codebase (confirmed: no
// `mockito` dependency in pubspec.yaml, no `Mock(` usage on either
// singleton). Every existing test that touches network-adjacent logic in
// this repo (classifyFinishOfflineResponse, withRecoveredScore,
// checkOnlineWithRetry) does so by testing the pure/DB-side logic directly
// instead of mocking HTTP — there is no established seam to call
// SyncService.flushNowWithResult() end-to-end and assert a real sync
// happened without either hitting the live api.alochi.org server (flaky,
// slow, and not something this codebase does anywhere) or inventing new
// mocking infrastructure the task didn't ask for.
//
// So this file instead pins down the exact SQLite read/write contract that
// `_flushDiagnosticAnswers` relies on: attemptsWithPending() surfaces new
// pending work, pendingForAttempt() returns the right shape to build the
// sync payload from, and markSynced() (called on the helper's success path)
// removes the attempt from future flush cycles — one bad attempt's rows
// never affect another attempt's.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/core/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _HubHealthyApi extends MonitoringApi {
  // LAN mode: ping() is the hub's health check, so it is true.
  @override
  Future<bool> ping() async => true;
}

class _RecordingSyncApi extends DiagnosticKioskApi {
  int syncCalls = 0;
  @override
  Future<Map<String, dynamic>> syncAnswers({
    required String attemptId,
    required List<Map<String, dynamic>> answers,
    int? generation,
  }) async {
    syncCalls++;
    return {'ok': true};
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DiagnosticAnswerStore.openInMemory();
  });

  tearDown(() async {
    await DiagnosticAnswerStore.reset();
    SyncService.instance.dispose();
  });

  test('a freshly saved answer is picked up as pending for its attempt',
      () async {
    await DiagnosticAnswerStore.saveAnswer(
      attemptId: 'att-1',
      subject: 'math',
      questionIndex: 1,
      questionId: 'q1',
      selectedOption: 'B',
    );

    expect(await DiagnosticAnswerStore.attemptsWithPending(), ['att-1']);
    final pending = await DiagnosticAnswerStore.pendingForAttempt('att-1');
    expect(pending, hasLength(1));
    expect(pending.first['question_index'], 1);
    expect(pending.first['question_id'], 'q1');
    expect(pending.first['selected_option'], 'B');
    expect(pending.first['answered_at'], isNotNull);
  });

  test(
      'marking synced (the success path of _flushDiagnosticAnswers) clears '
      'the attempt from the next flush cycle', () async {
    await DiagnosticAnswerStore.saveAnswer(
      attemptId: 'att-1',
      subject: 'math',
      questionIndex: 1,
      questionId: 'q1',
      selectedOption: 'B',
    );

    // Mirrors exactly what _flushDiagnosticAnswers does after a successful
    // diagnosticKioskApi.syncAnswers() call.
    await DiagnosticAnswerStore.markSynced('att-1', ['q1']);

    expect(await DiagnosticAnswerStore.pendingForAttempt('att-1'), isEmpty);
    expect(await DiagnosticAnswerStore.attemptsWithPending(), isEmpty);
  });

  test(
      'one attempt failing to sync never touches another attempt\'s '
      'pending rows (per-attempt isolation)', () async {
    await DiagnosticAnswerStore.saveAnswer(
      attemptId: 'att-bad',
      subject: 'math',
      questionIndex: 1,
      questionId: 'q1',
      selectedOption: 'A',
    );
    await DiagnosticAnswerStore.saveAnswer(
      attemptId: 'att-good',
      subject: 'math',
      questionIndex: 1,
      questionId: 'q1',
      selectedOption: 'A',
    );

    expect(await DiagnosticAnswerStore.attemptsWithPending(),
        containsAll(['att-bad', 'att-good']));

    // att-bad's sync "fails" (its rows are simply never marked synced) —
    // att-good's success must be unaffected.
    await DiagnosticAnswerStore.markSynced('att-good', ['q1']);

    expect(
        await DiagnosticAnswerStore.pendingForAttempt('att-bad'), hasLength(1));
    expect(await DiagnosticAnswerStore.pendingForAttempt('att-good'), isEmpty);
    expect(await DiagnosticAnswerStore.attemptsWithPending(), ['att-bad']);
  });

  group('probe offline -> online flush', () {
    SignalReading r(SignalTier t, {bool checking = false}) => SignalReading(
        tier: t,
        latencyMs: null,
        measuredAt: DateTime.now(),
        checking: checking);

    test('flushes once (debounced) on offline->online edge only', () async {
      var flushes = 0;
      final svc = SyncService.instance
        ..probeDebounce = const Duration(milliseconds: 30)
        ..probeFlushOverride = () async => flushes++;
      addTearDown(() => svc.probeFlushOverride = null);

      svc.handleProbeReading(r(SignalTier.none, checking: true)); // ignored
      svc.handleProbeReading(r(SignalTier.good)); // first reading: no edge
      svc.handleProbeReading(r(SignalTier.good));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(flushes, 0);

      svc.handleProbeReading(r(SignalTier.none));
      svc.handleProbeReading(r(SignalTier.good)); // edge
      svc.handleProbeReading(r(SignalTier.none)); // flap
      svc.handleProbeReading(r(SignalTier.good)); // edge again, debounced
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(flushes, 1);

      svc.handleProbeReading(r(SignalTier.good)); // still online: no flush
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(flushes, 1);
    });
  });

  group('LAN mode never flushes cloud diagnostic answers', () {
    late Directory tmp;
    late MonitoringApi savedApi;
    late DiagnosticKioskApi savedDiag;
    late _RecordingSyncApi diag;

    setUp(() async {
      savedApi = api;
      savedDiag = diagnosticKioskApi;
      api = _HubHealthyApi();
      diag = _RecordingSyncApi();
      diagnosticKioskApi = diag;
      tmp = Directory.systemTemp.createTempSync('sync_lan_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'cloud-att',
        subject: 'math',
        questionIndex: 1,
        questionId: 'q1',
        selectedOption: 'A',
      );
    });

    tearDown(() async {
      api = savedApi;
      diagnosticKioskApi = savedDiag;
      LanClientSession.current = null;
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    test('control: online (no LAN) the pending answers are sent and marked',
        () async {
      await SyncService.instance.flushNowWithResult();
      expect(diag.syncCalls, 1);
      expect(await DiagnosticAnswerStore.attemptsWithPending(), isEmpty);
    });

    test('with a LanClientSession the flush skips them, rows stay pending',
        () async {
      final lan = await LanClientSession.join(
        host: '127.0.0.1',
        port: 8080,
        code: '123456',
        client: MockClient((req) async => http.Response(
            '{"token":"${'t' * 32}",'
            '"pack_uuid":"11111111-2222-3333-4444-555555555555"}',
            200,
            headers: {'content-type': 'application/json'})),
        machineId: 'pc-1',
        deviceName: 'pc-1',
        mediaDirFor: (id) async => tmp,
      );
      LanClientSession.current = lan;
      addTearDown(lan.close);

      await SyncService.instance.flushNowWithResult();

      expect(diag.syncCalls, 0);
      expect(await DiagnosticAnswerStore.attemptsWithPending(), ['cloud-att']);
    });
  });
}
