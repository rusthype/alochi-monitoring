// lib/core/db/local_students_db.dart
//
// Children a proctor added while the server could not be reached (schema v9).
// The authoritative copy of the request (incl. birth date / parent F.I.O.) is
// the encrypted `local_queue` row tagged `_offlineKind: 'add_student'`; this
// table only keeps what the roster needs to keep the child usable meanwhile
// (names are the same ones already shown on screen) plus the temp -> server id
// mapping that lets queued results be re-pointed once the add is accepted.
//
// `temp_id` is the `client_temp_id` (`new:<uuid>`). Wave-2 offline packs reuse
// the very same id as `student_id` in the pack chain entry (+ `new_student`
// block), so a child added offline in a pack and one added here share a scheme.
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'offline_queue.dart';

class LocalStudent {
  final String tempId;
  final String groupId;
  final String firstName;
  final String lastName;
  final int grade;
  final String language;

  /// Server id once the queued add was accepted; null while still local.
  final String? serverId;

  const LocalStudent({
    required this.tempId,
    required this.groupId,
    required this.firstName,
    required this.lastName,
    this.grade = 0,
    this.language = '',
    this.serverId,
  });

  String get name => '$lastName $firstName'.trim();

  /// A `fetchStudents`-shaped roster row, flagged pending + local.
  Map<String, dynamic> toRosterRow() => {
        'id': tempId,
        'name': name,
        'first_name': firstName,
        'last_name': lastName,
        'grade': grade,
        'pending': true,
        'local_pending': true,
      };
}

class LocalStudentsDb {
  LocalStudentsDb._();

  static const _maxAgeMs = 7 * 24 * 60 * 60 * 1000; // same as the queue purge

  static Future<Database> get _db => OfflineQueue.db;

  /// v9 table. Idempotent (IF NOT EXISTS), like every other create*Tables.
  static Future<void> createTable(Database db) => db.execute('''
      CREATE TABLE IF NOT EXISTS local_students (
        temp_id    TEXT PRIMARY KEY,
        group_id   TEXT NOT NULL,
        first_name TEXT NOT NULL,
        last_name  TEXT NOT NULL,
        grade      INTEGER NOT NULL DEFAULT 0,
        language   TEXT NOT NULL DEFAULT '',
        created    INTEGER NOT NULL,
        server_id  TEXT
      )
    ''');

  static Future<void> add(LocalStudent s, {int? nowMs}) async {
    final d = await _db;
    await d.insert(
      'local_students',
      {
        'temp_id': s.tempId,
        'group_id': s.groupId,
        'first_name': s.firstName,
        'last_name': s.lastName,
        'grade': s.grade,
        'language': s.language,
        'created': nowMs ?? DateTime.now().millisecondsSinceEpoch,
        'server_id': s.serverId,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Still-local children of [groupId] (not yet accepted by the server — an
  /// accepted one comes back from the server roster itself).
  static Future<List<LocalStudent>> unsyncedForGroup(String groupId) async {
    final d = await _db;
    final rows = await d.query('local_students',
        where: 'group_id = ? AND server_id IS NULL',
        whereArgs: [groupId],
        orderBy: 'created ASC');
    return rows.map(_fromRow).toList();
  }

  /// Server id for [tempId] once its queued add was accepted, else null.
  static Future<String?> serverIdFor(String tempId) async {
    final d = await _db;
    final rows = await d.query('local_students',
        columns: ['server_id'],
        where: 'temp_id = ?',
        whereArgs: [tempId],
        limit: 1);
    if (rows.isEmpty) return null;
    final id = rows.first['server_id']?.toString() ?? '';
    return id.isEmpty ? null : id;
  }

  static Future<void> markSynced(String tempId, String serverId) async {
    final d = await _db;
    await d.update('local_students', {'server_id': serverId},
        where: 'temp_id = ?', whereArgs: [tempId]);
  }

  /// The queued add was permanently rejected: stop offering the child.
  static Future<void> remove(String tempId) async {
    final d = await _db;
    await d.delete('local_students', where: 'temp_id = ?', whereArgs: [tempId]);
  }

  /// Drops rows older than the queue's own 7-day horizon.
  static Future<int> purgeStale({int? nowMs}) async {
    final d = await _db;
    final cutoff = (nowMs ?? DateTime.now().millisecondsSinceEpoch) - _maxAgeMs;
    return d
        .delete('local_students', where: 'created < ?', whereArgs: [cutoff]);
  }

  /// Best-effort variant for UI paths: a missing/locked DB must never break
  /// the roster, but is logged instead of silently swallowed.
  static Future<List<LocalStudent>> unsyncedForGroupSafe(String groupId) async {
    try {
      return await unsyncedForGroup(groupId);
    } catch (e) {
      debugPrint('LocalStudentsDb.unsyncedForGroup error: $e');
      return const [];
    }
  }

  static LocalStudent _fromRow(Map<String, Object?> r) => LocalStudent(
        tempId: r['temp_id']?.toString() ?? '',
        groupId: r['group_id']?.toString() ?? '',
        firstName: r['first_name']?.toString() ?? '',
        lastName: r['last_name']?.toString() ?? '',
        grade: (r['grade'] as num?)?.toInt() ?? 0,
        language: r['language']?.toString() ?? '',
        serverId: (r['server_id']?.toString() ?? '').isEmpty
            ? null
            : r['server_id'].toString(),
      );
}
