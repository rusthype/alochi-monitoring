import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Durable per-test set of student ids THIS kiosk finished (written when the
/// result is saved/enqueued). Bridges the gap until the backend roster's own
/// `done` flag reflects the synced result. Never throws.
class RosterDoneStore {
  static const _prefix = 'roster_done_';
  static const _cap = 5000; // per test (a big school's grade-wide test on one PC); oldest dropped first

  static Future<Set<String>> load(String testKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList('$_prefix$testKey') ?? const []).toSet();
    } catch (e) {
      debugPrint('RosterDoneStore.load failed: $e');
      return <String>{};
    }
  }

  static Future<void> add(String testKey, String studentId) async {
    if (testKey.isEmpty || studentId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (prefs.getStringList('$_prefix$testKey') ?? <String>[])
        ..remove(studentId)
        ..add(studentId);
      await prefs.setStringList('$_prefix$testKey',
          list.length > _cap ? list.sublist(list.length - _cap) : list);
    } catch (e) {
      debugPrint('RosterDoneStore.add failed: $e');
    }
  }
}
