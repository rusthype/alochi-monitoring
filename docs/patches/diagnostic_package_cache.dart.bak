// lib/core/db/diagnostic_package_cache.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Diagnostika kioskining "hali BOSHLANMAGAN fan" peek-paketlari uchun doimiy
/// disk kesh — TestCacheDb bilan bir xil key->JSON blob naqshi, lekin alohida
/// jadval (diagnostic_history_db.dart o'z vaqtida xuddi shu sababga ko'ra
/// HistoryDb'ni qayta ishlatmagan: mavjud chaqiruvchilarni "burish" xavfli).
/// Fan haqiqatan boshlangach (`_startSubject`), shu fan uchun yozuv
/// O'CHIRILADI — AttemptStore endi yagona haqiqat manbai bo'ladi.
///
/// Har bir ochiq metod o'z xatosini ICHIDA yutadi (bo'sh/null/no-op bilan
/// qaytadi) — bu shunchaki qulaylik keshi, chaqiruvchilar (ko'pincha
/// `unawaited(...)` bilan, hech qanday try/catch'siz) hech qachon uning
/// muvaffaqiyatsizligidan asosiy oqimni yo'qotmasligi kerak (masalan sqflite
/// platform-kanali mavjud bo'lmagan widget-test muhitida).
class DiagnosticPackageCache {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    final path = join(dir.path, 'diagnostic_package_cache.db');
    _db = await openDatabase(path, version: 1, onCreate: _create);
    return _db!;
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE diagnostic_package_cache (
        cache_key  TEXT PRIMARY KEY,
        json       TEXT NOT NULL,
        cached_at  INTEGER NOT NULL
      )
    ''');
  }

  @visibleForTesting
  static Future<void> openInMemory() async {
    sqfliteFfiInit();
    // `databaseFactoryFfi` (used by the real `db` getter above) dispatches
    // every operation to a real background Isolate
    // (sqflite_common_ffi's `ffiMethodCallhandleInIsolate`) — genuine
    // cross-isolate message passing that resolves via the VM's real event
    // loop, NOT via `Zone.current.createTimer`/`scheduleMicrotask`. Inside a
    // `testWidgets` body, the whole test runs inside a `FakeAsync` zone
    // whose `pump()`/`pumpAndSettle()` only advance a *virtual* clock and
    // flush zone-local microtasks — they cannot make a real background
    // Isolate's reply arrive any faster. Production code fires
    // `unawaited(DiagnosticPackageCache.put/delete(...))` (see
    // `diagnostic_test_runner_screen.dart`), so that real, out-of-band
    // Future would still be pending when the test body returns, leaking
    // past this test's boundary and permanently corrupting
    // `TestAsyncUtils`'s (static, process-global) guard stack for every
    // later test in the same file ("Guarded function conflict").
    // `databaseFactoryFfiNoIsolate` runs every call in-process instead, so
    // it resolves through ordinary, FakeAsync-visible microtasks — use it
    // for tests only; production keeps the real isolate-backed factory.
    databaseFactory = databaseFactoryFfiNoIsolate;
    // singleInstance: false — sqflite otherwise caches/reuses ONE connection
    // per path, and `inMemoryDatabasePath` is the same literal path every
    // call, so a second test's openInMemory() would silently hand back the
    // FIRST test's still-open (and still-populated) in-memory db instead of
    // a fresh one (same fix as diagnostic_history_db.dart's TestCacheDb-
    // pattern flaw).
    _db = await openDatabase(inMemoryDatabasePath,
        version: 1, onCreate: _create, singleInstance: false);
  }

  @visibleForTesting
  static Future<void> reset() async {
    // Awaiting close() also drains any still-in-flight unawaited put()/
    // delete() call a test triggered indirectly via production code
    // (_prefetchSubjectInBackground/_startSubject fire real sqflite I/O
    // that doesn't resolve inside a testWidgets FakeAsync zone) — without
    // this, that Future leaks past this test's boundary and can corrupt a
    // later test's TestAsyncUtils guard state.
    await _db?.close();
    _db = null;
  }

  static String _key(String attemptId, String subject) =>
      '${attemptId}_$subject';

  static Future<void> put(
      String attemptId, String subject, Map<String, dynamic> data) async {
    try {
      final d = await db;
      await d.insert(
        'diagnostic_package_cache',
        {
          'cache_key': _key(attemptId, subject),
          'json': jsonEncode(data),
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('DiagnosticPackageCache.put failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> get(
      String attemptId, String subject) async {
    try {
      final d = await db;
      final rows = await d.query(
        'diagnostic_package_cache',
        where: 'cache_key = ?',
        whereArgs: [_key(attemptId, subject)],
      );
      if (rows.isEmpty) return null;
      return jsonDecode(rows.first['json'] as String) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('DiagnosticPackageCache.get failed: $e');
      return null;
    }
  }

  static Future<void> delete(String attemptId, String subject) async {
    try {
      final d = await db;
      await d.delete(
        'diagnostic_package_cache',
        where: 'cache_key = ?',
        whereArgs: [_key(attemptId, subject)],
      );
    } catch (e) {
      debugPrint('DiagnosticPackageCache.delete failed: $e');
    }
  }

  /// `__subjects__` maxsus kaliti ostida shu attempt'ning fan ro'yxati.
  static Future<void> putSubjectList(String attemptId, List<String> subjects) =>
      put(attemptId, '__subjects__', {'subjects': subjects});

  static Future<List<String>?> getSubjectList(String attemptId) async {
    final data = await get(attemptId, '__subjects__');
    final list = data?['subjects'] as List?;
    return list?.map((e) => e.toString()).toList();
  }
}
