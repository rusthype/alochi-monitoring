// Audit wave 2 #4: startup recovery of attempts left by a power cut / crash.

import 'dart:io';

import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/core/services/attempt_recovery_service.dart';
import 'package:alochi_monitoring/features/test/engine_host_screen.dart'
    show buildResultToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

const _min = 60 * 1000;

class _Harness {
  _Harness(this.entries, {int? wall, int? ticks, this.screenActive = false})
      : clock = MonitoredClock(
            ticks: () => ticks ?? 5000,
            wall: () => wall ?? _now,
            highWaterStore: _MemHwm());

  static final _now = DateTime.utc(2026, 10, 29, 10).millisecondsSinceEpoch;

  final List<AttemptEntry> entries;
  final MonitoredClock clock;
  bool screenActive;
  bool offlineSession = false;
  Object? enqueueError;
  int? currentVersion;
  final queued = <(Map<String, dynamic>, String)>[];
  final cleared = <String>[];
  final done = <String>[];

  AttemptRecoveryService get service => AttemptRecoveryService(
        listAll: () async => entries,
        clearEntry: (e) async => cleared.add(e.slotKey),
        enqueue: (p, t) async {
          if (enqueueError != null) throw enqueueError!;
          queued.add((p, t));
        },
        markDone: (k, s) async => done.add('$k|$s'),
        currentVersion: (_) async => currentVersion,
        clock: clock,
        testScreenActive: () => screenActive,
        offlineSessionActive: () => offlineSession,
      );
}

AttemptEntry _entry(
  Map<String, dynamic> rec, {
  String testKey = 'math_bob1',
  bool parked = false,
}) =>
    AttemptEntry(
      slotKey: parked
          ? 'attempt_${testKey}__parked__${rec['student_id']}'
          : 'attempt_$testKey',
      testKey: testKey,
      isParked: parked,
      record: rec,
    );

Map<String, dynamic> _rec({
  bool completed = false,
  int? deadlineInMs,
  Map<String, dynamic>? answers,
  String student = 'S-1',
  Object? pausedMs,
  Object? school = '56',
  Object? version,
  String? attemptId = 'nonce-1',
}) =>
    {
      'variant': 2,
      'answers': answers ?? {'Math/0': 1, 'Math/1': 'x'},
      'started_at': _Harness._now - 40 * _min,
      if (attemptId != null) 'attempt_id': attemptId,
      if (completed) 'completed': true,
      'deadline_epoch_ms':
          deadlineInMs == null ? null : _Harness._now + deadlineInMs,
      if (pausedMs != null) 'paused_remaining_ms': pausedMs,
      if (version != null) 'test_version': version,
      'student_name': 'Karimov Ali',
      'student_id': student,
      'group_name': '5-A',
      if (school != null) 'school': school,
      'grade': 5,
      'group_id': 'g-9',
      'test_key': 'math_bob1',
    };

