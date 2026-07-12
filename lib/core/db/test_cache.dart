// lib/core/db/test_cache.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Sqflite kesh — yuklab olingan test JSON'lari saqlanadi.
/// Jadval: cached_tests
class TestCache {
  static Database? _db;

  static Future<Database> get _database async {
    if (_db != null) return _db!;
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final path = join(dir.path, 'test_cache.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE cached_tests (
            test_key       TEXT PRIMARY KEY,
            title          TEXT NOT NULL,
            grade          INTEGER NOT NULL,
            version        INTEGER NOT NULL,
            json           TEXT NOT NULL,
            downloaded_at  INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  /// Yangi yoki yangilangan test ma'lumotini saqlaydi (upsert).
  static Future<void> upsert(
    String testKey,
    String title,
    int grade,
    int version,
    String jsonStr,
  ) async {
    final db = await _database;
    await db.insert(
      'cached_tests',
      {
        'test_key': testKey,
        'title': title,
        'grade': grade,
        'version': version,
        'json': jsonStr,
        'downloaded_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Bitta test yozuvini qaytaradi yoki null (topilmasa).
  /// json maydoni decode qilinib qaytariladi.
  static Future<Map<String, dynamic>?> get(String testKey) async {
    final db = await _database;
    final rows = await db.query(
      'cached_tests',
      where: 'test_key = ?',
      whereArgs: [testKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final jsonStr = row['json'] as String?;
    if (jsonStr == null || jsonStr.isEmpty) return null;
    try {
      final decoded = await compute(jsonDecode, jsonStr);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      debugPrint('TestCache.get($testKey) json decode error: $e');
      return null;
    }
  }

  /// Barcha keshlangan yozuvlar ro'yxatini qaytaradi (json maydonsiz — metadata).
  static Future<List<Map<String, dynamic>>> all() async {
    final db = await _database;
    final rows = await db.query(
      'cached_tests',
      columns: ['test_key', 'title', 'grade', 'version', 'downloaded_at'],
      orderBy: 'downloaded_at DESC',
    );
    if (rows.isEmpty) return [];
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  /// Berilgan test_key uchun saqlangan version raqamini qaytaradi yoki null.
  static Future<int?> versionOf(String testKey) async {
    final db = await _database;
    final rows = await db.query(
      'cached_tests',
      columns: ['version'],
      where: 'test_key = ?',
      whereArgs: [testKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final v = rows.first['version'];
    if (v == null) return null;
    return int.tryParse(v.toString());
  }
}
