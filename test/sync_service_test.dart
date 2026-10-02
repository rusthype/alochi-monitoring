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
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/core/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
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
}
