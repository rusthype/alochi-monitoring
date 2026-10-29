import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads [SharedPreferences] without ever throwing, so `main()` can ALWAYS
/// override `sharedPreferencesProvider` (an un-overridden provider throws
/// UnimplementedError on the first frame — the "Xatolik yuz berdi" screen
/// instead of login).
///
/// A corrupt/unwritable `%APPDATA%\...\shared_preferences.json` on a school PC
/// makes `getInstance()` throw. We retry once after [retryDelay]; if it still
/// fails we switch the plugin to an in-memory store (settings reset to
/// defaults for this run, nothing persisted) and report via [onFailure].
/// Because `setMockInitialValues` swaps the global store, every later direct
/// `SharedPreferences.getInstance()` caller (heartbeat, attempt store, ...)
/// gets the same working in-memory instance instead of throwing again.
///
/// Before giving up on persistence, a file that is really torn (power cut
/// mid-write leaves a truncated or NUL-filled `shared_preferences.json`) is
/// renamed to `shared_preferences.json.corrupt-<ts>` and the load is retried,
/// so the plugin recreates a fresh file and later launches persist normally
/// instead of staying in-memory forever with the corruption never healed.
Future<SharedPreferences> loadPrefsWithFallback({
  Future<SharedPreferences> Function() load = SharedPreferences.getInstance,
  Duration retryDelay = const Duration(milliseconds: 300),
  void Function(Object error, StackTrace stack)? onFailure,
  Future<File> Function() locatePrefsFile = _defaultPrefsFile,
}) async {
  try {
    return await load();
  } catch (error, stack) {
    debugPrint('SharedPreferences init failed (retrying): $error');
    onFailure?.call(error, stack);
  }
  await Future<void>.delayed(retryDelay);
  try {
    return await load();
  } catch (error, stack) {
    debugPrint('SharedPreferences init failed again: $error');
    onFailure?.call(error, stack);
  }
  if (await _quarantineIfTorn(locatePrefsFile)) {
    try {
      return await load();
    } catch (error, stack) {
      debugPrint('SharedPreferences still failing after quarantine: $error');
      onFailure?.call(error, stack);
    }
  }
  // ponytail: non-persistent for this run; settings reset to defaults.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

Future<File> _defaultPrefsFile() async => File(p.join(
    (await getApplicationSupportDirectory()).path, 'shared_preferences.json'));

/// Newest corrupt-file backups kept next to the prefs file.
const _keepBackups = 3;

/// Repairs a prefs file the plugin cannot load. Returns true only when the
/// file was actually changed. A healthy file that failed to load for another
/// reason (locked, permissions) is never touched.
///
/// * Not a JSON object (torn / NUL-filled by a power cut): renamed aside as
///   `<file>.corrupt-<ts>`; the plugin then starts a fresh file.
/// * A JSON object with unreadable (null) values: the original is copied to
///   `<file>.corrupt-<ts>` and the file is rewritten with every readable entry
///   (temp file + rename), so nothing we could still read is lost.
///
/// Only the newest [_keepBackups] backups are kept.
Future<bool> _quarantineIfTorn(Future<File> Function() locate) async {
  try {
    final file = await locate();
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return false; // the plugin treats empty as no prefs
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      // not valid JSON -> torn
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final backup = '${file.path}.corrupt-$stamp';
    if (decoded is Map) {
      final clean = <String, Object?>{
        for (final e in decoded.entries)
          if (e.value != null) e.key.toString(): e.value,
      };
      if (clean.length == decoded.length) return false; // healthy file
      await file.copy(backup);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(clean), flush: true);
      await tmp.rename(file.path);
      debugPrint('shared_preferences.json had unreadable entries; readable '
          'ones kept, original saved as .corrupt-$stamp');
    } else {
      await file.rename(backup);
      debugPrint('Corrupt shared_preferences.json moved aside (.corrupt-$stamp)');
    }
    await _pruneBackups(file);
    return true;
  } catch (e) {
    debugPrint('Could not quarantine shared_preferences.json: $e');
    return false;
  }
}

Future<void> _pruneBackups(File prefs) async {
  try {
    final prefix = '${p.basename(prefs.path)}.corrupt-';
    final backups = <(int, File)>[
      for (final f in prefs.parent.listSync().whereType<File>())
        if (p.basename(f.path).startsWith(prefix))
          (int.tryParse(p.basename(f.path).substring(prefix.length)) ?? 0, f),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    for (final old in backups.skip(_keepBackups)) {
      await old.$2.delete();
    }
  } catch (e) {
    debugPrint('Could not prune shared_preferences backups: $e');
  }
}
