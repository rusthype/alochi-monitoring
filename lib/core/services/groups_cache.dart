// lib/core/services/groups_cache.dart
//
// Last-good group list per school (SharedPreferences), so a proctor whose
// network dropped after the first load can still pick a group and use the
// already downloaded tests. Convenience only: every failure is logged and
// reads as "nothing cached".
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroupsCache {
  static const _prefix = 'groups_cache_v1_';

  /// schoolId (collision-free) when known, else the school code.
  static String _key(String schoolCode, String schoolId) =>
      '$_prefix${schoolId.isNotEmpty ? 'id_$schoolId' : 'code_$schoolCode'}';

  static Future<void> save(
      String schoolCode, String schoolId, List<Map<String, dynamic>> groups) async {
    if (groups.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(schoolCode, schoolId), jsonEncode(groups));
    } catch (e) {
      debugPrint('GroupsCache.save: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> load(
      String schoolCode, String schoolId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(schoolCode, schoolId));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('GroupsCache.load: $e');
      return const [];
    }
  }
}
