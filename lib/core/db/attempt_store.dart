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

  /// Where the record of a student who was displaced from the main slot of
  /// [testKey] (another student started the same test on this PC) is kept.
  static String _parkKey(String testKey, String studentId) =>
      'attempt_${testKey}__parked__$studentId';

  /// Which student currently owns each main slot - lets [save] skip the
  /// read-and-compare on every keystroke-driven save.
  static final Map<String, String> _mainOwner = {};

  static Future<Map<String, dynamic>?> _decode(String? raw) async {
    if (raw == null || raw.isEmpty) return null;
    final decrypted = await QueueCrypto.decryptPayload(raw);
    final decoded = jsonDecode(decrypted);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  /// Loads the saved attempt for [testKey], or null if none exists / corrupt.
  static Future<Map<String, dynamic>?> load(String testKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await _decode(prefs.getString(_key(testKey)));
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
  ///
  /// There is ONE main slot per test (so the other callers keep working with
  /// just a test key). When a second student starts the same test the first
  /// student's unfinished / completed-but-unsent record is parked by [save]
  /// instead of being overwritten; it is found again here.
  static Future<Map<String, dynamic>?> loadForStudent(
      String testKey, String studentId) async {
    if (studentId.isEmpty) return null;
    final saved = await load(testKey);
    if (saved != null && saved['student_id'] == studentId) return saved;
    try {
      final prefs = await SharedPreferences.getInstance();
      final parked =
          await _decode(prefs.getString(_parkKey(testKey, studentId)));
      if (parked != null && parked['student_id'] == studentId) return parked;
    } catch (e) {
      debugPrint('AttemptStore.loadForStudent($testKey) parked error: $e');
    }
    return null;
  }

  /// A record worth protecting from being displaced: it holds answers, or it
  /// is the completed snapshot that still has to be (re)submitted.
  static bool _worthParking(Map<String, dynamic> rec) {
    if (rec['completed'] == true) return true;
    final a = rec['answers'];
    return a is Map && a.isNotEmpty;
  }

  /// Saves/overwrites the attempt for [testKey]. Best-effort — swallows
  /// storage errors so a save failure never crashes the running test.
  ///
  /// If the main slot currently belongs to a DIFFERENT student with a
  /// record worth keeping, that record is parked (per student) first, so a
  /// second student on the same PC can never destroy the first one's
  /// answers; the saving student's own parked copy (if any) is superseded.
  static Future<void> save(String testKey, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sid = data['student_id']?.toString() ?? '';
      if (_mainOwner[testKey] != sid) {
        final existingRaw = prefs.getString(_key(testKey));
        final existing = await _decode(existingRaw);
        final oldSid = existing?['student_id']?.toString() ?? '';
        if (existing != null &&
            oldSid.isNotEmpty &&
            oldSid != sid &&
            _worthParking(existing)) {
          await prefs.setString(_parkKey(testKey, oldSid), existingRaw!);
        }
        if (sid.isNotEmpty) await prefs.remove(_parkKey(testKey, sid));
      }
      final encrypted = await QueueCrypto.encryptPayload(jsonEncode(data));
      await prefs.setString(_key(testKey), encrypted);
      _mainOwner[testKey] = sid;
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
      _mainOwner.remove(testKey);
    } catch (e) {
      debugPrint('AttemptStore.clear($testKey) error: $e');
    }
  }
}
