// lib/core/db/db_migrate.dart
//
// Helpers for idempotent sqflite migrations. A deployed PC's `user_version`
// can disagree with its real schema (older builds created tables without
// bumping it, or a partial upgrade ran), so a migration must never assume a
// table/column is absent. Never drops or recreates user data.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `ALTER TABLE ... ADD COLUMN`, skipped if the column already exists.
Future<void> addColumnIfMissing(
    DatabaseExecutor db, String table, String column, String ddl) async {
  final cols = await db.rawQuery('PRAGMA table_info($table)');
  if (cols.any((c) => c['name'] == column)) return;
  await db.execute('ALTER TABLE $table ADD COLUMN $column $ddl');
}
