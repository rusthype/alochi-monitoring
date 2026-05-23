import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class HistoryDb {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final path = join(dir.path, 'monitoring_history.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            first_name TEXT,
            last_name TEXT,
            school TEXT,
            grade_group TEXT,
            math_score INTEGER,
            eng_score INTEGER,
            total_pct REAL,
            date_taken INTEGER
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<void> insertResult({
    required String firstName,
    required String lastName,
    required String school,
    required String gradeGroup,
    required int mathScore,
    required int engScore,
    required double totalPct,
  }) async {
    final d = await db;
    await d.insert('history', {
      'first_name': firstName,
      'last_name': lastName,
      'school': school,
      'grade_group': gradeGroup,
      'math_score': mathScore,
      'eng_score': engScore,
      'total_pct': totalPct,
      'date_taken': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<List<Map<String, dynamic>>> getHistory() async {
    final d = await db;
    return await d.query('history', orderBy: 'date_taken DESC');
  }

  static Future<void> clearHistory() async {
    final d = await db;
    await d.delete('history');
  }
}
