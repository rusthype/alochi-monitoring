// Audit wave 2 #4: startup recovery of attempts left by a power cut / crash.

import 'dart:async';
import 'dart:io';

import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/diagnostics/active_test_gate.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/core/services/attempt_recovery_service.dart';
import 'package:alochi_monitoring/features/test/engine_host_screen.dart'
    show buildResultToken, tokenForStoredAttempt;
import 'package:alochi_monitoring/core/models/test_version.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart'
    show currentResultScope;
import 'package:flutter/foundation.dart' show ValueNotifier;
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
  String scope = 'cloud';
  Object? recordError;
  final recorded = <(Map<String, dynamic>, String)>[];
  Future<int?> Function(AttemptEntry)? remaining;
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
        resultScope: () => scope,
        recordInSession: (p, t) async {
          if (recordError != null) throw recordError!;
          recorded.add((p, t));
        },
        serverRemainingSeconds: remaining,
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

  test('paused, empty and never-started records are left alone', () async {
    final h = _Harness([
      _entry(_rec(deadlineInMs: -9 * _min, pausedMs: 120000)),
      _entry(_rec(deadlineInMs: -9 * _min, answers: {}), testKey: 't2'),
      _entry(_rec(), testKey: 't3'), // deadline null: seeded by dispatch
    ])
      ..currentVersion = 2;
    expect(await h.service.run(), 0);
    expect(h.queued, isEmpty);
    expect(h.cleared, isEmpty);
  });

  test(
      'an attempt of another test version is submitted as recovered (the '
      'engine would drop it), even with time left', () async {
    // Contract change (audit wave 3): it used to be skipped and then buried
    // by the new attempt's first save.
    final h = _Harness([
      _entry(_rec(deadlineInMs: 10 * _min, version: 1), testKey: 't4'),
      _entry(_rec(deadlineInMs: -9 * _min, version: 1), testKey: 't5'),
      _entry(_rec(deadlineInMs: 10 * _min, version: 2), testKey: 't6'),
    ])
      ..currentVersion = 2;
    expect(await h.service.run(), 2);
    expect(h.queued.map((q) => (q.$1['detail'] as Map)['recovered']),
        everyElement('test_version_changed'));
    expect(h.cleared, ['attempt_t4', 'attempt_t5']);
  });

  test('abandoned for a week across a reboot: auto-submitted with its answers',
      () async {
    // Saved with 10 min left on boot 1 (ticks 90 min); a week later boot 2.
    final saved = _rec(deadlineInMs: 10 * _min)
      ..['epoch_at_save'] = _Harness._now - 7 * 24 * 60 * _min
      ..['deadline_epoch_ms'] =
          _Harness._now - 7 * 24 * 60 * _min + 10 * _min
      ..['ticks_at_save'] = 90 * 60 * _min;
    final h = _Harness([_entry(saved)], ticks: 5000);
    expect(await h.service.run(), 1);
    expect(h.queued.single.$1['raw_answers'], {'Math/0': 1, 'Math/1': 'x'});
    expect((h.queued.single.$1['detail'] as Map)['recovered'],
        'deadline_passed');
    expect(h.cleared, hasLength(1));
  });

  test('a scan that notices a starting test just before enqueue backs off',
      () async {
    final h = _Harness([_entry(_rec(completed: true))]);
    var calls = 0;
    final s = AttemptRecoveryService(
      listAll: () async => h.entries,
      clearEntry: (e) async => h.cleared.add(e.slotKey),
      enqueue: (p, t) async => h.queued.add((p, t)),
      markDone: (_, __) async {},
      currentVersion: (_) async => null,
      clock: h.clock,
      // free at the scan start and the loop check, busy at the last check
      testScreenActive: () => ++calls >= 3,
    );
    expect(await s.run(), 0);
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

  test('a record without attempt_id gets the same token as the engine host',
      () async {
    final rec = _rec(completed: true, attemptId: null);
    final a = _Harness([_entry(rec)]);
    await a.service.run();
    expect(a.queued.single.$2, tokenForStoredAttempt('math_bob1', rec));
    expect(a.queued.single.$2,
        buildResultToken('math_bob1', 'S-1', 'rec-${rec['started_at']}'));
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

  test(
      'the default "test is active" check honours the start gate (held from '
      'the Start tap, before the engine screen exists)', () async {
    final h = _Harness([_entry(_rec(completed: true))]);
    final s = AttemptRecoveryService(
      listAll: () async => h.entries,
      clearEntry: (e) async => h.cleared.add(e.slotKey),
      enqueue: (p, t) async => h.queued.add((p, t)),
      markDone: (_, __) async {},
      currentVersion: (_) async => null,
      clock: h.clock,
    );
    final release = ActiveTestGate.enter();
    addTearDown(ActiveTestGate.resetForTest);
    expect(await s.run(), 0);
    expect(h.queued, isEmpty);
    release();
    expect(await s.run(), 1);
  });

  test('nothing is queued online during an offline pack / LAN session',
      () async {
    final h = _Harness([_entry(_rec(completed: true))])..scope = 'pack:p1';
    expect(await h.service.run(), 0);
    expect(h.queued, isEmpty);
  });

  // ── wave 8a: recovery inside a pack / LAN session ─────────────────────────

  group('offline session recovery', () {
    Map<String, dynamic> scoped(String scope, {int deadlineInMs = -3 * _min}) =>
        {..._rec(deadlineInMs: deadlineInMs), 'result_scope': scope};

    test('pack: an expired attempt of THIS pack goes into the pack chain',
        () async {
      final h = _Harness([_entry(scoped('pack:p1'))])..scope = 'pack:p1';
      expect(await h.service.run(), 1);
      expect(h.queued, isEmpty, reason: 'never the online queue');
      final (payload, token) = h.recorded.single;
      expect(token, buildResultToken('math_bob1', 'S-1', 'nonce-1'));
      expect(payload['raw_answers'], {'Math/0': 1, 'Math/1': 'x'});
      expect((payload['detail'] as Map)['recovered'], 'deadline_passed');
      expect(h.cleared, hasLength(1));
      expect(h.done, isEmpty, reason: 'a pack roster reads its own chain');
    });

    test('LAN: an expired attempt of THIS hub pack goes into the outbox and '
        'marks the roster', () async {
      final h = _Harness([_entry(scoped('lan:p1'))])..scope = 'lan:p1';
      expect(await h.service.run(), 1);
      expect(h.queued, isEmpty);
      expect(h.recorded, hasLength(1));
      expect(h.done, ['math_bob1|S-1']);
      expect(h.cleared, hasLength(1));
    });

    test('a completed-never-recorded attempt of this session is recorded too',
        () async {
      final h = _Harness([
        _entry({...scoped('pack:p1', deadlineInMs: 5 * _min), 'completed': true})
      ])
        ..scope = 'pack:p1';
      expect(await h.service.run(), 1);
      expect(h.recorded, hasLength(1));
    });

    test('other scope / legacy record (no scope) stays parked and is counted',
        () async {
      final h = _Harness([
        _entry(scoped('cloud')),
        _entry(scoped('pack:other'), parked: true),
        _entry(_rec(deadlineInMs: -3 * _min), testKey: 'math_bob2'), // legacy
      ])
        ..scope = 'pack:p1';
      final s = h.service;
      expect(await s.run(), 0);
      expect(h.recorded, isEmpty);
      expect(h.queued, isEmpty);
      expect(h.cleared, isEmpty);
      expect(s.deferred, 3);
    });

    test('time left, or a test on screen: nothing happens', () async {
      final live = _Harness([_entry(scoped('lan:p1', deadlineInMs: 9 * _min))])
        ..scope = 'lan:p1';
      expect(await live.service.run(), 0);
      expect(live.recorded, isEmpty);

      final busy = _Harness([_entry(scoped('lan:p1'))], screenActive: true)
        ..scope = 'lan:p1';
      expect(await busy.service.run(), 0);
      expect(busy.recorded, isEmpty);
    });

    test('the hub still says time remains: not submitted (resume check kept)',
        () async {
      final h = _Harness([_entry(scoped('lan:p1'))])
        ..scope = 'lan:p1'
        ..remaining = (_) async => 300;
      expect(await h.service.run(), 0);
      expect(h.recorded, isEmpty);
      expect(h.cleared, isEmpty);
    });

    test('a failing session write keeps the attempt and retries later',
        () async {
      final h = _Harness([_entry(scoped('pack:p1'))])
        ..scope = 'pack:p1'
        ..recordError = StateError('chain locked');
      expect(await h.service.run(), 0);
      expect(h.cleared, isEmpty);
      h.recordError = null;
      expect(await h.service.run(), 1);
      expect(h.recorded, hasLength(1));
    });

    test('the session changing during the hub lookup aborts the write',
        () async {
      final h = _Harness([_entry(scoped('lan:p1'))])..scope = 'lan:p1';
      h.remaining = (_) async {
        h.scope = 'cloud'; // the LAN session closed meanwhile
        return null;
      };
      expect(await h.service.run(), 0);
      expect(h.recorded, isEmpty);
      expect(h.queued, isEmpty);
      expect(h.cleared, isEmpty);
    });

    test('cloud mode still sweeps a pack / LAN scoped record online (no other '
        'channel left)', () async {
      final h = _Harness([_entry(scoped('pack:p1'))]);
      expect(await h.service.run(), 1);
      expect(h.queued, hasLength(1));
      expect(h.recorded, isEmpty);
    });

    test('with no session open the scope is cloud', () {
      expect(currentResultScope(), 'cloud');
    });
  });

  test('a list failure is swallowed', () async {
    final s = AttemptRecoveryService(
        listAll: () async => throw StateError('disk'),
        testScreenActive: () => false);
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
      clock: _Harness([]).clock,
    );
    expect(await s.run(), 1);
    expect(queued, [buildResultToken('math_bob1', 'S-1', 'nonce-1')]);
    expect(await AttemptStore.loadForStudent('math_bob1', 'S-1'), isNull);
    expect(await AttemptStore.loadForStudent('math_bob1', 'S-2'), isNotNull);
    expect(await s.run(), 0); // nothing left to do
  });

  // ── wave 5 ────────────────────────────────────────────────────────────────

  AttemptRecoveryService svc(
    _Harness h, {
    ValueNotifier<bool>? gate,
    Future<int?> Function(AttemptEntry)? remaining,
    Future<void> Function(AttemptEntry, Map<String, dynamic>)? extend,
    Future<void> Function(Map<String, dynamic>, String)? enqueue,
    Future<List<AttemptEntry>> Function()? listAll,
    bool Function()? busy,
    Duration scanEvery = const Duration(hours: 1),
    Duration gateDebounce = const Duration(milliseconds: 20),
    Duration retryAfter = const Duration(milliseconds: 20),
  }) =>
      AttemptRecoveryService(
        listAll: listAll ?? () async => h.entries,
        clearEntry: (e) async => h.cleared.add(e.slotKey),
        enqueue: enqueue ??
            (p, t) async {
              if (h.enqueueError != null) throw h.enqueueError!;
              h.queued.add((p, t));
            },
        markDone: (k, s) async => h.done.add('$k|$s'),
        currentVersion: (_) async => h.currentVersion,
        serverRemainingSeconds: remaining ?? (_) async => null,
        extendEntry: extend ?? (e, r) async {},
        clock: h.clock,
        testScreenActive: busy ?? () => gate?.value ?? h.screenActive,
        gate: gate,
        scanEvery: scanEvery,
        gateDebounce: gateDebounce,
        retryAfter: retryAfter,
      );

  Future<void> settle([int ms = 120]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('F3 version defaults', () {
    test('missing version is 0 everywhere and never counts as a change', () {
      expect(parseTestVersion(null), 0);
      expect(parseTestVersion('x'), 0);
      expect(parseTestVersion('7'), 7);
      expect(parseTestVersion(3.0), 3);
      expect(testVersionChanged(1, 0), isFalse); // spec default vs cache 0
      expect(testVersionChanged(0, 4), isFalse);
      expect(testVersionChanged(null, 4), isFalse);
      expect(testVersionChanged(2, 2), isFalse);
      expect(testVersionChanged(2, 3), isTrue);
    });

    test('live attempt of a package with no version is not queued', () async {
      // Cache stores 0 for a package without `version`; the record carries the
      // spec's value.
      final h = _Harness([_entry(_rec(deadlineInMs: 10 * _min, version: 1))])
        ..currentVersion = 0;
      expect(await h.service.run(), 0);
      expect(h.queued, isEmpty);
      expect(h.cleared, isEmpty);
    });
  });

  group('F4 scheduling', () {
    test('rescans when the active-test gate releases (debounced)', () async {
      final gate = ValueNotifier<bool>(false);
      final h = _Harness([]);
      var scans = 0;
      final s = svc(h, gate: gate, listAll: () async {
        scans++;
        return h.entries;
      });
      s.start();
      await settle(); // startup scan
      expect(scans, 1);
      gate.value = true;
      gate.value = false;
      await settle();
      expect(scans, 2);
      s.dispose();
    });

    test('slow periodic rescan runs while the app is up; dispose stops it',
        () async {
      final h = _Harness([]);
      var scans = 0;
      final s = svc(h,
          scanEvery: const Duration(milliseconds: 30),
          listAll: () async {
        scans++;
        return h.entries;
      });
      s.start();
      await settle(200);
      expect(scans, greaterThanOrEqualTo(3));
      s.dispose();
      final at = scans;
      await settle(150);
      expect(scans, at);
    });

    test('a failed enqueue is retried without waiting for a restart',
        () async {
      final h = _Harness([_entry(_rec(completed: true))])
        ..enqueueError = StateError('db locked');
      final s = svc(h);
      expect(await s.run(), 0);
      h.enqueueError = null;
      await settle();
      expect(h.queued, hasLength(1));
      expect(h.cleared, hasLength(1));
      s.dispose();
    });

    test('a scan aborted by a starting test is retried later', () async {
      final h = _Harness([_entry(_rec(completed: true))]);
      var calls = 0;
      // free at the entry check, busy at the loop check, free afterwards
      final s = svc(h, busy: () => ++calls == 2);
      expect(await s.run(), 0);
      await settle();
      expect(h.queued, hasLength(1));
      s.dispose();
    });

    test('overlapping runs never scan concurrently', () async {
      final h = _Harness([]);
      var inFlight = 0, maxInFlight = 0, scans = 0;
      final s = svc(h, listAll: () async {
        scans++;
        maxInFlight = ++inFlight > maxInFlight ? inFlight : maxInFlight;
        await settle(40);
        inFlight--;
        return h.entries;
      });
      await Future.wait([s.run(), s.run(), s.run()]);
      await settle(200);
      expect(maxInFlight, 1);
      expect(scans, 2); // the running one + exactly one follow-up
      s.dispose();
    });
  });

  group('F5 start vs recovery race', () {
    test('Start waits for the same student\'s recovery in flight', () async {
      final h = _Harness([_entry(_rec(completed: true))]);
      final release = Completer<void>();
      final enqueued = Completer<void>();
      final s = svc(h, enqueue: (p, t) async {
        enqueued.complete();
        await release.future;
        h.queued.add((p, t));
      });
      final scan = s.run();
      await enqueued.future;
      var waited = false;
      final w = s.waitForRecovery('S-1').then((_) => waited = true);
      await settle(30);
      expect(waited, isFalse);
      expect(h.cleared, isEmpty);
      release.complete();
      await Future.wait([scan, w]);
      expect(h.cleared, hasLength(1)); // cleared BEFORE Start resumed
      expect(waited, isTrue);
      // Another student is not held up.
      await s.waitForRecovery('S-2');
      s.dispose();
    });

    test('a Start tap between enqueue and clear keeps the record', () async {
      final h = _Harness([_entry(_rec(completed: true))]);
      final s = svc(h, enqueue: (p, t) async {
        h.queued.add((p, t));
        h.screenActive = true; // Start tapped while the enqueue ran
      });
      await s.run();
      expect(h.queued, hasLength(1)); // same token as the engine's: deduped
      expect(h.cleared, isEmpty); // not cleared under the engine
      s.dispose();
    });
  });

  group('F6 hub remaining time', () {
    test('hub says time remains: not submitted, deadline moved', () async {
      final h = _Harness([_entry(_rec(deadlineInMs: -3 * _min))]);
      AttemptEntry? extended;
      Map<String, dynamic>? stored;
      final s = svc(h,
          remaining: (_) async => 300,
          extend: (e, r) async {
            extended = e;
            stored = r;
          });
      expect(await s.run(), 0);
      expect(h.queued, isEmpty);
      expect(h.cleared, isEmpty);
      expect(extended, isNotNull);
      expect(stored!['deadline_epoch_ms'], h.clock.nowMs + 300 * 1000);
      expect(stored!['epoch_at_save'], isNotNull);
      expect(stored!['ticks_at_save'], isNotNull);
      expect(stored!['answers'], {'Math/0': 1, 'Math/1': 'x'});
      s.dispose();
    });

    test('offline / error / timeout / zero left: local deadline decides',
        () async {
      for (final r in <Future<int?> Function(AttemptEntry)>[
        (_) async => null,
        (_) async => 0,
        (_) async => throw StateError('offline'),
        (_) => Future<int?>.delayed(const Duration(milliseconds: 10))
            .then((_) => throw TimeoutException('3s')),
      ]) {
        final h = _Harness([_entry(_rec(deadlineInMs: -3 * _min))]);
        final s = svc(h, remaining: r);
        expect(await s.run(), 1);
        expect((h.queued.single.$1['detail'] as Map)['recovered'],
            'deadline_passed');
        s.dispose();
      }
    });

    test('after one hub failure the rest of the scan does not ask again',
        () async {
      final h = _Harness([
        _entry(_rec(deadlineInMs: -3 * _min), testKey: 'a'),
        _entry(_rec(deadlineInMs: -3 * _min, student: 'S-2'), testKey: 'b'),
      ]);
      var asked = 0;
      final s = svc(h, remaining: (_) async {
        asked++;
        throw StateError('offline');
      });
      expect(await s.run(), 2);
      expect(asked, 1);
      s.dispose();
    });

    test('completed and other-version attempts are queued without the hub',
        () async {
      final h = _Harness([
        _entry(_rec(completed: true), testKey: 'a'),
        _entry(_rec(deadlineInMs: 10 * _min, version: 1), testKey: 'b'),
      ])
        ..currentVersion = 2;
      var asked = 0;
      final s = svc(h, remaining: (_) async {
        asked++;
        return 600;
      });
      expect(await s.run(), 2);
      expect(asked, 0);
      s.dispose();
    });
  });
}
