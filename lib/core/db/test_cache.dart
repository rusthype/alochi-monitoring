// lib/core/db/test_cache.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'db_migrate.dart';

/// Sqflite kesh — yuklab olingan test JSON'lari saqlanadi.
/// Jadval: cached_tests
class TestCache {
  static Database? _db;

  // Offline USB pack mode (core/offline/offline_session.dart): the decrypted
  // pack content must live in memory only (decision 14), never in this
  // plaintext SQLite file. While [_memory] is non-null every method below
  // reads/writes it instead of the database.
  static Map<String, _MemEntry>? _memory;
  static bool get isMemoryMode => _memory != null;
  static void enterMemoryMode() => _memory = {};
  static void exitMemoryMode() => _memory = null;

  /// Test seam: open the cache at this file instead of the support dir.
  @visibleForTesting
  static String? pathOverride;

  @visibleForTesting
  static Future<void> resetForTest() async {
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
    _opening = null;
    pathOverride = null;
  }

  static Future<String> _dbPath() async {
    final o = pathOverride;
    if (o != null) return o;
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, 'test_cache.db');
  }

  /// Counts real file opens (test seam for the single-open guarantee).
  @visibleForTesting
  static int opensForTest = 0;

  static Future<Database> _open(String path) {
    opensForTest++;
    // One idempotent ensure-schema for create AND every open (same pattern as
    // OfflineQueue): older files get the additive columns / tables, nothing is
    // dropped or rewritten.
    return openDatabase(path, version: 1, onOpen: _ensureSchema);
  }

  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_tests (
        test_key       TEXT PRIMARY KEY,
        title          TEXT NOT NULL,
        grade          INTEGER NOT NULL,
        version        INTEGER NOT NULL,
        json           TEXT NOT NULL,
        downloaded_at  INTEGER NOT NULL
      )
    ''');
    // Offline catalog scoping: last known time lock + the scopes (group /
    // school / global) this test was listed under. NULL = unknown (row cached
    // before these columns existed).
    await addColumnIfMissing(db, 'cached_tests', 'locked_until', 'TEXT');
    await addColumnIfMissing(db, 'cached_tests', 'available_until', 'TEXT');
    await addColumnIfMissing(db, 'cached_tests', 'scopes', 'TEXT');
    // Last good roster per group (offline roster).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS roster_cache (
        group_id  TEXT PRIMARY KEY,
        test_key  TEXT NOT NULL,
        json      TEXT NOT NULL,
        saved_at  INTEGER NOT NULL
      )
    ''');
  }

  /// The one in-flight open: racing first callers share it instead of each
  /// opening the file.
  static Future<Database>? _opening;

  static Future<Database> get _database async {
    final open = _db;
    if (open != null) return open;
    return _opening ??= _openDefault().whenComplete(() => _opening = null);
  }

  static Future<Database> _openDefault() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final path = await _dbPath();
    try {
      return _db = await _open(path);
    } catch (e) {
      if (!_isCorrupt(e)) rethrow;
      debugPrint('TestCache: open failed ($e), quarantining the file');
      await _quarantine(path);
      return _db = await _open(path);
    }
  }

  /// Unreadable file (not a database / malformed) - as opposed to a merely
  /// locked or busy one, which must never cost the user their cache.
  static bool _isCorrupt(Object e) {
    if (e is! DatabaseException) return false;
    final m = e.toString().toLowerCase();
    if (m.contains('locked') || m.contains('busy')) return false;
    return m.contains('not a database') ||
        m.contains('malformed') ||
        m.contains('corrupt') ||
        m.contains('notadb') ||
        m.contains('disk image');
  }

  /// Moves the damaged file (and its -wal/-shm) aside as `<name>.corrupt-<ts>`
  /// and forgets the handle, so the next access creates an empty database.
  static Future<void> _quarantine(String path) async {
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$path$suffix');
      try {
        if (await f.exists()) await f.rename('$path.corrupt-$ts$suffix');
      } catch (e) {
        debugPrint('TestCache: could not move ${f.path} aside: $e');
      }
    }
  }

  /// Runs [op] against the database. A corrupt file is quarantined and [op]
  /// retried once on the fresh database; a final failure returns [fallback]
  /// when given, else rethrows. The cache must never take the app down.
  static Future<T> _run<T>(Future<T> Function(Database db) op,
      {T Function()? fallback}) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await op(await _database);
      } catch (e) {
        if (attempt == 0 && _isCorrupt(e)) {
          debugPrint('TestCache: corrupt database ($e), recreating');
          await _quarantine(await _dbPath());
          continue;
        }
        debugPrint('TestCache: database error: $e');
        if (fallback != null) return fallback();
        rethrow;
      }
    }
  }

  /// Yangi yoki yangilangan test ma'lumotini saqlaydi (upsert).
  static Future<void> upsert(
    String testKey,
    String title,
    int grade,
    int version,
    String jsonStr,
  ) async {
    final mem = _memory;
    if (mem != null) {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map) {
        mem[testKey] = _MemEntry(
            title, grade, version, Map<String, dynamic>.from(decoded));
      }
      return;
    }
    await _run((db) async {
      // REPLACE rewrites the whole row: carry the scoping columns over.
      final prev = await db.query('cached_tests',
          columns: ['locked_until', 'available_until', 'scopes'],
          where: 'test_key = ?',
          whereArgs: [testKey],
          limit: 1);
      await db.insert(
        'cached_tests',
        {
          'test_key': testKey,
          'title': title,
          'grade': grade,
          'version': version,
          'json': jsonStr,
          'downloaded_at': DateTime.now().millisecondsSinceEpoch,
          if (prev.isNotEmpty) ...prev.first,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Remember that [testKey] was listed under [scope] (see
  /// TestCatalogService.scopeToken); [scope] is added to the known scopes.
  /// With [updateLock] the time lock is written as given ([lockedUntil] /
  /// [availableUntil] null clears a lock the server no longer has); without
  /// it the stored lock is kept. No-op for an uncached test and in memory
  /// mode. Never throws.
  static Future<void> recordListing(String testKey,
      {String? scope,
      bool updateLock = false,
      String? lockedUntil,
      String? availableUntil}) async {
    if (_memory != null) return;
    try {
      await _run((db) async {
        final rows = await db.query('cached_tests',
            columns: ['locked_until', 'available_until', 'scopes'],
            where: 'test_key = ?',
            whereArgs: [testKey],
            limit: 1);
        if (rows.isEmpty) return;
        final row = rows.first;
        final scopes = _decodeScopes(row['scopes']) ?? <String>{};
        final before = scopes.length;
        if (scope != null) scopes.add(scope);
        final newLocked = !updateLock
            ? row['locked_until'] as String?
            : ((lockedUntil ?? '').isEmpty ? null : lockedUntil);
        final newAvail = !updateLock
            ? row['available_until'] as String?
            : ((availableUntil ?? '').isEmpty ? null : availableUntil);
        if (scopes.length == before &&
            row['scopes'] != null &&
            row['locked_until'] == newLocked &&
            row['available_until'] == newAvail) {
          return; // nothing changed: no write
        }
        await db.update(
            'cached_tests',
            {
              'locked_until': newLocked,
              'available_until': newAvail,
              'scopes': jsonEncode(scopes.toList()..sort()),
            },
            where: 'test_key = ?',
            whereArgs: [testKey]);
      });
    } catch (e) {
      debugPrint('TestCache.recordListing($testKey): $e');
    }
  }

  static Set<String>? _decodeScopes(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final d = jsonDecode(raw);
      if (d is List) return d.map((e) => e.toString()).toSet();
    } catch (_) {}
    return null;
  }

  /// Bitta test yozuvini qaytaradi yoki null (topilmasa).
  /// json maydoni decode qilinib qaytariladi.
  static Future<Map<String, dynamic>?> get(String testKey) async {
    final mem = _memory;
    if (mem != null) {
      final e = mem[testKey];
      return e == null ? null : Map<String, dynamic>.from(e.json);
    }
    final rows = await _run(
        (db) => db.query(
              'cached_tests',
              where: 'test_key = ?',
              whereArgs: [testKey],
              limit: 1,
            ),
        fallback: () => <Map<String, Object?>>[]);
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
    final mem = _memory;
    if (mem != null) {
      return mem.entries
          .map((e) => <String, dynamic>{
                'test_key': e.key,
                'title': e.value.title,
                'grade': e.value.grade,
                'version': e.value.version,
              })
          .toList();
    }
    final rows = await _run(
        (db) => db.query(
              'cached_tests',
              columns: [
                'test_key',
                'title',
                'grade',
                'version',
                'downloaded_at',
                'locked_until',
                'available_until',
                'scopes',
              ],
              orderBy: 'downloaded_at DESC',
            ),
        fallback: () => <Map<String, Object?>>[]);
    if (rows.isEmpty) return [];
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      // null = scopes unknown (row cached before scoping existed).
      m['scopes'] = _decodeScopes(r['scopes']);
      return m;
    }).toList();
  }

  // ── Roster cache ──────────────────────────────────────────────────────────
  static const _rosterKeep = 200;

  /// Stores the last good roster of [groupId] (backend rows incl. `code` and
  /// the `done` flag of [testKey]). An empty list is never stored: it must not
  /// replace a good one. No-op in memory mode. Never throws.
  static Future<void> putRoster(
      String groupId, String testKey, List<Map<String, dynamic>> rows) async {
    if (_memory != null || groupId.isEmpty || rows.isEmpty) return;
    try {
      await _run((db) async {
        await db.insert(
          'roster_cache',
          {
            'group_id': groupId,
            'test_key': testKey,
            'json': jsonEncode(rows),
            'saved_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await db.rawDelete(
            'DELETE FROM roster_cache WHERE group_id NOT IN '
            '(SELECT group_id FROM roster_cache ORDER BY saved_at DESC LIMIT ?)',
            [_rosterKeep]);
      });
    } catch (e) {
      debugPrint('TestCache.putRoster($groupId): $e');
    }
  }

  /// Last good roster of [groupId], or null. `done` and `attempts_remaining`
  /// belong to one test, so for any other [testKey] they are dropped.
  static Future<List<Map<String, dynamic>>?> getRoster(
      String groupId, String testKey) async {
    if (_memory != null || groupId.isEmpty) return null;
    try {
      final rows = await _run(
          (db) => db.query('roster_cache',
              where: 'group_id = ?', whereArgs: [groupId], limit: 1),
          fallback: () => <Map<String, Object?>>[]);
      if (rows.isEmpty) return null;
      final decoded = jsonDecode(rows.first['json'] as String);
      if (decoded is! List) return null;
      final sameTest = rows.first['test_key'] == testKey;
      final out = <Map<String, dynamic>>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        if (!sameTest) {
          m.remove('done');
          m.remove('attempts_remaining');
        }
        out.add(m);
      }
      return out.isEmpty ? null : out;
    } catch (e) {
      debugPrint('TestCache.getRoster($groupId): $e');
      return null;
    }
  }

  /// Berilgan test_key uchun saqlangan version raqamini qaytaradi yoki null.
  static Future<int?> versionOf(String testKey) async {
    final mem = _memory;
    if (mem != null) return mem[testKey]?.version;
    final rows = await _run(
        (db) => db.query(
              'cached_tests',
              columns: ['version'],
              where: 'test_key = ?',
              whereArgs: [testKey],
              limit: 1,
            ),
        fallback: () => <Map<String, Object?>>[]);
    if (rows.isEmpty) return null;
    final v = rows.first['version'];
    if (v == null) return null;
    return int.tryParse(v.toString());
  }

  /// Berilgan test_key to'plamiga kirmagan barcha keshlangan yozuvlarni
  /// o'chiradi. Faqat backenddan MUVAFFAQIYATLI (bo'sh bo'lsa ham) javob
  /// olingandan keyin chaqirilishi kerak — tarmoq xatosida chaqirilmasin
  /// (offline rejim buzilmasligi uchun).
  static Future<void> pruneNotIn(Set<String> keepKeys) async {
    // Bo'sh to'plam hech qachon "hammasini o'chir" degani emas (2026-10-28:
    // bo'sh/qisman katalog javobi butun keshni o'chirgan).
    if (keepKeys.isEmpty) return;
    // Pack mode: only the pack's tests are visible here, never prune from it.
    if (_memory != null) return;
    final placeholders = List.filled(keepKeys.length, '?').join(',');
    await _run((db) => db.delete(
          'cached_tests',
          where: 'test_key NOT IN ($placeholders)',
          whereArgs: keepKeys.toList(),
        ));
  }

  /// Aynan berilgan test_key yozuvlarini o'chiradi (bo'sh to'plam — hech narsa).
  static Future<void> deleteKeys(Set<String> keys) async {
    if (keys.isEmpty) return;
    final mem = _memory;
    if (mem != null) {
      mem.removeWhere((k, _) => keys.contains(k));
      return;
    }
    final placeholders = List.filled(keys.length, '?').join(',');
    await _run((db) => db.delete(
          'cached_tests',
          where: 'test_key IN ($placeholders)',
          whereArgs: keys.toList(),
        ));
  }
}

class _MemEntry {
  final String title;
  final int grade;
  final int version;
  final Map<String, dynamic> json;
  const _MemEntry(this.title, this.grade, this.version, this.json);
}
