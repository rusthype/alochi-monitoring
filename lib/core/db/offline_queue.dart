// lib/core/db/offline_queue.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../api/api_client.dart';

class OfflineQueue {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final path = join(dir.path, 'monitoring_queue.db');
    _db = await openDatabase(path, version: 4, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE queue (
          id       INTEGER PRIMARY KEY AUTOINCREMENT,
          payload  TEXT NOT NULL,
          created  INTEGER NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        CREATE TABLE tg_queue (
          id       INTEGER PRIMARY KEY AUTOINCREMENT,
          msg      TEXT NOT NULL,
          created  INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE local_queue (
          id       INTEGER PRIMARY KEY AUTOINCREMENT,
          payload  TEXT NOT NULL,
          created  INTEGER NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          token    TEXT
        )
      ''');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute('''
          CREATE TABLE tg_queue (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            msg      TEXT NOT NULL,
            created  INTEGER NOT NULL
          )
        ''');
      }
      if (oldVersion < 3) {
        await db.execute('''
          CREATE TABLE local_queue (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            payload  TEXT NOT NULL,
            created  INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0
          )
        ''');
      }
      if (oldVersion < 4) {
        await db.execute('ALTER TABLE local_queue ADD COLUMN token TEXT');
      }
    });
    return _db!;
  }

  static Future<void> enqueue(TestResult result) async {
    final d = await db;
    await d.insert('queue', {
      'payload': jsonEncode(result.toJson()),
      'created': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    });
  }

  static Future<int> flush(
      Future<Map<String, dynamic>> Function(TestResult) submitFn) async {
    final d = await db;
    final rows = await d.query('queue', orderBy: 'created ASC');
    int synced = 0;
    for (final row in rows) {
      try {
        final json = jsonDecode(row['payload'] as String);
        final result = TestResult(
          packageId: json['package_id'],
          variant: json['variant'],
          mathScore: json['math_score'],
          engScore: json['eng_score'],
          totalPct: json['total_pct'],
          answers: Map<String, String>.from(json['answers'] ?? {}),
          deviceId: json['device_id'] ?? 'offline',
        );
        final r = await submitFn(result);
        final ok = r['synced'] as bool? ?? false;
        final permanent = r['permanent'] as bool? ?? false;
        if (ok) {
          await d.delete('queue', where: 'id = ?', whereArgs: [row['id']]);
          synced++;
        } else if (permanent) {
          // Server permanently rejected payload — drop to avoid endless retry
          await d.delete('queue', where: 'id = ?', whereArgs: [row['id']]);
          debugPrint('OfflineQueue.flush: id=${row['id']} permanent error, dropping');
        } else {
          await d.update('queue', {'attempts': (row['attempts'] as int) + 1},
              where: 'id = ?', whereArgs: [row['id']]);
        }
      } catch (e) {
        debugPrint('OfflineQueue.flush error (id=${row['id']}): $e');
      }
    }
    return synced;
  }

  static Future<int> pendingCount() async {
    final d = await db;
    final res = await d.rawQuery('SELECT COUNT(*) as c FROM queue');
    return (res.first['c'] as int?) ?? 0;
  }

  // ── Local Result Offline Queue ──────────────────────────────────────────────
  static Future<void> enqueueLocal(Map<String, dynamic> payload, String token) async {
    final d = await db;
    await d.insert('local_queue', {
      'payload': jsonEncode(payload),
      'created': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
      'token': token,
    });
  }

  static Future<int> flushLocal(Future<bool> Function(Map<String, dynamic> payload, String token) submitFn) async {
    final d = await db;
    final rows = await d.query('local_queue', orderBy: 'created ASC');
    int synced = 0;
    for (final row in rows) {
      try {
        final json = jsonDecode(row['payload'] as String);
        final token = (row['token'] as String?) ?? newIdempotencyToken();
        final ok = await submitFn(json, token);
        if (ok) {
          await d.delete('local_queue', where: 'id = ?', whereArgs: [row['id']]);
          synced++;
        } else {
          await d.update('local_queue', {'attempts': (row['attempts'] as int) + 1},
              where: 'id = ?', whereArgs: [row['id']]);
        }
      } catch (e) {
        debugPrint('OfflineQueue.flushLocal error (id=${row['id']}): $e');
      }
    }
    return synced;
  }

  static Future<int> pendingLocalCount() async {
    final d = await db;
    final res = await d.rawQuery('SELECT COUNT(*) as c FROM local_queue');
    return (res.first['c'] as int?) ?? 0;
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────
  static const int _maxAttempts = 10;
  static const int _maxAgeMs = 7 * 24 * 60 * 60 * 1000; // 7 kun

  /// "O'lik" qatorlarni tozalaydi: attempts >= 10 YOKI 7 kundan eski.
  /// Muvaffaqiyatli yuborilgan qatorlar flush paytida allaqachon o'chiriladi —
  /// bu faqat doimiy xato beradigan yoki juda eski yig'ilib qolganlar uchun.
  /// Qaytaradi: o'chirilgan jami qatorlar soni.
  static Future<int> purgeStale() async {
    final d = await db;
    final cutoff = DateTime.now().millisecondsSinceEpoch - _maxAgeMs;
    int removed = 0;
    // queue va local_queue: attempts + created ustunlari bor
    for (final table in ['queue', 'local_queue']) {
      removed += await d.delete(table,
          where: 'attempts >= ? OR created < ?',
          whereArgs: [_maxAttempts, cutoff]);
    }
    // legacy tg_queue: attempts ustuni yo'q — faqat yosh bo'yicha
    removed += await d.delete('tg_queue', where: 'created < ?', whereArgs: [cutoff]);
    if (removed > 0) debugPrint('OfflineQueue.purgeStale: $removed eski/o\'lik qator o\'chirildi');
    return removed;
  }

  // ── Telegram Offline Queue ──────────────────────────────────────────────────
  // LEGACY: faqat eski yig'ilib qolgan TG xabarlarini drenajlash uchun. Yangi kod ishlatmaydi — keyingi relizda olib tashlanadi.
  static Future<void> enqueueTg(String msg) async {
    final d = await db;
    await d.insert('tg_queue', {
      'msg': msg,
      'created': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<int> flushTg(String botToken, List<int> adminIds) async {
    final d = await db;
    final rows = await d.query('tg_queue', orderBy: 'created ASC');
    int synced = 0;
    for (final row in rows) {
      try {
        final msg = row['msg'] as String;
        bool allSent = true;
        for (final id in adminIds) {
          final r = await http.post(
            Uri.parse('https://api.telegram.org/bot$botToken/sendMessage'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'chat_id': id, 'text': msg, 'parse_mode': 'HTML'}),
          );
          if (r.statusCode != 200) allSent = false;
        }
        if (allSent) {
          await d.delete('tg_queue', where: 'id = ?', whereArgs: [row['id']]);
          synced++;
        }
      } catch (e) {
        debugPrint('OfflineQueue.flushTg error (id=${row['id']}): $e');
      }
    }
    return synced;
  }
}
