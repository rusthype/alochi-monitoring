// OfflineQueue must open (and keep user data) on ANY on-disk schema, including
// ones whose PRAGMA user_version lags the real tables (seen on a school PC:
// user_version 1 with the full v6 schema -> SqfliteFfiException on every open).
import 'dart:io';

import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds the REAL schema a given app version produced, then stamps
/// [userVersion] (which may deliberately disagree).
Future<void> _seed(String path, int schemaVersion, int userVersion) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  final v = schemaVersion;
  final tokenQ = v >= 5 ? ', token TEXT' : '';
  await db.execute('CREATE TABLE queue (id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'payload TEXT NOT NULL, created INTEGER NOT NULL, '
      'attempts INTEGER NOT NULL DEFAULT 0$tokenQ)');
  if (v >= 5) {
    await db.execute('CREATE UNIQUE INDEX idx_queue_token ON queue(token) '
        'WHERE token IS NOT NULL');
  }
  if (v >= 2) {
    await db.execute('CREATE TABLE tg_queue (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, msg TEXT NOT NULL, created INTEGER NOT NULL)');
  }
  if (v >= 3) {
    final tokenL = v >= 4 ? ', token TEXT' : '';
    await db.execute('CREATE TABLE local_queue (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, payload TEXT NOT NULL, created INTEGER NOT NULL, '
        'attempts INTEGER NOT NULL DEFAULT 0$tokenL)');
  }
  if (v >= 6) {
    await db.execute('CREATE UNIQUE INDEX idx_local_queue_token ON '
        'local_queue(token) WHERE token IS NOT NULL');
  }
  if (v >= 7) {
    await db.execute('CREATE TABLE pack_results (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, pack_uuid TEXT NOT NULL, idempotency_key TEXT NOT '
        'NULL, payload TEXT NOT NULL, meta_json TEXT NOT NULL, prev_hash TEXT '
        'NOT NULL, hash TEXT NOT NULL, created INTEGER NOT NULL, exported_at '
        'INTEGER)');
    await db.execute('CREATE UNIQUE INDEX idx_pack_results_key ON '
        'pack_results(pack_uuid, idempotency_key)');
    await db.execute('CREATE TABLE pack_meta (pack_uuid TEXT PRIMARY KEY, '
        "school_code TEXT NOT NULL DEFAULT '', expires_at INTEGER NOT NULL, "
        'loaded_at INTEGER NOT NULL)');
  }
  await db.insert('queue', {'payload': 'q1', 'created': 1});
  if (v >= 3) await db.insert('local_queue', {'payload': 'l1', 'created': 2});
  await db.execute('PRAGMA user_version = $userVersion');
  await db.close();
}

Future<int> _i(Database db, String sql) async =>
    (await db.rawQuery(sql)).first.values.first as int;

Future<Set<String>> _tables(Database db) async =>
    (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'] as String)
        .toSet();

void main() {
  late Directory tmp;
  late String path;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('queue_mig_');
    path = p.join(tmp.path, 'monitoring_queue.db');
  });
  tearDown(() async {
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<void> expectHealthy({required bool hadLocal}) async {
    await OfflineQueue.openAtPath(path);
    final db = await OfflineQueue.db;
    expect(await _i(db, 'PRAGMA user_version'), 9);
    expect(
        await _tables(db),
        containsAll(<String>{
          'queue',
          'tg_queue',
          'local_queue',
          'pack_results',
          'pack_meta',
          'lan_outbox',
          'local_students',
        }));
    expect(await db.query('queue', columns: ['payload']), [
      {'payload': 'q1'}
    ]);
    if (hadLocal) {
      expect(await db.query('local_queue', columns: ['payload']), [
        {'payload': 'l1'}
      ]);
    }
    // Columns usable end to end.
    await db.insert('queue', {'payload': 'q2', 'created': 3, 'token': 't'});
    await db
        .insert('local_queue', {'payload': 'l2', 'created': 3, 'token': 't'});

    // Second open is a no-op: same data, still v9.
    await OfflineQueue.openAtPath(path);
    final again = await OfflineQueue.db;
    expect(await _i(again, 'SELECT COUNT(*) FROM queue'), 2);
    expect(await _i(again, 'PRAGMA user_version'), 9);
  }

  test('real office-1 case: full v6 schema stamped user_version 1', () async {
    await _seed(path, 6, 1);
    await expectHealthy(hadLocal: true);
  });

  for (final v in [1, 2, 3, 4, 5, 6, 7]) {
    test('genuine v$v schema upgrades', () async {
      await _seed(path, v, v);
      await expectHealthy(hadLocal: v >= 3);
    });
  }

  test('v7 pack tables present but user_version 6', () async {
    await _seed(path, 7, 6);
    await expectHealthy(hadLocal: true);
  });

  test('full schema but user_version 0 (create path on existing tables)',
      () async {
    await _seed(path, 7, 0);
    await expectHealthy(hadLocal: true);
  });

  test('v8 schema (no local_students) upgrades to v9 keeping rows', () async {
    await _seed(path, 7, 8); // a real v8 install: v7 tables + lan_outbox
    var db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('CREATE TABLE lan_outbox (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, pack_uuid TEXT NOT NULL, idempotency_key TEXT NOT '
        'NULL, envelope TEXT NOT NULL, created INTEGER NOT NULL, attempts '
        'INTEGER NOT NULL DEFAULT 0, status INTEGER NOT NULL DEFAULT 0, '
        'reject_reason TEXT)');
    await db.close();
    await expectHealthy(hadLocal: true);
    // The new table is usable and survives a second open.
    final cur = await OfflineQueue.db;
    await cur.insert('local_students', {
      'temp_id': 'new:1',
      'group_id': 'g',
      'first_name': 'Ali',
      'last_name': 'Valiyev',
      'created': 1,
    });
    await OfflineQueue.openAtPath(path);
    final again = await OfflineQueue.db;
    expect(await _i(again, 'SELECT COUNT(*) FROM local_students'), 1);
  });

  test('fresh create', () async {
    await OfflineQueue.openAtPath(path);
    final db = await OfflineQueue.db;
    expect(await _i(db, 'PRAGMA user_version'), 9);
    expect(await _tables(db), containsAll(<String>{'queue', 'pack_results'}));
  });

  test('DiagnosticAnswerStore.upgrade tolerates an existing generation column',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('CREATE TABLE local_diagnostic_answers (id INTEGER '
        'PRIMARY KEY, attempt_id TEXT, generation INTEGER)');
    await DiagnosticAnswerStore.upgrade(db, 1, 2);
    await DiagnosticAnswerStore.upgrade(db, 1, 2);
    await db.close();
  });
}
