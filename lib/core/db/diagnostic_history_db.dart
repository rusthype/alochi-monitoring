// lib/core/db/diagnostic_history_db.dart
//
// Local per-ATTEMPT history for the diagnostic kiosk flow — separate table
// and file from HistoryDb (monitoring's per-subject-finish history) on
// purpose: HistoryDb's schema/table and its 5 existing callers
// (local_result_screen.dart, engine_host_screen.dart, unit1_runner.dart,
// interhouse_result_screen.dart, combined_runner.dart) are locked and must
// not change. One row per diagnostic attempt (not per subject-finish),
// upserted by attempt_id: Math finishing writes/updates math_score+status,
// English finishing writes/updates english_score+status on the SAME row.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DiagnosticHistoryDb {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final path = join(dir.path, 'diagnostic_history.db');
    _db = await openDatabase(path, version: 1, onCreate: _create);
    return _db!;
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE diagnostic_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        attempt_id TEXT UNIQUE,
        student_name TEXT,
        class_label TEXT,
        school TEXT,
        math_score INTEGER,
        english_score INTEGER,
        status TEXT,
        date_taken INTEGER
      )
    ''');
  }

  @visibleForTesting
  static Future<void> openInMemory() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // singleInstance: false — sqflite otherwise caches/reuses ONE connection
    // per path, and `inMemoryDatabasePath` is the same literal path every
    // call, so a second test's openInMemory() would silently hand back the
    // FIRST test's still-open (and still-populated) in-memory db instead of
    // a fresh one.
    _db = await openDatabase(inMemoryDatabasePath,
        version: 1, onCreate: _create, singleInstance: false);
  }

  @visibleForTesting
  static Future<void> reset() async {
    await _db?.close();
    _db = null;
  }

  /// Upserts by `attempt_id`. A null score arg leaves that column
  /// untouched (not blanked) — English finishing must not erase an
  /// already-recorded Math score, and vice versa.
  static Future<void> upsert({
    required String attemptId,
    required String studentName,
    required String classLabel,
    required String school,
    required String status,
    int? mathScore,
    int? englishScore,
  }) async {
    final d = await db;
    final existing = await d.query('diagnostic_history',
        where: 'attempt_id = ?', whereArgs: [attemptId], limit: 1);
    if (existing.isEmpty) {
      await d.insert('diagnostic_history', {
        'attempt_id': attemptId,
        'student_name': studentName,
        'class_label': classLabel,
        'school': school,
        'math_score': mathScore,
        'english_score': englishScore,
        'status': status,
        'date_taken': DateTime.now().millisecondsSinceEpoch,
      });
      return;
    }
    final row = existing.first;
    await d.update(
      'diagnostic_history',
      {
        'student_name': studentName,
        'class_label': classLabel,
        'school': school,
        'math_score': mathScore ?? row['math_score'],
        'english_score': englishScore ?? row['english_score'],
        'status': status,
      },
      where: 'attempt_id = ?',
      whereArgs: [attemptId],
    );
  }

  /// Flips a row's status to `'sent'` and backfills score fields when the
  /// offline-queue replay for this attempt finally succeeds (the single
  /// central replay point: api_client.dart's `_dispatchLocalQueueItem`).
  /// No-op if the row doesn't exist (e.g. the DB was cleared/reinstalled
  /// between the original pending-write and this replay).
  static Future<void> markSent({
    required String attemptId,
    int? mathScore,
    int? englishScore,
  }) async {
    final d = await db;
    final existing = await d.query('diagnostic_history',
        where: 'attempt_id = ?', whereArgs: [attemptId], limit: 1);
    if (existing.isEmpty) return;
    final row = existing.first;
    await d.update(
      'diagnostic_history',
      {
        'status': 'sent',
        'math_score': mathScore ?? row['math_score'],
        'english_score': englishScore ?? row['english_score'],
      },
      where: 'attempt_id = ?',
      whereArgs: [attemptId],
    );
  }

  /// Epoch-ms of local midnight for "today" — an actual calendar-day
  /// boundary, not a rolling 24h window, so a kiosk operator's mental model
  /// of "today's tests" matches what's shown regardless of what hour the
  /// screen happens to be opened.
  static int _startOfTodayEpochMs() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
  }

  /// Deletes every row from a previous calendar day. This kiosk is reused
  /// across many days/schools — without an actual DELETE, the table would
  /// grow unbounded and stale rows would keep accumulating even though
  /// `getAll()`'s query-time filter already hides them. Returns the number
  /// of rows removed.
  static Future<int> purgeOldEntries() async {
    final d = await db;
    return d.delete('diagnostic_history',
        where: 'date_taken < ?', whereArgs: [_startOfTodayEpochMs()]);
  }

  /// Only today's rows (local device time, midnight-to-midnight) — a
  /// different day's kiosk session must never visually mix into this list.
  /// Purges stale rows first (see `purgeOldEntries`) so the table doesn't
  /// grow forever, then applies the same "today" boundary at query time as
  /// a second, independent guard.
  static Future<List<Map<String, dynamic>>> getAll() async {
    final d = await db;
    await purgeOldEntries();
    return d.query(
      'diagnostic_history',
      where: 'date_taken >= ?',
      whereArgs: [_startOfTodayEpochMs()],
      orderBy: 'date_taken DESC',
    );
  }
}
