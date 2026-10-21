// lib/core/db/pack_local_students_db.dart
//
// Children a proctor added while an offline `.alochipack` was open ("Bola
// qo'shish", add-student wave 2). The pack roster is signed and fixed, so these
// kids live ONLY here (and, once they finish a test, inside that result's
// `new_student` block in the HMAC chain). Keyed by pack uuid so a restart or a
// re-open of the same pack brings them back; a different pack never sees them.
//
// The row body (names, birth date, parent F.I.O.) is encrypted at rest like the
// chain's payloads (QueueCrypto). Each insert is its own sqlite statement, so a
// crash leaves either the whole child or none.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'offline_queue.dart';
import 'queue_crypto.dart';

class PackLocalStudent {
  /// `new:<uuid>` — the `client_temp_id`, also the result's `student_id`.
  final String tempId;
  final String groupId;
  final String firstName;
  final String lastName;
  final DateTime? birthDate;
  final String parentFio;
  final int grade;

  /// 'uz' / 'ru' / '' (diagnostic test language; local only, not in the chain).
  final String language;

  const PackLocalStudent({
    required this.tempId,
    required this.groupId,
    required this.firstName,
    required this.lastName,
    this.birthDate,
    this.parentFio = '',
    this.grade = 0,
    this.language = '',
  });

  String get name => '$lastName $firstName'.trim();

  static String? _date(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The chain entry's `new_student` block (contract "Offline (pack) path").
  Map<String, dynamic> toNewStudentBlock() => {
        'temp_id': tempId,
        'first_name': firstName,
        'last_name': lastName,
        if (birthDate != null) 'birth_date': _date(birthDate),
        if (parentFio.isNotEmpty) 'parent_fio': parentFio,
        'group_id': groupId,
      };

  /// Roster-shaped row (monitoring `fetchStudents` / the shared
  /// [OfflineContentSource.localStudents] view), flagged pending + local.
  Map<String, dynamic> toRosterRow() => {
        'id': tempId,
        'name': name,
        'code': '',
        'first_name': firstName,
        'last_name': lastName,
        if (birthDate != null) 'birth_date': _date(birthDate),
        if (parentFio.isNotEmpty) 'parent_fio': parentFio,
        'group_id': groupId,
        'grade': grade,
        if (language.isNotEmpty) 'language': language,
        'pending': true,
        'local_pending': true,
      };

  String _toBlob() => jsonEncode({
        'first_name': firstName,
        'last_name': lastName,
        if (birthDate != null) 'birth_date': _date(birthDate),
        'parent_fio': parentFio,
        'grade': grade,
        'language': language,
      });

  static PackLocalStudent? _fromRow(
      String tempId, String groupId, String blob) {
    try {
      final m = jsonDecode(blob);
      if (m is! Map) return null;
      return PackLocalStudent(
        tempId: tempId,
        groupId: groupId,
        firstName: m['first_name']?.toString() ?? '',
        lastName: m['last_name']?.toString() ?? '',
        birthDate: DateTime.tryParse(m['birth_date']?.toString() ?? ''),
        parentFio: m['parent_fio']?.toString() ?? '',
        grade: (m['grade'] as num?)?.toInt() ?? 0,
        language: m['language']?.toString() ?? '',
      );
    } catch (e) {
      debugPrint('PackLocalStudent: unreadable row $tempId: $e');
      return null;
    }
  }
}

class PackLocalStudentsDb {
  PackLocalStudentsDb._();

  static Future<Database> get _db => OfflineQueue.db;

  /// Idempotent (IF NOT EXISTS), created by `OfflineQueue.ensureSchema` on every
  /// open, so no schema-version bump is needed.
  static Future<void> createTable(Database db) => db.execute('''
      CREATE TABLE IF NOT EXISTS pack_local_students (
        pack_uuid TEXT NOT NULL,
        temp_id   TEXT NOT NULL,
        group_id  TEXT NOT NULL,
        created   INTEGER NOT NULL,
        data      TEXT NOT NULL,
        PRIMARY KEY (pack_uuid, temp_id)
      )
    ''');

  /// Stores [s] for [packUuid]; a repeat of the same temp id is a no-op (the
  /// dialog reuses one temp id per add, so a retry cannot create a twin).
  static Future<void> add(String packUuid, PackLocalStudent s,
      {int? nowMs}) async {
    final d = await _db;
    await d.insert(
      'pack_local_students',
      {
        'pack_uuid': packUuid,
        'temp_id': s.tempId,
        'group_id': s.groupId,
        'created': nowMs ?? DateTime.now().millisecondsSinceEpoch,
        'data': await QueueCrypto.encryptPayload(s._toBlob()),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Every child added to [packUuid], oldest first.
  static Future<List<PackLocalStudent>> forPack(String packUuid) async {
    final d = await _db;
    final rows = await d.query('pack_local_students',
        where: 'pack_uuid = ?', whereArgs: [packUuid], orderBy: 'created ASC');
    final out = <PackLocalStudent>[];
    for (final r in rows) {
      final plain = await QueueCrypto.decryptPayload(r['data'] as String);
      final s = PackLocalStudent._fromRow(
          r['temp_id'] as String, r['group_id'] as String, plain);
      if (s != null) out.add(s);
    }
    return out;
  }

  /// Drops a pack's children (called when its `pack_meta` is purged).
  static Future<void> deleteForPack(String packUuid) async {
    final d = await _db;
    await d.delete('pack_local_students',
        where: 'pack_uuid = ?', whereArgs: [packUuid]);
  }
}
