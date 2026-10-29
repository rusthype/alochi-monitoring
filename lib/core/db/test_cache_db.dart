// lib/core/db/test_cache_db.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestCacheDb {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final path = join(dir.path, 'monitoring_test_cache.db');
    _db = await openDatabase(path, version: 1, onCreate: _create);
    return _db!;
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS test_cache (
        test_key      TEXT PRIMARY KEY,
        version       INTEGER NOT NULL,
        json          TEXT NOT NULL,
        downloaded_at INTEGER NOT NULL
      )
    ''');
  }

  @visibleForTesting
  static Future<void> openInMemory() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _db =
        await openDatabase(inMemoryDatabasePath, version: 1, onCreate: _create);
  }

  @visibleForTesting
  static void reset() => _db = null;

  static Future<void> put(
      String testKey, int version, Map<String, dynamic> data) async {
    final d = await db;
    await d.insert(
      'test_cache',
      {
        'test_key': testKey,
        'version': version,
        'json': jsonEncode(data),
        'downloaded_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> get(String testKey) async {
    final d = await db;
    final rows = await d.query(
      'test_cache',
      where: 'test_key = ?',
      whereArgs: [testKey],
    );
    if (rows.isEmpty) return null;
    // A row that does not decode to a JSON object is not a downloaded test:
    // drop it so the version check re-downloads instead of crashing the loader.
    try {
      final decoded = jsonDecode(rows.first['json'] as String);
      if (decoded is Map<String, dynamic>) return decoded;
      debugPrint('TestCacheDb.get($testKey): not a JSON object, dropping row');
    } catch (e) {
      debugPrint('TestCacheDb.get($testKey): corrupt row, dropping it: $e');
    }
    try {
      await d.delete('test_cache', where: 'test_key = ?', whereArgs: [testKey]);
    } catch (e) {
      debugPrint('TestCacheDb.get($testKey): could not drop bad row: $e');
    }
    return null;
  }

  static Future<int?> cachedVersion(String testKey) async {
    final d = await db;
    final rows = await d.query(
      'test_cache',
      columns: ['version'],
      where: 'test_key = ?',
      whereArgs: [testKey],
    );
    if (rows.isEmpty) return null;
    return rows.first['version'] as int?;
  }
}
