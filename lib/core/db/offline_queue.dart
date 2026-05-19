// lib/core/db/offline_queue.dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/models.dart';

class OfflineQueue {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir  = await getApplicationSupportDirectory();
    final path = join(dir.path, 'monitoring_queue.db');
    _db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE queue (
          id       INTEGER PRIMARY KEY AUTOINCREMENT,
          payload  TEXT NOT NULL,
          created  INTEGER NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0
        )
      ''');
    });
    return _db!;
  }

  static Future<void> enqueue(TestResult result) async {
    final d = await db;
    await d.insert('queue', {
      'payload':  jsonEncode(result.toJson()),
      'created':  DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    });
  }

  static Future<int> flush(Future<bool> Function(TestResult) submitFn) async {
    final d    = await db;
    final rows = await d.query('queue', orderBy: 'created ASC');
    int synced = 0;
    for (final row in rows) {
      try {
        final json   = jsonDecode(row['payload'] as String);
        final result = TestResult(
          packageId: json['package_id'],
          variant:   json['variant'],
          mathScore: json['math_score'],
          engScore:  json['eng_score'],
          totalPct:  json['total_pct'],
          answers:   Map<String, String>.from(json['answers'] ?? {}),
          deviceId:  json['device_id'] ?? 'offline',
        );
        final ok = await submitFn(result);
        if (ok) {
          await d.delete('queue', where: 'id = ?', whereArgs: [row['id']]);
          synced++;
        } else {
          await d.update('queue', {'attempts': (row['attempts'] as int) + 1},
              where: 'id = ?', whereArgs: [row['id']]);
        }
      } catch (_) {}
    }
    return synced;
  }

  static Future<int> pendingCount() async {
    final d   = await db;
    final res = await d.rawQuery('SELECT COUNT(*) as c FROM queue');
    return (res.first['c'] as int?) ?? 0;
  }
}
