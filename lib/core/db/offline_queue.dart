// lib/core/db/offline_queue.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/models.dart';
import '../api/api_client.dart';
import '../diagnostics/error_log.dart';
import '../sync/server_backoff.dart';
import 'db_migrate.dart';
import 'local_students_db.dart';
import 'pack_local_students_db.dart';
import 'queue_crypto.dart';

class OfflineQueue {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    _db = await _openRecovering(join(dir.path, 'monitoring_queue.db'));
    changes.value++; // a recovery notice may be waiting
    return _db!;
  }

  /// Test seam: open the queue at an explicit path (same schema/migrations).
  @visibleForTesting
  static Future<void> openAtPath(String path) async {
    await resetForTest();
    _db = await _openRecovering(path);
    changes.value++;
  }

  static bool _recoveryNotice = false;

  /// Bumped whenever rows are added to / removed from the result queues (or
  /// the queue file is opened), so UI that shows the pending count refreshes
  /// on the event instead of polling with a timer.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Latest known size of the result queues and the age of the oldest row,
  /// published by the queue operations themselves (PendingResultsChip reads
  /// this and never queries the file on its own).
  static final ValueNotifier<({int count, Duration? oldest})> pending =
      ValueNotifier<({int count, Duration? oldest})>((count: 0, oldest: null));

  /// Results the server REJECTED (409 `max_attempts_exceeded` etc.): kept in
  /// their own terminal table, never retried, never purged. The teacher chip
  /// shows this count next to the pending one.
  static final ValueNotifier<int> rejected = ValueNotifier<int>(0);

  static void _changed() {
    changes.value++;
    unawaited(refreshPending());
  }

  /// Re-reads [pending] from the queue. Never throws.
  static Future<({int count, Duration? oldest})> refreshPending() async {
    try {
      final count = await _countAll();
      final oldest = count > 0 ? await oldestPendingAge() : null;
      rejected.value = await rejectedCount();
      return pending.value = (count: count, oldest: oldest);
    } catch (e) {
      debugPrint('OfflineQueue.refreshPending: $e');
      return pending.value;
    }
  }

  /// True once after a corrupt queue file was replaced: the screens that
  /// already poll the queue show ONE teacher-visible notice (the results that
  /// were inside are in the `.corrupt-<ts>` file next to it, for support).
  static bool takeRecoveryNotice() {
    final v = _recoveryNotice;
    _recoveryNotice = false;
    return v;
  }

  /// Unreadable file (not a database / malformed) - as opposed to a merely
  /// locked or busy one, whose results must never be moved away.
  static bool _isCorrupt(Object e) {
    if (e is! DatabaseException) return false;
    final m = e.toString().toLowerCase();
    if (m.contains('locked') || m.contains('busy')) return false;
    return m.contains('not a database') ||
        m.contains('malformed') ||
        m.contains('corrupt') ||
        m.contains('notadb') ||
        m.contains('disk image');
  }

  /// [_open], but a corrupt file never crashes the app: it is moved aside as
  /// `<name>.corrupt-<ts>` (with -wal / -shm), a fresh queue is created and
  /// [takeRecoveryNotice] raises the teacher notice.
  static Future<Database> _openRecovering(String path) async {
    try {
      return await _open(path);
    } catch (e) {
      if (!_isCorrupt(e)) rethrow;
      debugPrint('OfflineQueue: $path is corrupt ($e), moving it aside');
      unawaited(ErrorLog.record(e, 'queue_db'));
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$path$suffix');
        try {
          if (await f.exists()) await f.rename('$path.corrupt-$ts$suffix');
        } catch (err) {
          debugPrint('OfflineQueue: could not move ${f.path} aside: $err');
        }
      }
      final db = await _open(path);
      _recoveryNotice = true;
      return db;
    }
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    await _db?.close();
    _db = null;
    pending.value = (count: 0, oldest: null);
    rejected.value = 0;
  }

  // Schema v9 adds `local_students` (local_students_db.dart): children a
  // proctor added while offline + their temp -> server id mapping. Additive
  // and idempotent like every step before it; nothing else changes.
  //
  // Schema v8 adds `lan_outbox` (lan_outbox_db.dart): results a LAN client has
  // not yet handed to the teacher's hub. Its own table, so neither the online
  // flush nor purgeStale() can ever see (or drop) those rows.
  //
  // Schema v7 adds the offline-USB-pack tables (pack_results / pack_meta, see
  // pack_results_db.dart). They are separate tables on purpose: the online
  // queue/local_queue flush, purgeStale and the diagnostic peek must never see
  // pack rows, and pack rows must never be dropped by the 7-day stale purge.
  static Future<Database> _open(String path) {
    // One idempotent ensureSchema for create, upgrade AND every open: the
    // stored user_version cannot be trusted (see db_migrate.dart), so the
    // schema is verified against reality instead of replayed by version.
    return openDatabase(path, version: 9, onOpen: ensureSchema);
  }

  /// Brings any queue DB (fresh, any older version, or version-drifted) to the
  /// v9 schema without touching existing rows.
  @visibleForTesting
  static Future<void> ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS queue (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        payload  TEXT NOT NULL,
        created  INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        token    TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tg_queue (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        msg      TEXT NOT NULL,
        created  INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_queue (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        payload  TEXT NOT NULL,
        created  INTEGER NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        token    TEXT
      )
    ''');
    // v4/v5: token columns on tables created by older builds without them.
    await addColumnIfMissing(db, 'local_queue', 'token', 'TEXT');
    await addColumnIfMissing(db, 'queue', 'token', 'TEXT');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_queue_token ON queue(token) WHERE token IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_local_queue_token ON local_queue(token) WHERE token IS NOT NULL',
    );
    // Additive (no version bump: ensureSchema runs on every open). Results the
    // server rejected live here; no older code path ever reads this table.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rejected_results (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        source    TEXT NOT NULL,
        payload   TEXT NOT NULL,
        token     TEXT,
        created   INTEGER NOT NULL,
        attempts  INTEGER NOT NULL DEFAULT 0,
        reason    TEXT,
        rejected_at INTEGER NOT NULL
      )
    ''');
    await createPackTables(db);
    await createLanTables(db);
    await LocalStudentsDb.createTable(db);
    await PackLocalStudentsDb.createTable(db);
  }

  /// v7 tables for offline USB packs. Idempotent (IF NOT EXISTS) so a
  /// create + upgrade path can never double-apply.
  @visibleForTesting
  static Future<void> createPackTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pack_results (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        pack_uuid        TEXT NOT NULL,
        idempotency_key  TEXT NOT NULL,
        payload          TEXT NOT NULL,
        meta_json        TEXT NOT NULL,
        prev_hash        TEXT NOT NULL,
        hash             TEXT NOT NULL,
        created          INTEGER NOT NULL,
        exported_at      INTEGER
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_pack_results_key ON pack_results(pack_uuid, idempotency_key)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pack_meta (
        pack_uuid    TEXT PRIMARY KEY,
        school_code  TEXT NOT NULL DEFAULT '',
        expires_at   INTEGER NOT NULL,
        loaded_at    INTEGER NOT NULL
      )
    ''');
    // Additive (no version bump needed: ensureSchema runs on every open).
    // kind: 'monitoring' | 'diagnostic' (NULL = packs stored before this);
    // created_at: pack manifest created_at (ms); archived_at: local archive flag.
    await addColumnIfMissing(db, 'pack_meta', 'kind', 'TEXT');
    await addColumnIfMissing(db, 'pack_meta', 'created_at', 'INTEGER');
    await addColumnIfMissing(db, 'pack_meta', 'archived_at', 'INTEGER');
  }

  /// v8 table for the LAN client outbox. Idempotent like [createPackTables].
  @visibleForTesting
  static Future<void> createLanTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lan_outbox (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        pack_uuid        TEXT NOT NULL,
        idempotency_key  TEXT NOT NULL,
        envelope         TEXT NOT NULL,
        created          INTEGER NOT NULL,
        attempts         INTEGER NOT NULL DEFAULT 0,
        status           INTEGER NOT NULL DEFAULT 0,
        reject_reason    TEXT
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_lan_outbox_key ON lan_outbox(pack_uuid, idempotency_key)',
    );
  }

  static Future<void> enqueue(TestResult result, {String? token}) async {
    final d = await db;
    final t = token ?? newIdempotencyToken();
    await d.insert(
      'queue',
      {
        'payload':
            await QueueCrypto.encryptPayload(jsonEncode(result.toJson())),
        'created': DateTime.now().millisecondsSinceEpoch,
        'attempts': 0,
        'token': t,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _changed();
  }

  static Future<int> flush(
      Future<Map<String, dynamic>> Function(TestResult, String)
          submitFn) async {
    final d = await db;
    final rows = await d.query('queue', orderBy: 'created ASC');
    int synced = 0;
    for (final row in rows) {
      try {
        final json = jsonDecode(
            await QueueCrypto.decryptPayload(row['payload'] as String));
        final result = TestResult(
          packageId: json['package_id'],
          variant: json['variant'],
          mathScore: json['math_score'],
          engScore: json['eng_score'],
          totalPct: json['total_pct'],
          answers: Map<String, String>.from(json['answers'] ?? {}),
          deviceId: json['device_id'] ?? 'offline',
        );
        final token = (row['token'] as String?) ?? '';
        final r = await submitFn(result, token);
        final ok = r['synced'] as bool? ?? false;
        final permanent = r['permanent'] as bool? ?? false;
        if (ok) {
          await d.delete('queue', where: 'id = ?', whereArgs: [row['id']]);
          synced++;
        } else if (r['rejected'] == true) {
          await _holdRejected(d, 'queue', row, r['reject_reason']);
        } else if (permanent) {
          // Server permanently rejected payload — drop to avoid endless retry
          await d.delete('queue', where: 'id = ?', whereArgs: [row['id']]);
          debugPrint(
              'OfflineQueue.flush: id=${row['id']} permanent error, dropping');
        } else {
          await d.update('queue', {'attempts': (row['attempts'] as int) + 1},
              where: 'id = ?', whereArgs: [row['id']]);
          // 429 / 503 with Retry-After: the server asked us to wait, so the
          // remaining rows would only be refused too.
          if (_noteRetryAfter(r)) break;
        }
      } catch (e) {
        debugPrint('OfflineQueue.flush error (id=${row['id']}): $e');
      }
    }
    _changed();
    return synced;
  }

  /// Moves a row the server rejected into `rejected_results` (one
  /// transaction: it is never in neither table). The payload stays encrypted.
  static Future<void> _holdRejected(
      Database d, String source, Map<String, Object?> row, Object? reason) {
    debugPrint('OfflineQueue: id=${row['id']} ($source) rejected by the '
        'server ($reason), kept for the teacher');
    return d.transaction((txn) async {
      await txn.insert('rejected_results', {
        'source': source,
        'payload': row['payload'],
        'token': row['token'],
        'created': row['created'],
        'attempts': (row['attempts'] as int? ?? 0) + 1,
        'reason': reason?.toString() ?? 'conflict',
        'rejected_at': DateTime.now().millisecondsSinceEpoch,
      });
      await txn.delete(source, where: 'id = ?', whereArgs: [row['id']]);
    });
  }

  static Future<int> rejectedCount() async {
    final d = await db;
    final res = await d.rawQuery('SELECT COUNT(*) as c FROM rejected_results');
    return (res.first['c'] as int?) ?? 0;
  }

  /// The teacher acted (e.g. the panel granted another attempt): put every
  /// rejected result back into its queue under the SAME idempotency token, so
  /// the next flush submits it again. Returns how many moved.
  static Future<int> requeueRejected() async {
    final d = await db;
    final moved = await d.transaction((txn) async {
      final rows = await txn.query('rejected_results', orderBy: 'id ASC');
      for (final r in rows) {
        await txn.insert(
          r['source'] == 'local_queue' ? 'local_queue' : 'queue',
          {
            'payload': r['payload'],
            'created': r['created'],
            'attempts': 0,
            'token': r['token'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await txn.delete('rejected_results');
      return rows.length;
    });
    if (moved > 0) _changed();
    return moved;
  }

  /// Records a `retry_after_s` hint of a submit reply; true = stop flushing.
  static bool _noteRetryAfter(Map<String, dynamic> reply) {
    final ra = reply['retry_after_s'];
    if (ra is! num || ra <= 0) return false;
    ServerBackoff.note(Duration(seconds: ra.toInt()));
    return true;
  }

  static Future<int> pendingCount() async {
    final d = await db;
    final res = await d.rawQuery('SELECT COUNT(*) as c FROM queue');
    return (res.first['c'] as int?) ?? 0;
  }

  // ── Local Result Offline Queue ──────────────────────────────────────────────
  static Future<void> enqueueLocal(
      Map<String, dynamic> payload, String token) async {
    final d = await db;
    await d.insert(
      'local_queue',
      {
        'payload': await QueueCrypto.encryptPayload(jsonEncode(payload)),
        'created': DateTime.now().millisecondsSinceEpoch,
        'attempts': 0,
        'token': token,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _changed();
  }

  static Future<int> flushLocal(
      Future<Map<String, dynamic>> Function(
              Map<String, dynamic> payload, String token)
          submitFn) async {
    final d = await db;
    final rows = await d.query('local_queue', orderBy: 'created ASC');
    int synced = 0;
    for (final row in rows) {
      try {
        final json = jsonDecode(
            await QueueCrypto.decryptPayload(row['payload'] as String));
        final token = (row['token'] as String?) ?? newIdempotencyToken();
        final r = await submitFn(json, token);
        final ok = r['synced'] as bool? ?? false;
        final permanent = r['permanent'] as bool? ?? false;
        if (r['rejected'] == true) {
          await _holdRejected(d, 'local_queue', row, r['reject_reason']);
        } else if (ok || permanent) {
          await d
              .delete('local_queue', where: 'id = ?', whereArgs: [row['id']]);
          if (ok) synced++;
          if (permanent) {
            debugPrint(
                'OfflineQueue.flushLocal: id=${row['id']} permanent error, dropping');
          }
        } else {
          await d.update(
              'local_queue', {'attempts': (row['attempts'] as int) + 1},
              where: 'id = ?', whereArgs: [row['id']]);
          if (_noteRetryAfter(r)) break;
        }
      } catch (e) {
        debugPrint('OfflineQueue.flushLocal error (id=${row['id']}): $e');
      }
    }
    _changed();
    return synced;
  }

  /// How many rows the last [peekLocalQueue] could not decrypt (skipped, not
  /// removed) - lets the export tell the operator that results are missing.
  static int lastPeekUnreadable = 0;

  /// Read-only snapshot of every not-yet-flushed `local_queue` row,
  /// decrypted — NEVER deletes, updates attempts, or races the background
  /// auto-flush (unlike [flushLocal]). Used by DiagnosticExportService to
  /// self-score a still-pending diagnostic attempt for the offline ZIP
  /// export, export-time-only — never during normal app operation.
  static Future<List<Map<String, dynamic>>> peekLocalQueue() async {
    final d = await db;
    final rows = await d.query('local_queue', orderBy: 'created ASC');
    final result = <Map<String, dynamic>>[];
    lastPeekUnreadable = 0;
    for (final row in rows) {
      try {
        final json = jsonDecode(
            await QueueCrypto.decryptPayload(row['payload'] as String));
        if (json is Map) result.add(Map<String, dynamic>.from(json));
      } catch (e) {
        // Skipped, never deleted: the row stays queued for the real flush.
        lastPeekUnreadable++;
        debugPrint(
            'OfflineQueue.peekLocalQueue decrypt error (id=${row['id']}): $e');
      }
    }
    return result;
  }

  static Future<int> pendingLocalCount() async {
    final d = await db;
    final res = await d.rawQuery('SELECT COUNT(*) as c FROM local_queue');
    return (res.first['c'] as int?) ?? 0;
  }

  /// Age of the oldest result still waiting in either queue (null = none):
  /// the teacher chip says how long a result has been stuck.
  static Future<Duration?> oldestPendingAge({int? nowMs}) async {
    final d = await db;
    final rows = await Future.wait([
      d.rawQuery('SELECT MIN(created) AS m FROM queue'),
      d.rawQuery('SELECT MIN(created) AS m FROM local_queue'),
    ]);
    int? oldest;
    for (final r in rows) {
      final m = r.first['m'] as int?;
      if (m != null && (oldest == null || m < oldest)) oldest = m;
    }
    if (oldest == null) return null;
    final age = (nowMs ?? DateTime.now().millisecondsSinceEpoch) - oldest;
    return Duration(milliseconds: age < 0 ? 0 : age);
  }

  /// Combined queue + local_queue pending count, run concurrently (see
  /// SyncService._flushAll and SyncStatusBadge._refreshPending, the two
  /// former call sites that used to compute this separately/sequentially).
  static Future<int> totalPendingCount() async {
    final total = await _countAll();
    // SyncService polls this every few seconds: keep [pending] in step with
    // what it sees (e.g. the queue left over from the previous run).
    if (total != pending.value.count) unawaited(refreshPending());
    return total;
  }

  static Future<int> _countAll() async {
    final counts = await Future.wait([pendingCount(), pendingLocalCount()]);
    return counts[0] + counts[1];
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────
  // Result rows (queue / local_queue) are NEVER deleted by age or by attempt
  // count: only a server receipt or a permanent rejection removes them (see
  // flush). `created` is the PC wall clock, which a dead-CMOS reset (2000), an
  // NTP step or a manual change makes meaningless, and an age rule on it wiped
  // finished exams right after a failed flush. A result row is a few KB; keeping
  // an undeliverable one is cheaper than losing a child's exam. The attempts
  // column is still incremented, for diagnostics only.
  static const int _maxAgeMs = 7 * 24 * 60 * 60 * 1000; // 7 kun

  /// Eski qatorlarni tozalaydi. Natija qatorlari (queue, local_queue)
  /// HECH QACHON yosh yoki urinishlar soni bo'yicha o'chirilmaydi — faqat
  /// server tasdig'i yoki doimiy rad etish (flush) ularni olib tashlaydi.
  /// tg_queue va local_students 7 kun qoidasida qoladi.
  /// Qaytaradi: o'chirilgan jami qatorlar soni.
  static Future<int> purgeStale({int? nowMs}) async {
    final d = await db;
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _maxAgeMs;
    int removed = 0;
    // legacy tg_queue: attempts ustuni yo'q — faqat yosh bo'yicha
    removed +=
        await d.delete('tg_queue', where: 'created < ?', whereArgs: [cutoff]);
    removed += await LocalStudentsDb.purgeStale(nowMs: now);
    if (removed > 0) {
      debugPrint(
          'OfflineQueue.purgeStale: $removed eski qator o\'chirildi');
      _changed();
    }
    return removed;
  }
}
