// lib/core/db/attempt_store.dart
// Crash-recovery persistence for an in-progress test attempt.
//
// The test engine only kept answers in memory (test_engine.dart _answers),
// so an app crash/restart lost all progress and re-rolled a random variant
// on relaunch (runner_dispatch.dart _pickRandomVariant). This store lets
// runner_dispatch resume the SAME variant and test_engine restore the typed
// answers + remaining countdown after a crash/restart, as long as the
// attempt's deadline has not passed.
//
// SharedPreferences is sufficient here (small JSON blob per test, no
// relational queries needed) — kept separate from the sqflite-backed
// offline_queue.dart / test_cache.dart which serve different purposes.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'queue_crypto.dart';

/// Persists a single in-progress attempt per `test_key`.
///
/// Stored JSON shape:
/// ```json
/// {
///   "variant": 1,
///   "answers": {"Section/0": "typed", "Section/1": 2},
///   "started_at": 1730000000000,
///   "deadline_epoch_ms": 1730000600000,
///   "student_name": "Ism Familiya",
///   "student_id": "A26-473",
///   "group_name": "5-A"
/// }
/// ```
class AttemptStore {
  static String _key(String testKey) => 'attempt_$testKey';

  /// Loads the saved attempt for [testKey], or null if none exists / corrupt.
  static Future<Map<String, dynamic>?> load(String testKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(testKey));
      if (raw == null || raw.isEmpty) return null;
      final decrypted = await QueueCrypto.decryptPayload(raw);
      final decoded = jsonDecode(decrypted);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (e) {
      debugPrint('AttemptStore.load($testKey) error: $e');
      return null;
    }
  }

  /// Loads the saved attempt for [testKey] only if it belongs to
  /// [studentId]. A saved attempt left behind by a DIFFERENT student (e.g.
  /// an abandoned attempt on a shared kiosk) must never resume for someone
  /// else, so this returns null in that case even though a record
  /// technically exists on disk.
  ///
  /// If [studentId] is empty (as in manual-entry, no-roster flows), returns
  /// null since we have no reliable identifier to match against. Two
  /// different manual-entry students both have studentId=='', so allowing
  /// a resume on empty string would leak answers across students — the same
  /// bug via a different path. Only resume if we can positively identify
  /// the student.
  static Future<Map<String, dynamic>?> loadForStudent(
      String testKey, String studentId) async {
    if (studentId.isEmpty) return null;
    final saved = await load(testKey);
    if (saved == null) return null;
    if (saved['student_id'] != studentId) return null;
    return saved;
  }

  /// Saves/overwrites the attempt for [testKey]. Best-effort — swallows
  /// storage errors so a save failure never crashes the running test.
  static Future<void> save(String testKey, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encrypted = await QueueCrypto.encryptPayload(jsonEncode(data));
      await prefs.setString(_key(testKey), encrypted);
    } catch (e) {
      debugPrint('AttemptStore.save($testKey) error: $e');
    }
  }

  /// Removes the saved attempt for [testKey]. Called after a successful
  /// submit so the next launch starts a fresh attempt.
  static Future<void> clear(String testKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(testKey));
    } catch (e) {
      debugPrint('AttemptStore.clear($testKey) error: $e');
    }
  }
}