void main() {
  test('completed but never queued: queued with the engine token, then cleared',
      () async {
    final h = _Harness([_entry(_rec(completed: true, deadlineInMs: 5 * _min))]);
    expect(await h.service.run(), 1);

    expect(h.queued, hasLength(1));
    final (payload, token) = h.queued.single;
    expect(token, buildResultToken('math_bob1', 'S-1', 'nonce-1'));
    expect(payload['name'], 'Karimov Ali');
    expect(payload['grade'], 5);
    expect(payload['variant'], '2');
    expect(payload['school_code'], '56');
    expect(payload['group_id'], 'g-9');
    expect(payload['group_name'], '5-A');
    expect(payload['student_id'], 'S-1');
    expect(payload['raw_answers'], {'Math/0': 1, 'Math/1': 'x'});
    expect((payload['detail'] as Map)['test_key'], 'math_bob1');
    expect(h.done, ['math_bob1|S-1']);
    expect(h.cleared, ['attempt_math_bob1']);
  });

  test('unfinished with the deadline passed is auto-submitted with its answers',
      () async {
    final h = _Harness([_entry(_rec(deadlineInMs: -3 * _min))]);
    expect(await h.service.run(), 1);
    final (payload, token) = h.queued.single;
    expect(token, buildResultToken('math_bob1', 'S-1', 'nonce-1'));
    expect(payload['raw_answers'], {'Math/0': 1, 'Math/1': 'x'});
    expect((payload['detail'] as Map)['recovered'], 'deadline_passed');
    expect(payload['duration_seconds'], greaterThan(0));
    expect(h.cleared, hasLength(1));
    expect(h.done, ['math_bob1|S-1']);
  });

  test('unfinished with time remaining is left alone', () async {
    final h = _Harness([_entry(_rec(deadlineInMs: 10 * _min))]);
    expect(await h.service.run(), 0);
    expect(h.queued, isEmpty);
    expect(h.cleared, isEmpty);
  });

  test('a clock reset to 1970 after the cut must not expire (or extend) it',
      () async {
    // Saved with 10 min left; after reboot the RTC reads 1970.
    final saved = _rec(deadlineInMs: 10 * _min)
      ..['epoch_at_save'] = _Harness._now
      ..['ticks_at_save'] = 90 * 60 * _min;
    final h = _Harness([_entry(saved)], wall: 0, ticks: 5000);
    expect(await h.service.run(), 0);
    expect(h.cleared, isEmpty);
  });

  test('paused, empty, never-started and other-version records are left alone',
      () async {
    final h = _Harness([
      _entry(_rec(deadlineInMs: -9 * _min, pausedMs: 120000)),
      _entry(_rec(deadlineInMs: -9 * _min, answers: {}), testKey: 't2'),
      _entry(_rec(), testKey: 't3'), // deadline null: seeded by dispatch
      _entry(_rec(deadlineInMs: -9 * _min, version: 1), testKey: 't4'),
    ])
      ..currentVersion = 2;
    expect(await h.service.run(), 0);
    expect(h.queued, isEmpty);
    expect(h.cleared, isEmpty);
  });

  test('parked records of displaced students are recovered too', () async {
    final h = _Harness([
      _entry(_rec(student: 'S-2', deadlineInMs: 8 * _min)), // B still going
      _entry(_rec(student: 'S-1', completed: true), parked: true),
    ]);
    expect(await h.service.run(), 1);
    expect(h.queued.single.$1['student_id'], 'S-1');
    expect(h.cleared, ['attempt_math_bob1__parked__S-1']);
  });

  test('diagnostic blobs and records without identity are skipped', () async {
    final h = _Harness([
      _entry(_rec(completed: true), testKey: 'diag_abc'),
      _entry(_rec(completed: true, school: null), testKey: 'old_build'),
    ]);
    expect(await h.service.run(), 0);
    expect(h.cleared, isEmpty);
  });

  test('a record without attempt_id still gets a stable token', () async {
    final a = _Harness([_entry(_rec(completed: true, attemptId: null))]);
    final b = _Harness([_entry(_rec(completed: true, attemptId: null))]);
    await a.service.run();
    await b.service.run();
    expect(a.queued.single.$2, b.queued.single.$2);
  });

  test('a failing enqueue keeps the record and does not stop the scan',
      () async {
    final h = _Harness([
      _entry(_rec(completed: true), testKey: 'a'),
      _entry(_rec(completed: true, student: 'S-2'), testKey: 'b'),
    ])
      ..enqueueError = StateError('db locked');
    expect(await h.service.run(), 0);
    expect(h.cleared, isEmpty);

    h.enqueueError = null;
    expect(await h.service.run(), 2); // next scan retries both
    expect(h.cleared, hasLength(2));
  });

  test('a scan while a test screen is open does nothing', () async {
    final h = _Harness([_entry(_rec(completed: true))], screenActive: true);
    expect(await h.service.run(), 0);
    expect(h.queued, isEmpty);
    h.screenActive = false;
    expect(await h.service.run(), 1);
  });

  test('nothing is queued online during an offline pack / LAN session',
      () async {
    final h = _Harness([_entry(_rec(completed: true))])..offlineSession = true;
    expect(await h.service.run(), 0);
    expect(h.queued, isEmpty);
  });

  test('a list failure is swallowed', () async {
    final s = AttemptRecoveryService(
        listAll: () async => throw StateError('disk'),
        testScreenActive: () => false,
        offlineSessionActive: () => false);
    expect(await s.run(), 0);
  });

  test('end to end with the real file-backed store: queued once, store emptied',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await QueueCrypto.encryptPayload('{}');
    final tmp = Directory.systemTemp.createTempSync('recovery_e2e_');
    addTearDown(() {
      AttemptStore.useDirectoryForTest(null);
      tmp.deleteSync(recursive: true);
    });
    AttemptStore.useDirectoryForTest(tmp);
    await AttemptStore.save(
        'math_bob1', _rec(completed: true, deadlineInMs: 5 * _min));
    await AttemptStore.save(
        'math_bob1', _rec(student: 'S-2', deadlineInMs: 8 * _min)); // parks S-1

    final queued = <String>[];
    final s = AttemptRecoveryService(
      enqueue: (p, t) async => queued.add(t),
      markDone: (_, __) async {},
      currentVersion: (_) async => null,
      testScreenActive: () => false,
      offlineSessionActive: () => false,
      clock: _Harness([]).clock,
    );
    expect(await s.run(), 1);
    expect(queued, [buildResultToken('math_bob1', 'S-1', 'nonce-1')]);
    expect(await AttemptStore.loadForStudent('math_bob1', 'S-1'), isNull);
    expect(await AttemptStore.loadForStudent('math_bob1', 'S-2'), isNotNull);
    expect(await s.run(), 0); // nothing left to do
  });
}
