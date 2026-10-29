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
// Storage: one small encrypted JSON file per record under
// `<app support>/attempts/`, written atomically (temp file + flush + rename,
// the previous good copy kept as `.bak`). The records used to live in the
// single shared_preferences.json, which the desktop plugin rewrites in full
// and non-atomically on every change - a power cut could tear it and take
// every attempt (and the whole prefs file) with it. Until [init] succeeds
// (tests, or an unwritable data dir) the old SharedPreferences backend is used
// unchanged; records still sitting there are migrated lazily on first read.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'queue_crypto.dart';

/// One stored record found by [AttemptStore.listAll].
class AttemptEntry {
  /// Storage slot id (the legacy shared_preferences key).
  final String slotKey;
  final String testKey;

  /// True for a record of a student displaced from the main slot of
  /// [testKey]; false for the main slot.
  final bool isParked;
  final Map<String, dynamic> record;

  const AttemptEntry({
    required this.slotKey,
    required this.testKey,
    required this.isParked,
    required this.record,
  });
}

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
  static const _slotPrefix = 'attempt_';
  static const _parkSep = '__parked__';

  static String _key(String testKey) => '$_slotPrefix$testKey';

  /// Where the record of a student who was displaced from the main slot of
  /// [testKey] (another student started the same test on this PC) is kept.
  static String _parkKey(String testKey, String studentId) =>
      '$_slotPrefix$testKey$_parkSep$studentId';

  /// Which student currently owns each main slot - lets [save] skip the
  /// read-and-compare on every keystroke-driven save.
  static final Map<String, String> _mainOwner = {};

  /// `attempt_id` of the record last written to each main slot (same purpose).
  static final Map<String, String> _mainAttempt = {};

  // ── backend selection ──────────────────────────────────────────────────────

  static Directory? _dir;

  /// Slots already looked up in the legacy shared_preferences backend.
  static final Set<String> _legacyChecked = {};

  /// Resolves `<app support>/attempts` and switches to the file backend.
  /// Never throws: on failure the SharedPreferences backend stays in use.
  static Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'attempts'));
      await dir.create(recursive: true);
      _dir = dir;
    } catch (e) {
      debugPrint('AttemptStore.init failed, using shared_preferences: $e');
    }
  }

  /// Test seam: use [dir] for the file backend, or null for the legacy
  /// SharedPreferences backend. Also forgets all in-memory caches.
  @visibleForTesting
  static void useDirectoryForTest(Directory? dir) {
    _dir = dir;
    _mainOwner.clear();
    _mainAttempt.clear();
    _legacyChecked.clear();
  }

  // ── serialization of all store operations ──────────────────────────────────

  static Future<void> _tail = Future<void>.value();

  /// File backend: runs [op] after every earlier store operation finished, so
  /// concurrent debounced saves can never interleave their temp-file/rename
  /// steps. The SharedPreferences backend (tests, fallback) needs no ordering
  /// and runs directly, exactly as before.
  static Future<T> _serial<T>(Future<T> Function() op) {
    if (_dir == null) return op();
    final r = _tail.then((_) => op());
    _tail = r.then((_) {}, onError: (_) {});
    return r;
  }

  // ── slot file naming ───────────────────────────────────────────────────────

  static final RegExp _escaped = RegExp(r'~([0-9a-f]+)~');

  /// Reversible, filesystem-safe form of a slot key (everything outside
  /// [A-Za-z0-9_-] becomes `~<hex>~`).
  static String _fileStem(String slot) {
    final b = StringBuffer();
    for (final r in slot.runes) {
      final c = String.fromCharCode(r);
      if (RegExp(r'[A-Za-z0-9_\-]').hasMatch(c)) {
        b.write(c);
      } else {
        b.write('~${r.toRadixString(16)}~');
      }
    }
    return b.toString();
  }

  static String _slotFromStem(String stem) => stem.replaceAllMapped(
      _escaped, (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));

  static String _path(Directory dir, String slot) =>
      p.join(dir.path, '${_fileStem(slot)}.json');

  // ── raw slot access (call only inside _serial) ─────────────────────────────

  static Future<Map<String, dynamic>?> _decode(String? raw) async {
    if (raw == null || raw.isEmpty) return null;
    final decrypted = await QueueCrypto.decryptPayload(raw);
    final decoded = jsonDecode(decrypted);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  static Future<({String raw, Map<String, dynamic> rec})?> _readFile(
      String path) async {
    try {
      final raw = await File(path).readAsString();
      final rec = await _decode(raw);
      return rec == null ? null : (raw: raw, rec: rec);
    } catch (_) {
      return null; // missing, empty, torn or tampered
    }
  }

  /// The raw (encrypted) text and decoded record of [slot], or null.
  static Future<({String raw, Map<String, dynamic> rec})?> _readSlot(
      String slot) async {
    final dir = _dir;
    if (dir == null) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(slot);
      final rec = await _decode(raw);
      return rec == null ? null : (raw: raw!, rec: rec);
    }
    final path = _path(dir, slot);
    // Newest valid copy wins. A complete `.tmp` is always newer than the main
    // file (a crash between "write tmp" and "rename tmp -> main" leaves it
    // beside the old main or beside `.bak`; a torn one fails to decode and is
    // skipped), so it comes first - it may hold the `completed` marker.
    final hit = await _readFile('$path.tmp') ??
        await _readFile(path) ??
        await _readFile('$path.bak');
    if (hit != null) return hit;
    return _migrateLegacy(dir, slot);
  }

  /// Moves a record still stored in shared_preferences into its own file.
  static Future<({String raw, Map<String, dynamic> rec})?> _migrateLegacy(
      Directory dir, String slot) async {
    if (_legacyChecked.contains(slot)) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(slot);
      final rec = await _decode(raw);
      if (rec == null) {
        _legacyChecked.add(slot);
        return null;
      }
      await _writeSlot(slot, raw!);
      await prefs.remove(slot);
      // Only now: after a transient failure the next read must retry, or the
      // legacy record would stay invisible for the rest of the process.
      _legacyChecked.add(slot);
      return (raw: raw, rec: rec);
    } catch (e) {
      debugPrint('AttemptStore: legacy migration of $slot failed: $e');
      return null;
    }
  }

  static Future<void> _writeSlot(String slot, String raw,
      {SharedPreferences? prefs}) async {
    final dir = _dir;
    if (dir == null) {
      await (prefs ?? await SharedPreferences.getInstance())
          .setString(slot, raw);
      return;
    }
    final path = _path(dir, slot);
    final tmp = File('$path.tmp');
    await tmp.writeAsString(raw, flush: true);
    try {
      await File(path).rename('$path.bak'); // keep the previous good copy
    } on FileSystemException {
      // no previous copy
    }
    await tmp.rename(path);
  }

  static Future<void> _deleteSlot(String slot) async {
    final dir = _dir;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(slot);
    if (dir == null) return;
    final path = _path(dir, slot);
    // Main LAST: a power cut part-way must not leave a `.tmp`/`.bak` that
    // [_readSlot] would resurrect as the cleared record.
    for (final f in ['$path.tmp', '$path.bak', path]) {
      try {
        await File(f).delete();
      } on PathNotFoundException {
        // already gone
      }
    }
  }

  // ── public API ─────────────────────────────────────────────────────────────

  /// Loads the saved attempt for [testKey], or null if none exists / corrupt.
  static Future<Map<String, dynamic>?> load(String testKey) =>
      _serial(() => _loadMain(testKey));

  static Future<Map<String, dynamic>?> _loadMain(String testKey) async {
    try {
      return (await _readSlot(_key(testKey)))?.rec;
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
      String testKey, String studentId) {
    if (studentId.isEmpty) return Future.value(null);
    return _serial(() async {
      final saved = await _loadMain(testKey);
      if (saved != null && saved['student_id'] == studentId) return saved;
      try {
        final parked = (await _readSlot(_parkKey(testKey, studentId)))?.rec;
        if (parked != null && parked['student_id'] == studentId) return parked;
      } catch (e) {
        debugPrint('AttemptStore.loadForStudent($testKey) parked error: $e');
      }
      return null;
    });
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
  static Future<void> save(String testKey, Map<String, dynamic> data) {
    // Serialise the payload NOW: the caller may keep mutating [data].
    final String encoded;
    try {
      encoded = jsonEncode(data);
    } catch (e) {
      debugPrint('AttemptStore.save($testKey) encode error: $e');
      return Future<void>.value();
    }
    return _serial(() async {
      try {
        // Prefs backend: take the instance first, as the old code did - the
        // widget tests' fake-async pumping depends on this hop order.
        final prefs =
            _dir == null ? await SharedPreferences.getInstance() : null;
        final sid = data['student_id']?.toString() ?? '';
        final aid = data['attempt_id']?.toString() ?? '';
        var supersedeOwnParked = false;
        if (_mainOwner[testKey] != sid || _mainAttempt[testKey] != aid) {
          final existing = await _readSlot(_key(testKey));
          final oldSid = existing?.rec['student_id']?.toString() ?? '';
          final oldAid = existing?.rec['attempt_id']?.toString() ?? '';
          if (existing != null && _worthParking(existing.rec)) {
            if (oldSid.isNotEmpty && oldSid != sid) {
              await _writeSlot(_parkKey(testKey, oldSid), existing.raw);
            } else if (oldSid.isNotEmpty &&
                oldAid.isNotEmpty &&
                aid.isNotEmpty &&
                oldAid != aid) {
              // The same student starts a DIFFERENT attempt over unsent
              // answers (the engine drops a record of another test version):
              // keep the old one under its own slot for the recovery scan.
              await _writeSlot(
                  _parkKey(testKey, '$oldSid#$oldAid'), existing.raw);
            }
          }
          supersedeOwnParked = sid.isNotEmpty;
        }
        final encrypted = await QueueCrypto.encryptPayload(encoded);
        await _writeSlot(_key(testKey), encrypted, prefs: prefs);
        _mainOwner[testKey] = sid;
        _mainAttempt[testKey] = aid;
        // Only after the new main slot is safely on disk: the parked copy may
        // be the sole copy until then.
        if (supersedeOwnParked) await _supersedeParked(testKey, sid, aid);
      } catch (e) {
        debugPrint('AttemptStore.save($testKey) error: $e');
      }
    });
  }

  /// The student [sid] now owns the main slot with attempt [aid]. Their parked
  /// copy is dropped only if it is the same attempt (the new main slot carries
  /// it) or holds nothing; a DIFFERENT attempt with answers (e.g. one of an
  /// older test version the engine discarded) is moved to its own
  /// `<sid>#<attempt>` slot for the recovery scan - never deleted while it is
  /// the only copy of those answers.
  static Future<void> _supersedeParked(
      String testKey, String sid, String aid) async {
    final slot = _parkKey(testKey, sid);
    final parked = await _readSlot(slot);
    if (parked != null && _worthParking(parked.rec)) {
      final pAid = parked.rec['attempt_id']?.toString() ?? '';
      if (pAid != aid) {
        await _writeSlot(_parkKey(testKey, '$sid#$pAid'), parked.raw);
      }
    }
    await _deleteSlot(slot);
  }

  /// Removes the saved attempt for [testKey]. Called after a successful
  /// submit so the next launch starts a fresh attempt.
  static Future<void> clear(String testKey) => _serial(() async {
        try {
          await _deleteSlot(_key(testKey));
          _mainOwner.remove(testKey);
          _mainAttempt.remove(testKey);
        } catch (e) {
          debugPrint('AttemptStore.clear($testKey) error: $e');
        }
      });

  /// Removes exactly the slot [e] was listed from (main or parked), and only
  /// while it still holds the record that was listed: a student who started
  /// the attempt again meanwhile has newer answers in that slot, and deleting
  /// it would lose them.
  static Future<void> clearEntry(AttemptEntry e) => _serial(() async {
        try {
          final cur = await _readSlot(e.slotKey);
          if (cur != null && jsonEncode(cur.rec) != jsonEncode(e.record)) {
            debugPrint('AttemptStore.clearEntry(${e.slotKey}): record changed '
                'since it was listed, kept');
            return;
          }
          await _deleteSlot(e.slotKey);
          if (!e.isParked) {
            _mainOwner.remove(e.testKey);
            _mainAttempt.remove(e.testKey);
          }
        } catch (err) {
          debugPrint('AttemptStore.clearEntry(${e.slotKey}) error: $err');
        }
      });

  /// Every stored record, main and parked, across all tests (crash recovery
  /// scan). Unreadable records are skipped. Never throws.
  static Future<List<AttemptEntry>> listAll() => _serial(() async {
        final slots = <String>{};
        try {
          final dir = _dir;
          if (dir != null && await dir.exists()) {
            await for (final f in dir.list()) {
              final name = p.basename(f.path);
              final stem = name.endsWith('.json')
                  ? name.substring(0, name.length - 5)
                  : (name.endsWith('.json.bak') || name.endsWith('.json.tmp'))
                      ? name.substring(0, name.length - 9)
                      : null;
              if (stem != null) slots.add(_slotFromStem(stem));
            }
          }
          final prefs = await SharedPreferences.getInstance();
          slots.addAll(prefs.getKeys().where((k) => k.startsWith(_slotPrefix)));
        } catch (e) {
          debugPrint('AttemptStore.listAll scan error: $e');
        }
        final out = <AttemptEntry>[];
        for (final slot in slots) {
          if (!slot.startsWith(_slotPrefix)) continue;
          try {
            final hit = await _readSlot(slot);
            if (hit == null) continue;
            final rest = slot.substring(_slotPrefix.length);
            final cut = rest.indexOf(_parkSep);
            out.add(AttemptEntry(
              slotKey: slot,
              testKey: cut < 0 ? rest : rest.substring(0, cut),
              isParked: cut >= 0,
              record: hit.rec,
            ));
          } catch (e) {
            debugPrint('AttemptStore.listAll($slot) error: $e');
          }
        }
        return out;
      });
}
