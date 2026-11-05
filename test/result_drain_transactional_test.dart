// Proctoring metadata (incidents + clock-tamper flags) must survive a failed
// result write: the pack session peeks them, writes, and clears only what
// THIS write stored (a failed write or an idempotent replay keeps them).
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/security/incident_log.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/lan_test_pack.dart';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

/// A clock that has already seen the date being set forward (one flag).
MonitoredClock _clockWithFlag() {
  var ticks = 1000000;
  var wall = DateTime.utc(2026, 10, 17, 9).millisecondsSinceEpoch;
  final c = MonitoredClock(
      ticks: () => ticks, wall: () => wall, highWaterStore: _MemHwm());
  ticks += 5000;
  wall += 5000 + 3600000;
  c.checkNow();
  expect(c.pendingFlags, hasLength(1));
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('IncidentLog.peek/consume', () {
    setUp(() => IncidentLog.instance.drain());
    tearDown(() => IncidentLog.instance.drain());

    test('peek does not clear; consume removes only what was peeked', () {
      final log = IncidentLog.instance;
      log.add('a');
      log.add('b');
      final peeked = log.peek();
      expect(peeked.map((e) => e['type']), ['a', 'b']);
      expect(log.snapshot, hasLength(2));
      log.add('c'); // arrives while the write is in flight
      log.consume(peeked);
      expect(log.snapshot.map((e) => e['type']), ['c']);
    });

    test('overflow counts are consumed too, later drops stay', () {
      final log = IncidentLog.instance;
      for (var i = 0; i < 205; i++) {
        log.add('x');
      }
      final peeked = log.peek();
      expect(peeked.last['type'], 'incident_overflow');
      expect(peeked.last['dropped'], {'x': 5});
      log.consume(peeked);
      expect(log.snapshot, isEmpty);
      expect(log.peek(), isEmpty);
    });
  });

  group('OfflinePackSession.recordResult keeps metadata unless stored', () {
    late Directory tmp;
    late OfflinePackSession session;
    late MonitoredClock savedClock;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('drain_tx_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      session = await OfflinePackSession.open(lanTestPack(), tmp);
      savedClock = MonitoredClock.instance;
      MonitoredClock.instance = _clockWithFlag();
      IncidentLog.instance.drain();
      IncidentLog.instance.add('focus_lost');
    });

    tearDown(() async {
      MonitoredClock.instance = savedClock;
      IncidentLog.instance.drain();
      OfflinePackSession.close();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    test('write throws -> incidents and flags are still pending', () async {
      final d = await OfflineQueue.db;
      await d.execute('ALTER TABLE pack_results RENAME TO pack_results_off');
      await expectLater(session.recordResult(lanResultPayload(), token: 'k1'),
          throwsA(anything));
      expect(
          IncidentLog.instance.snapshot.map((e) => e['type']), ['focus_lost']);
      expect(MonitoredClock.instance.pendingFlags, hasLength(1));

      // The retry (DB back) carries them into the stored row.
      await d.execute('ALTER TABLE pack_results_off RENAME TO pack_results');
      final row = await session.recordResult(lanResultPayload(), token: 'k1');
      final meta = jsonDecode(row.metaJson) as Map<String, dynamic>;
      expect((meta['incidents'] as List).single['type'], 'focus_lost');
      expect((meta['clock_flags'] as List).single['type'], 'clock_forward');
    });

    test('success clears exactly what was stored', () async {
      await session.recordResult(lanResultPayload(), token: 'k1');
      expect(IncidentLog.instance.snapshot, isEmpty);
      expect(MonitoredClock.instance.pendingFlags, isEmpty);
    });

    test('idempotent replay stores nothing, so nothing is dropped', () async {
      await session.recordResult(lanResultPayload(), token: 'k1');
      IncidentLog.instance.add('tab_switch'); // a new attempt's incident
      final again = await session.recordResult(lanResultPayload(), token: 'k1');
      // Not attached to the old row, not lost: still waiting.
      expect(again.metaJson, isNot(contains('tab_switch')));
      expect(
          IncidentLog.instance.snapshot.map((e) => e['type']), ['tab_switch']);
      expect((await PackResultsDb.rowsForPack(lanPackUuid)), hasLength(1));
    });
  });
}
