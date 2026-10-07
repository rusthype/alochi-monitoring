// lib/core/db/diagnostic_answer_store.dart
//
// Fixed-variant (2-5 sinf) diagnostika kiosk oqimi uchun bardoshli
// mahalliy javob saqlash. diagnostic_history.db (attempt bo'yicha
// xulosaviy qator) va offline_queue.dart'ning queue/local_queue'sidan
// (butun-payload submit-yoki-tashla outbox'i) ataylab alohida sqflite
// fayl/jadval: bu jadvalning vazifasi darhol har-bosishda halokatdan
// tiklanish VA SyncService'ning mavjud 60s flush'iga hali serverga
// yetib bormagan narsani berish — ikkala mavjud do'konning shakli/hayot
// sikli ham bunga to'g'ri kelmaydi.
//
// Jadval nomi ATAYLAB backend'ning `diagnostic_answers` Postgres jadvali
// (apps.diagnostic.models.DiagnosticAnswer) bilan mos kelmaydi — bular
// butunlay ikki xil ma'lumotlar bazasi; farqli nom ikkalasini kod/logda
// chalkashtirmaslik uchun.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DiagnosticAnswerStore {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final path = join(dir.path, 'diagnostic_answer_progress.db');
    _db = await openDatabase(path,
        version: 2, onCreate: _create, onUpgrade: upgrade);
    return _db!;
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE local_diagnostic_answers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        attempt_id TEXT NOT NULL,
        subject TEXT NOT NULL,
        question_index INTEGER NOT NULL,
        question_id TEXT NOT NULL,
        selected_option TEXT NOT NULL,
        answered_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0,
        generation INTEGER
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_local_diag_answers_attempt_question '
      'ON local_diagnostic_answers(attempt_id, question_id)',
    );
  }

  /// v2: `generation` — the attempt's `attempts_used` at the time the row was
  /// written, so a flush can tell the server which reset-generation the row
  /// belongs to (NULL = legacy row / old backend, sent without a generation).
  @visibleForTesting
  static Future<void> upgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE local_diagnostic_answers ADD COLUMN generation INTEGER');
    }
  }

  @visibleForTesting
  static Future<void> openInMemory() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // singleInstance: false — DiagnosticHistoryDb.openInMemory'ning izohiga
    // qarang: aks holda sqflite har doim BIRINCHI test'ning hali ochiq,
    // hali to'ldirilgan xotiradagi bazasini keyingi testlarga qaytaradi.
    _db = await openDatabase(inMemoryDatabasePath,
        version: 2,
        onCreate: _create,
        onUpgrade: upgrade,
        singleInstance: false);
  }

  @visibleForTesting
  static Future<void> reset() async {
    await _db?.close();
    _db = null;
  }

  /// Darhol halokatdan-tiklanish yozuvi — har javob bosilganda chaqiriladi.
  /// (attempt_id, question_id) bo'yicha upsert qiladi: allaqachon
  /// javob berilgan savolni o'zgartirish dublikat qator to'plash o'rniga
  /// joyida almashtiradi, va qatorni yana sinxronlanmagan deb belgilaydi —
  /// shuning uchun o'zgarish keyingi flush'da haqiqatan serverga yetadi.
  static Future<void> saveAnswer({
    required String attemptId,
    required String subject,
    required int questionIndex,
    required String questionId,
    required String selectedOption,
    int? generation,
  }) async {
    final d = await db;
    await d.insert(
      'local_diagnostic_answers',
      {
        'attempt_id': attemptId,
        'subject': subject,
        'question_index': questionIndex,
        'question_id': questionId,
        'selected_option': selectedOption,
        'answered_at': DateTime.now().millisecondsSinceEpoch,
        'synced': 0,
        'generation': generation,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Server `saved_answers` (`{question_id: selected_option}`) dan lokal
  /// qatorlarni to'ldiradi — allaqachon lokal qator bor savolga TEGMAYDI
  /// (lokal yutadi, unique index + `ignore`). Qatorlar `synced = 1` bilan
  /// yoziladi: server allaqachon biladi, qayta yuklanmaydi.
  /// `question_index` [orderedQuestionIds] tartibidan (1-based) tiklanadi;
  /// ro'yxatda yo'q question_id o'tkazib yuboriladi.
  static Future<void> seedSynced({
    required String attemptId,
    required String subject,
    required Map<String, String> saved,
    required List<String> orderedQuestionIds,
    int? generation,
  }) async {
    if (saved.isEmpty) return;
    final d = await db;
    final batch = d.batch();
    for (final e in saved.entries) {
      final i = orderedQuestionIds.indexOf(e.key);
      if (i < 0) continue;
      batch.insert(
        'local_diagnostic_answers',
        {
          'attempt_id': attemptId,
          'subject': subject,
          'question_index': i + 1,
          'question_id': e.key,
          'selected_option': e.value,
          'answered_at': DateTime.now().millisecondsSinceEpoch,
          'synced': 1,
          'generation': generation,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// [attemptId] uchun [subject]ga cheklangan barcha qatorlar, savol
  /// tartibida. Ataylab subject bo'yicha cheklangan: `question_index`
  /// har subject uchun qayta ishlatiladi (Matematika 1-30, keyin xuddi shu
  /// attempt_id uchun Ingliz tili 1-30), demak cheklanmagan o'qish ikki
  /// subject'ning qatorlarini bir xil index'ga to'qnashtirib qo'yardi.
  static Future<List<Map<String, dynamic>>> loadAll(
    String attemptId, {
    required String subject,
  }) async {
    final d = await db;
    return d.query(
      'local_diagnostic_answers',
      where: 'attempt_id = ? AND subject = ?',
      whereArgs: [attemptId, subject],
      orderBy: 'question_index ASC',
    );
  }

  /// [attemptId] uchun (istalgan subject) hali sinxronlanmagan barcha
  /// qatorlar, eskisi birinchi — SyncService'ning flush'i to'g'ridan-to'g'ri
  /// `kiosk/sync/`ga shu shaklda yuboradi.
  static Future<List<Map<String, dynamic>>> pendingForAttempt(
      String attemptId) async {
    final d = await db;
    return d.query(
      'local_diagnostic_answers',
      where: 'attempt_id = ? AND synced = 0',
      whereArgs: [attemptId],
      orderBy: 'question_index ASC',
    );
  }

  /// Kamida bitta sinxronlanmagan qatorga ega har bir attempt_id — flush
  /// tsikliga chaqiruvchi oldindan kuzatmagan attemptlarni topish imkonini
  /// beradi.
  static Future<List<String>> attemptsWithPending() async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT DISTINCT attempt_id FROM local_diagnostic_answers WHERE synced = 0',
    );
    return rows.map((r) => r['attempt_id'] as String).toList();
  }

  static Future<void> markSynced(
      String attemptId, List<String> questionIds) async {
    if (questionIds.isEmpty) return;
    final d = await db;
    final placeholders = List.filled(questionIds.length, '?').join(',');
    await d.rawUpdate(
      'UPDATE local_diagnostic_answers SET synced = 1 '
      'WHERE attempt_id = ? AND question_id IN ($placeholders)',
      [attemptId, ...questionIds],
    );
  }

  /// Server `stale_generation` (409) dedi: shu [generation]dagi qatorlar
  /// reset qilingan attempt'ga tegishli — o'chiriladi (yangi generation
  /// qatorlari saqlanadi).
  static Future<void> clearGeneration(String attemptId, int? generation) async {
    final d = await db;
    await d.delete('local_diagnostic_answers',
        where: generation == null
            ? 'attempt_id = ? AND generation IS NULL'
            : 'attempt_id = ? AND generation = ?',
        whereArgs: generation == null ? [attemptId] : [attemptId, generation]);
  }

  /// [attemptId] uchun (ikkala subject) barcha qatorlarni tozalaydi —
  /// butun attempt yakunlanganda chaqiriladi (qarang:
  /// DiagnosticTestRunnerScreen._finishTest), AttemptStore.clear'ning xuddi
  /// shu voqea uchun tozalashini aks ettiradi.
  static Future<void> clearAttempt(String attemptId) async {
    final d = await db;
    await d.delete('local_diagnostic_answers',
        where: 'attempt_id = ?', whereArgs: [attemptId]);
  }

  /// Deletes ONLY already-synced rows (all attempts) — safe session-handoff
  /// cleanup. Unsynced answers are never touched: they are the only copy
  /// until SyncService uploads them.
  static Future<void> clearSynced() async {
    final d = await db;
    await d.delete('local_diagnostic_answers', where: 'synced = 1');
  }
}
