// Audit wave 6: SERVER TIME as an independent witness for the test timer.
//  R1  absorbSuspend: a real suspend leaves the device-to-server offset
//      unchanged (credit the gap); a manual date change moves it (credit
//      nothing, flag it). Offline: the old rule.
//  R2  rebaseSavedDeadline / the recovery sweep: online, elapsed since the save
//      is server-now minus server-at-save.
import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/core/services/attempt_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

const _s = 1000;
const _min = 60 * _s;
const _h = 60 * _min;

/// Device (ticks + wall) and a server whose clock only ever follows real time.
class _World {
  int ticks = 5000000;
  int wall = DateTime.utc(2026, 10, 29, 9).millisecondsSinceEpoch;

  /// Real elapsed time as the server sees it.
  int server = DateTime.utc(2026, 10, 29, 9).millisecondsSinceEpoch;
  bool online = true;
  int seq = 0;
  int? offset;
  int probes = 0;

  /// The PC slept [ms]: ticks frozen, wall and server moved on.
  void sleep(int ms) {
    wall += ms;
    server += ms;
  }

  /// Real time passes on every clock.
  void advance(int ms) {
    ticks += ms;
    wall += ms;
    server += ms;
  }

  /// The server was heard from now (an API answer's Date header).
  void observe({int bias = 0}) {
    offset = server - wall + bias;
    seq++;
  }

  MonitoredClock clock({bool probeAnswers = false, int Function()? slack}) =>
      MonitoredClock(
        offsetUncertaintyMs: slack,
        ticks: () => ticks,
        wall: () => wall,
        highWaterStore: _NoHwm(),
        serverSample: () =>
            online && offset != null ? (offsetMs: offset!, seq: seq) : null,
        probeServer: () {
          probes++;
          if (probeAnswers && online) observe();
        },
      );
}

bool _flagged(MonitoredClock c) =>
    c.pendingFlags.any((f) => f['type'] == 'clock_change_server_confirmed');

