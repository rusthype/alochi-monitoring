// Offline queue schema v6 -> v7 migration and the pack result chain store.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/offline/offline_crypto.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final Uint8List _chainKey = Uint8List.fromList(List.generate(32, (i) => i + 1));

class _NoHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('queue_db_');
  });

  tearDown(() async {
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test(
      'v6 database upgrades to the current schema and keeps every existing row',
      () async {
    final path = p.join(tmp.path, 'monitoring_queue.db');
    // Hand-build a v6 database exactly as shipped before this feature.
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 6,
            onCreate: (db, _) async {
              await db.execute('''CREATE TABLE queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL,
                created INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
                token TEXT)''');
              await db.execute(
                  'CREATE UNIQUE INDEX idx_queue_token ON queue(token) WHERE token IS NOT NULL');
              await db.execute('''CREATE TABLE tg_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT, msg TEXT NOT NULL,
                created INTEGER NOT NULL)''');
              await db.execute('''CREATE TABLE local_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL,
                created INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
                token TEXT)''');
              await db.execute(
                  'CREATE UNIQUE INDEX idx_local_queue_token ON local_queue(token) WHERE token IS NOT NULL');
            }));
    await old.insert('queue',
        {'payload': 'P1', 'created': 111, 'attempts': 2, 'token': 'tok-q'});
    await old.insert('local_queue',
        {'payload': 'P2', 'created': 222, 'attempts': 0, 'token': 'tok-l'});
    await old.insert('tg_queue', {'msg': 'M', 'created': 333});
    expect(await old.getVersion(), 6);
    await old.close();

    await OfflineQueue.openAtPath(path);
    final d = await OfflineQueue.db;
    expect(await d.getVersion(), 9);

    final q = await d.query('queue');
    expect(q, hasLength(1));
    expect(q.single['payload'], 'P1');
    expect(q.single['attempts'], 2);
    expect(q.single['token'], 'tok-q');
    final l = await d.query('local_queue');
    expect(l.single['token'], 'tok-l');
    expect((await d.query('tg_queue')).single['msg'], 'M');
    expect(await OfflineQueue.pendingCount(), 1);
    expect(await OfflineQueue.pendingLocalCount(), 1);

    // New tables exist and work.
    await PackResultsDb.append(
        packUuid: 'pk',
        chainKey: _chainKey,
        idempotencyKey: 'k1',
        payloadJson: '{}');
    expect(await PackResultsDb.unexportedCount(), 1);
    // The online queue's stale purge must never touch pack rows.
    await OfflineQueue.purgeStale();
    expect(await PackResultsDb.unexportedCount(), 1);
  });

  test('fresh install creates the current (v8) schema directly', () async {
    await OfflineQueue.openAtPath(p.join(tmp.path, 'fresh.db'));
    final d = await OfflineQueue.db;
    expect(await d.getVersion(), 9);
    final names =
        (await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
            .map((r) => r['name'])
            .toSet();
    expect(
        names,
        containsAll([
          'queue',
          'tg_queue',
          'local_queue',
          'pack_results',
          'pack_meta',
          'lan_outbox'
        ]));
  });

  group('HMAC chain', () {
    setUp(() => OfflineQueue.openAtPath(p.join(tmp.path, 'chain.db')));

    test('links follow the documented formula and start from 64 zeros',
        () async {
      final a = await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: _chainKey,
          idempotencyKey: 'a',
          payloadJson: '{"n":1}');
      final b = await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: _chainKey,
          idempotencyKey: 'b',
          payloadJson: '{"n":2}');
      expect(a.prevHash, '0' * 64);
      expect(a.metaJson,
          '{"idempotency_key":"a","incidents":[],"clock_flags":[]}');
      expect(a.hash,
          OfflineCrypto.chainHash(_chainKey, '0' * 64, '{"n":1}', a.metaJson));
      expect(b.prevHash, a.hash);
      expect(b.hash,
          OfflineCrypto.chainHash(_chainKey, a.hash, '{"n":2}', b.metaJson));
    });

    test('rows are stored encrypted but read back as the exact payload text',
        () async {
      const text = '{"name":"Ali Valiyev","raw_answers":{"A/0":1}}';
      await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: _chainKey,
          idempotencyKey: 'a',
          payloadJson: text);
      final raw = await (await OfflineQueue.db).query('pack_results');
      expect(raw.single['payload'].toString().contains('Ali Valiyev'), isFalse);
      final rows = await PackResultsDb.rowsForPack('pk');
      expect(rows.single.payloadJson, text);
    });

    test('same idempotency key twice -> one row, same link', () async {
      final a = await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: _chainKey,
          idempotencyKey: 'dup',
          payloadJson: '{}');
      final again = await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: _chainKey,
          idempotencyKey: 'dup',
          payloadJson: '{}');
      expect(again.hash, a.hash);
      expect((await PackResultsDb.rowsForPack('pk')), hasLength(1));
    });

    test('separate packs have independent chains', () async {
      final a = await PackResultsDb.append(
          packUuid: 'p1',
          chainKey: _chainKey,
          idempotencyKey: 'a',
          payloadJson: '{}');
      final b = await PackResultsDb.append(
          packUuid: 'p2',
          chainKey: _chainKey,
          idempotencyKey: 'a',
          payloadJson: '{}');
      expect(a.prevHash, '0' * 64);
      expect(b.prevHash, '0' * 64);
    });

    test('markExported stamps rows but never deletes them', () async {
      await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: _chainKey,
          idempotencyKey: 'a',
          payloadJson: '{}');
      expect(await PackResultsDb.unexportedCount('pk'), 1);
      await PackResultsDb.markExported('pk', 12345, 1 << 30);
      expect(await PackResultsDb.unexportedCount('pk'), 0);
      final rows = await PackResultsDb.rowsForPack('pk');
      expect(rows, hasLength(1));
      expect(rows.single.exportedAt, 12345);
      final s = await PackResultsDb.summaries();
      expect(s.single.total, 1);
      expect(s.single.unexported, 0);
    });

    test('meta_json carries incidents/clock flags inside the hash', () async {
      final r = await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: _chainKey,
          idempotencyKey: 'k',
          payloadJson: '{}',
          incidents: [
            {'type': 'focus_lost'}
          ],
          clockFlags: [
            {'type': 'clock_forward'}
          ]);
      expect(r.incidents.single['type'], 'focus_lost');
      expect(r.clockFlags.single['type'], 'clock_forward');
      // changing the meta text changes the link
      expect(
          OfflineCrypto.chainHash(_chainKey, '0' * 64, '{}',
              r.metaJson.replaceAll('focus_lost', 'x')),
          isNot(r.hash));
      // reading back returns the exact stored text (hash stays reproducible)
      final back = (await PackResultsDb.rowsForPack('pk')).single;
      expect(back.metaJson, r.metaJson);
      expect(back.hash, r.hash);
    });

    test('purge removes only EXPORTED rows, 30 days after the pack expired',
        () async {
      final expires = DateTime.utc(2026, 1, 1);
      await PackResultsDb.registerPack(
          packUuid: 'pk', schoolCode: '9', expiresAt: expires);
      await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: _chainKey,
          idempotencyKey: 'a',
          payloadJson: '{}');
      final day = const Duration(days: 1).inMilliseconds;
      final t0 = expires.millisecondsSinceEpoch;

      expect(await PackResultsDb.purgeExpired(nowMs: t0 + 29 * day), 0);
      expect(await PackResultsDb.rowsForPack('pk'), hasLength(1));

      // Not exported yet: never purged, however old (S-007).
      expect(await PackResultsDb.purgeExpired(nowMs: t0 + 400 * day), 0);
      expect(await PackResultsDb.rowsForPack('pk'), hasLength(1));
      expect((await PackResultsDb.summaries()).single.unexported, 1);

      await PackResultsDb.markExported('pk', 1, 1 << 30);
      expect(await PackResultsDb.purgeExpired(nowMs: t0 + 31 * day), 1);
      expect(await PackResultsDb.rowsForPack('pk'), isEmpty);
    });

    test(
        'a freshly exported row survives expiry+30d until the export itself '
        'is 30 days old', () async {
      final expires = DateTime.utc(2026, 1, 1);
      final day = const Duration(days: 1).inMilliseconds;
      final t0 = expires.millisecondsSinceEpoch;
      await PackResultsDb.registerPack(
          packUuid: 'pk', schoolCode: '9', expiresAt: expires);
      await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: _chainKey,
          idempotencyKey: 'a',
          payloadJson: '{}');
      await PackResultsDb.markExported('pk', t0 + 40 * day, 1 << 30);

      // pack expired >30d ago, but the export is only 10 days old: keep
      expect(await PackResultsDb.purgeExpired(nowMs: t0 + 50 * day), 0);
      expect(await PackResultsDb.rowsForPack('pk'), hasLength(1));
      // export now 31 days old AND pack expired >30d: purge
      expect(await PackResultsDb.purgeExpired(nowMs: t0 + 71 * day), 1);
      expect(await PackResultsDb.rowsForPack('pk'), isEmpty);
    });

    test(
        'a system-date jump a year ahead never purges a recent export or an '
        'unexported row', () async {
      final day = const Duration(days: 1).inMilliseconds;
      final expires = DateTime.utc(2026, 1, 1);
      var ticks = 5000;
      var wall =
          expires.millisecondsSinceEpoch + 60 * day; // pack expired 60d ago
      final clock = MonitoredClock(
          ticks: () => ticks, wall: () => wall, highWaterStore: _NoHwm());
      await PackResultsDb.registerPack(
          packUuid: 'pk', schoolCode: '9', expiresAt: expires);
      for (final k in ['exported', 'pending']) {
        await PackResultsDb.append(
            packUuid: 'pk',
            chainKey: _chainKey,
            idempotencyKey: k,
            payloadJson: '{"k":"$k"}');
      }
      // Real exporter path: stamps exported_at from the monitored clock.
      final db = await OfflineQueue.db;
      await db.update('pack_results', {'exported_at': clock.nowMs},
          where: 'idempotency_key = ?', whereArgs: ['exported']);

      wall += 365 * day; // user moves the date a year forward
      ticks += 1000;
      expect(await PackResultsDb.purgeExpired(clock: clock), 0);
      expect(await PackResultsDb.rowsForPack('pk'), hasLength(2));
    });

    test('countKeyPrefix numbers repeat attempts and escapes LIKE wildcards',
        () async {
      for (final k in ['diag:ab_c:1', 'diag:ab_c:2', 'diag:abxc:1']) {
        await PackResultsDb.append(
            packUuid: 'pk',
            chainKey: _chainKey,
            idempotencyKey: k,
            payloadJson: '{}');
      }
      expect(await PackResultsDb.countKeyPrefix('pk', 'diag:ab_c:'), 2);
      expect(await PackResultsDb.countKeyPrefix('pk', 'diag:nope:'), 0);
    });
  });
}