void main() {
  group('R1 absorbSuspend with the server as witness', () {
    test('real suspend (offset unchanged) credits the gap once', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(30 * _s);
      expect(c.absorbSuspend(), 0);
      final before = c.nowMs;

      // Lid closed 10 min: ticks frozen, wall and server moved on.
      w.wall += 10 * _min;
      w.server += 10 * _min;
      expect(c.absorbSuspend(), 0, reason: 'held until the server answers');
      expect(w.probes, 1);
      expect(c.nowMs, before, reason: 'nothing credited while waiting');

      w.advance(1 * _s);
      w.observe(); // the probe's answer
      expect(c.absorbSuspend(), 10 * _min);
      expect(c.nowMs - before, 10 * _min + _s);
      expect(_flagged(c), isFalse);
      w.advance(_s);
      expect(c.absorbSuspend(), 0, reason: 'no double credit');
    });

    test('manual +1 h date shift credits nothing and is flagged', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(30 * _s);
      c.absorbSuspend();
      final before = c.nowMs;

      w.wall += 1 * _h; // student moves the date forward; real time did not
      expect(c.absorbSuspend(), 0);
      w.advance(1 * _s);
      w.observe();
      expect(c.absorbSuspend(), 0);
      expect(c.nowMs - before, _s, reason: 'only the real second passed');
      expect(_flagged(c), isTrue);
      final flag = c.pendingFlags
          .singleWhere((f) => f['type'] == 'clock_change_server_confirmed');
      expect(flag['skew_ms'], 1 * _h);
      expect((flag['offset_delta_ms'] as int) + 1 * _h, lessThan(5 * _s));
    });

    test('manual date shift BACK credits nothing and is flagged', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(30 * _s);
      c.absorbSuspend();
      final before = c.nowMs;

      w.wall -= 1 * _h;
      c.absorbSuspend();
      w.advance(_s);
      w.observe();
      expect(c.absorbSuspend(), 0);
      expect(c.nowMs - before, _s);
      expect(_flagged(c), isTrue);
    });

    test('suspend plus a date moved back: only the real sleep is credited', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(30 * _s);
      c.absorbSuspend();
      final before = c.nowMs;

      // Slept 10 min (ticks frozen) and the date was moved 30 min back.
      w.server += 10 * _min;
      w.wall += 10 * _min - 30 * _min;
      c.absorbSuspend();
      w.advance(_s);
      w.observe();
      expect(c.absorbSuspend(), closeTo(10 * _min, 5 * _s));
      expect(c.nowMs - before, closeTo(10 * _min + _s, 5 * _s));
      expect(_flagged(c), isTrue);
    });

    test('a measurement taken BEFORE the jump is not a witness', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(_s);
      c.absorbSuspend();

      w.wall += 1 * _h;
      expect(c.absorbSuspend(), 0);
      w.advance(_s);
      // No new observation (seq unchanged): still waiting, nothing credited.
      expect(c.absorbSuspend(), 0);
      expect(_flagged(c), isFalse);
      w.observe();
      expect(c.absorbSuspend(), 0);
      expect(_flagged(c), isTrue);
    });

    test('offline from the start: the old rule credits at once', () {
      final w = _World()..online = false;
      final c = w.clock();
      w.advance(30 * _s);
      c.absorbSuspend();
      final before = c.nowMs;
      w.wall += 10 * _min;
      expect(c.absorbSuspend(), 10 * _min);
      expect(c.nowMs - before, 10 * _min);
      expect(w.probes, 0);
    });

    test('online but the server never answers: old rule after the wait', () {
      final w = _World()..observe();
      final c = w.clock(); // probe does not answer
      w.advance(_s);
      c.absorbSuspend();
      final before = c.nowMs;
      w.wall += 1 * _h;
      expect(c.absorbSuspend(), 0);
      w.advance(5 * _s);
      expect(c.absorbSuspend(), 0);
      w.advance(6 * _s);
      expect(c.absorbSuspend(), 1 * _h, reason: 'offline behaviour');
      expect(c.nowMs - before, 1 * _h + 11 * _s);
      expect(_flagged(c), isFalse);
    });

    test('an offset only loaded from disk (no sample) is no witness', () {
      final w = _World(); // offset never observed in this process
      final c = w.clock();
      w.wall += 10 * _min;
      expect(c.absorbSuspend(), 10 * _min);
    });

    test('startMonitoring drops a verdict pending from before the screen', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(_s);
      c.absorbSuspend();
      w.wall += 10 * _min;
      w.server += 10 * _min;
      c.absorbSuspend(); // held
      c.startMonitoring();
      final before = c.nowMs;
      w.advance(_s);
      w.observe();
      expect(c.absorbSuspend(), 0);
      expect(c.nowMs - before, _s);
      c.stopMonitoring();
    });
  });

  group('R2 server time at save', () {
    const remainingAtSave = 20 * _min;

    // Saved at the world's current moment; then the app is closed.
    ({int deadline, Map<String, int> snap}) save(_World w) {
      final saver = w.clock();
      final snap = saver.snapshot();
      return (deadline: snap['epoch_at_save']! + remainingAtSave, snap: snap);
    }

    int rebase(MonitoredClock c, ({int deadline, Map<String, int> snap}) s,
            {bool withServer = true}) =>
        c.rebaseSavedDeadline(
          deadlineEpochMs: s.deadline,
          epochAtSaveMs: s.snap['epoch_at_save'],
          ticksAtSaveMs: s.snap['ticks_at_save'],
          serverEpochAtSaveMs:
              withServer ? s.snap['server_epoch_at_save_ms'] : null,
        );

    test('snapshot carries the server epoch only when the server is known', () {
      final w = _World();
      expect(w.clock().snapshot().containsKey('server_epoch_at_save_ms'),
          isFalse);
      w.observe();
      expect(w.clock().snapshot()['server_epoch_at_save_ms'], w.server);
      w.online = false;
      expect(w.clock().snapshot().containsKey('server_epoch_at_save_ms'),
          isFalse);
    });

    test('snapshot omits it while a clock jump awaits its verdict', () {
      final w = _World()..observe();
      final c = w.clock();
      c.absorbSuspend();
      w.wall += 1 * _h;
      c.absorbSuspend();
      expect(c.snapshot().containsKey('server_epoch_at_save_ms'), isFalse);
    });

    test('long absence: ticks look continuous but the server says it expired',
        () {
      final w = _World()..observe();
      final s = save(w);
      // Next day: new boot (ticks restart small yet "continuous"), the RTC
      // reads earlier than the save. 9 h of real time went by.
      w.server += 9 * _h;
      w.ticks += 15 * _s;
      w.wall -= 2 * 24 * _h;
      w.observe();
      final c = w.clock();
      expect(rebase(c, s, withServer: false), greaterThan(c.nowMs),
          reason: 'without the witness the old logic grants time');
      expect(rebase(c, s), lessThan(c.nowMs));
    });

    test('a wall step while the app was closed is ignored', () {
      final w = _World()..observe();
      final s = save(w);
      w.advance(5 * _min);
      w.wall += 3 * _h; // date moved forward by hand
      w.observe(); // login after the restart re-learns the offset
      final c = w.clock();
      expect(rebase(c, s, withServer: false), lessThan(c.nowMs),
          reason: 'old logic reads the step as elapsed time');
      expect(rebase(c, s) - c.nowMs, closeTo(15 * _min, _s));
    });

    test('genuinely short absence keeps the remaining time', () {
      final w = _World()..observe();
      final s = save(w);
      w.advance(7 * _min);
      w.observe();
      final c = w.clock();
      expect(rebase(c, s) - c.nowMs, closeTo(13 * _min, _s));
    });

    test('a server epoch from the future never adds time', () {
      final w = _World()..observe();
      final s = save(w);
      final future = {...s.snap}
        ..['server_epoch_at_save_ms'] = s.snap['server_epoch_at_save_ms']! + _h;
      final c = w.clock();
      final r = c.rebaseSavedDeadline(
        deadlineEpochMs: s.deadline,
        epochAtSaveMs: future['epoch_at_save'],
        ticksAtSaveMs: future['ticks_at_save'],
        serverEpochAtSaveMs: future['server_epoch_at_save_ms'],
      );
      expect(r - c.nowMs, remainingAtSave);
    });

    test('an old record without the field uses the old logic', () {
      final w = _World()..observe();
      final s = save(w);
      w.advance(7 * _min);
      w.observe();
      final c = w.clock();
      final offline = _World()
        ..online = false
        ..ticks = w.ticks
        ..wall = w.wall;
      expect(rebase(c, s, withServer: false),
          rebase(offline.clock(), s, withServer: false));
    });

    test('record with the field but the server unknown: old logic', () {
      final w = _World()..observe();
      final s = save(w);
      w.advance(7 * _min);
      w.online = false;
      final c = w.clock();
      expect(rebase(c, s), rebase(c, s, withServer: false));
    });

    test('the recovery sweep uses the same rule', () async {
      final w = _World()..observe();
      final s = save(w);
      // 25 min later by the server; ticks and wall hide it (frozen ticks, wall
      // 5 min ahead only - the old logic sees a live attempt).
      w.server += 25 * _min;
      w.wall += _s;
      w.ticks += _s;
      w.observe();
      final queued = <String>[];
      Future<int> sweep() => AttemptRecoveryService(
            listAll: () async => [
              AttemptEntry(
                slotKey: 'attempt_math_bob1',
                testKey: 'math_bob1',
                isParked: false,
                record: {
                  'variant': 2,
                  'answers': {'Math/0': 1},
                  'started_at': s.snap['epoch_at_save']! - 10 * _min,
                  'attempt_id': 'n1',
                  'deadline_epoch_ms': s.deadline,
                  'epoch_at_save': s.snap['epoch_at_save'],
                  'ticks_at_save': s.snap['ticks_at_save'],
                  'server_epoch_at_save_ms': s.snap['server_epoch_at_save_ms'],
                  'student_name': 'A',
                  'student_id': 'S-1',
                  'group_name': '5-A',
                  'school': '56',
                  'grade': 5,
                  'group_id': 'g',
                  'test_key': 'math_bob1',
                },
              ),
            ],
            clearEntry: (e) async {},
            enqueue: (p, t) async => queued.add(t),
            markDone: (k, st) async {},
            currentVersion: (_) async => null,
            clock: w.clock(),
            testScreenActive: () => false,
          ).run();
      expect(await sweep(), 1, reason: 'server says the attempt expired');
      expect(queued, hasLength(1));
    });
  });

  // ── wave 7 ───────────────────────────────────────────────────────────────

  group('W7 P2-1 discardPending', () {
    test('drops a held verdict so a late server answer credits nothing', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(_s);
      c.absorbSuspend();
      w.sleep(10 * _min);
      expect(c.absorbSuspend(), 0);
      c.discardPending();
      final before = c.nowMs;
      w.advance(_s);
      w.observe();
      expect(c.absorbSuspend(), 0);
      expect(c.nowMs - before, _s);
      expect(_flagged(c), isFalse);
    });
  });

  group('W7 P2-2 stale server offset', () {
    const remainingAtSave = 20 * _min;

    test('wall set back after the first observation: no time handed back', () {
      final w = _World()..observe();
      final saver = w.clock();
      final snap = saver.snapshot();
      final deadline = snap['epoch_at_save']! + remainingAtSave;
      w.advance(25 * _min); // the attempt really expired
      final c = w.clock(); // app restarted
      w.observe(); // first observation of this process
      w.wall -= 1 * _h; // date moved back before the restore
      final r = c.rebaseSavedDeadline(
        deadlineEpochMs: deadline,
        epochAtSaveMs: snap['epoch_at_save'],
        ticksAtSaveMs: snap['ticks_at_save'],
        serverEpochAtSaveMs: snap['server_epoch_at_save_ms'],
      );
      expect(r, lessThan(c.nowMs), reason: 'the tick rule still expires it');
    });

    test('wall moved forward just before a save: no late server epoch', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(_s);
      expect(c.snapshot().containsKey('server_epoch_at_save_ms'), isTrue);
      w.wall += 1 * _h;
      expect(c.snapshot().containsKey('server_epoch_at_save_ms'), isFalse);
    });

    test('after a settled jump the witness is trusted again', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(_s);
      c.absorbSuspend();
      w.wall += 1 * _h;
      c.absorbSuspend();
      w.advance(_s);
      w.observe();
      c.absorbSuspend(); // verdict
      expect(c.snapshot()['server_epoch_at_save_ms'], w.server);
    });
  });

  group('W7 P3-4 confirmed gaps are not capped at 12 h', () {
    test('14 h suspend confirmed by the server is credited', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(30 * _s);
      c.absorbSuspend();
      final before = c.nowMs;
      w.sleep(14 * _h);
      c.absorbSuspend();
      w.advance(_s);
      w.observe();
      expect(c.absorbSuspend(), closeTo(14 * _h, 5 * _s));
      expect(c.nowMs - before, closeTo(14 * _h, 5 * _s));
      expect(_flagged(c), isFalse);
    });

    test('offline: a 14 h gap keeps the 12 h cap and credits nothing', () {
      final w = _World()..online = false;
      final c = w.clock();
      w.advance(30 * _s);
      c.absorbSuspend();
      final before = c.nowMs;
      w.wall += 14 * _h;
      expect(c.absorbSuspend(), 0);
      expect(c.nowMs, before);
    });

    test('even a confirmed gap above the 7 day ceiling is not credited', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(30 * _s);
      c.absorbSuspend();
      final before = c.nowMs;
      w.sleep(8 * 24 * _h);
      c.absorbSuspend();
      w.advance(_s);
      w.observe();
      expect(c.absorbSuspend(), 0);
      expect(c.nowMs - before, _s);
    });
  });

  group('W7 P3-5 sleep hidden by a wall reset', () {
    // Lid closed (ticks frozen, server moved on) and the wall clock put back by
    // the same amount before the next tick: wall and ticks agree, only the
    // device-to-server offset moved.
    MonitoredClock slept(_World w, int ms) {
      final c = w.clock();
      w.advance(30 * _s);
      c.absorbSuspend();
      w.server += ms;
      return c;
    }

    test('a fresh observation shows the offset moved: the gap is credited', () {
      final w = _World()..observe();
      final c = slept(w, 10 * _min);
      final before = c.nowMs;
      expect(c.absorbSuspend(), 0, reason: 'no observation yet');
      w.observe();
      expect(c.absorbSuspend(), closeTo(10 * _min, 5 * _s));
      expect(c.nowMs - before, closeTo(10 * _min, 5 * _s));
      expect(_flagged(c), isTrue);
      expect(c.absorbSuspend(), 0, reason: 'credited once');
    });

    test('server offset moving the other way credits nothing', () {
      final w = _World()..observe();
      final c = slept(w, -10 * _min);
      final before = c.nowMs;
      w.observe();
      expect(c.absorbSuspend(), 0);
      expect(c.nowMs, before);
    });

    test('an offset within the tolerance credits nothing', () {
      final w = _World()..observe();
      final c = slept(w, 3 * _s);
      final before = c.nowMs;
      w.observe();
      expect(c.absorbSuspend(), 0);
      expect(c.nowMs, before);
      expect(_flagged(c), isFalse);
    });

    test('offline / no new observation: nothing happens', () {
      final w = _World()..observe();
      final c = slept(w, 10 * _min);
      final before = c.nowMs;
      w.online = false;
      expect(c.absorbSuspend(), 0);
      w.online = true;
      expect(c.absorbSuspend(), 0, reason: 'same seq as the baseline');
      expect(c.nowMs, before);
    });
  });

  group('W7 P3-6 observation latency bias', () {
    test('slow ping on a real suspend still credits in full, unflagged', () {
      final w = _World()..observe();
      final c = w.clock(slack: () => 9 * _s); // 8 s round trip + 1 s
      w.advance(30 * _s);
      c.absorbSuspend();
      final before = c.nowMs;
      w.sleep(10 * _min);
      c.absorbSuspend();
      w.advance(_s);
      w.observe(bias: -8 * _s); // the Date header was 8 s old on arrival
      expect(c.absorbSuspend(), 10 * _min);
      expect(c.nowMs - before, 10 * _min + _s);
      expect(_flagged(c), isFalse);
    });

    test('unknown round trip widens the tolerance to 10 s', () {
      final w = _World()..observe();
      final c = w.clock();
      w.advance(30 * _s);
      c.absorbSuspend();
      w.sleep(10 * _min);
      c.absorbSuspend();
      w.advance(_s);
      w.observe(bias: -8 * _s);
      expect(c.absorbSuspend(), 10 * _min);
      expect(_flagged(c), isFalse);
    });

    test('a 10 minute manual date change is still detected', () {
      final w = _World()..observe();
      final c = w.clock(slack: () => 9 * _s);
      w.advance(30 * _s);
      c.absorbSuspend();
      final before = c.nowMs;
      w.wall += 10 * _min;
      c.absorbSuspend();
      w.advance(_s);
      w.observe(bias: -8 * _s);
      expect(c.absorbSuspend(), 0);
      expect(c.nowMs - before, _s);
      expect(_flagged(c), isTrue);
    });
  });

  group('W7 P2-3 hub extension drops the stale server epoch', () {
    AttemptEntry entry(_World w, Map<String, int> snap, int deadline) =>
        AttemptEntry(
          slotKey: 'attempt_math_bob1',
          testKey: 'math_bob1',
          isParked: false,
          record: {
            'variant': 2,
            'answers': {'Math/0': 1},
            'started_at': snap['epoch_at_save']! - 10 * _min,
            'attempt_id': 'n1',
            'deadline_epoch_ms': deadline,
            'epoch_at_save': snap['epoch_at_save'],
            'ticks_at_save': snap['ticks_at_save'],
            'server_epoch_at_save_ms': snap['server_epoch_at_save_ms'],
            'student_name': 'A',
            'student_id': 'S-1',
            'group_name': '5-A',
            'school': '56',
            'grade': 5,
            'group_id': 'g',
            'test_key': 'math_bob1',
          },
        );

    Future<Map<String, dynamic>> extend(_World w, MonitoredClock clock,
        {bool offlineAfterSave = false}) async {
      final snap = w.clock().snapshot();
      expect(snap.containsKey('server_epoch_at_save_ms'), isTrue);
      final deadline = snap['epoch_at_save']! + 20 * _min;
      w.advance(25 * _min); // local deadline passed
      if (offlineAfterSave) w.online = false;
      Map<String, dynamic>? stored;
      await AttemptRecoveryService(
        listAll: () async => [entry(w, snap, deadline)],
        clearEntry: (e) async {},
        enqueue: (p, t) async {},
        markDone: (k, st) async {},
        currentVersion: (_) async => null,
        serverRemainingSeconds: (_) async => 300,
        extendEntry: (e, r) async => stored = r,
        clock: clock,
        testScreenActive: () => false,
      ).run();
      return stored!;
    }

    test('server unknown at the extension: the old epoch is not kept', () async {
      final w = _World()..observe();
      final clock = w.clock();
      // The new snapshot cannot carry a server epoch.
      final stored = await extend(w, clock, offlineAfterSave: true);
      expect(stored.containsKey('server_epoch_at_save_ms'), isFalse);
      expect(stored['epoch_at_save'], isNotNull);
    });

    test('server known: the fresh epoch replaces the old one', () async {
      final w = _World()..observe();
      final clock = w.clock();
      final stored = await extend(w, clock);
      expect(stored['server_epoch_at_save_ms'], w.server);
    });
  });
}
