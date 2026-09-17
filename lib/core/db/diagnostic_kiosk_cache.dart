// lib/core/db/diagnostic_kiosk_cache.dart
// Offline fallback cache for kiosk roster/school-info reads (schools,
// classes, students) — same lightweight SharedPreferences-JSON-blob pattern
// as AttemptStore (core/db/attempt_store.dart), including QueueCrypto
// encryption at rest since roster rows carry student names (PII).
//
// Pure fallback: callers only read this on a FAILED live fetch, never to
// prefer stale data over a working live one.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'queue_crypto.dart';

class DiagnosticKioskCache {
  static String _key(String name) => 'diag_kiosk_cache_$name';

  /// Saves [data] (must be JSON-encodable) under [name]. Best-effort —
  /// swallows storage errors so a cache-write failure never breaks a
  /// successful live fetch.
  static Future<void> save(String name, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encrypted = await QueueCrypto.encryptPayload(jsonEncode(data));
      await prefs.setString(_key(name), encrypted);
    } catch (e) {
      debugPrint('DiagnosticKioskCache.save($name) error: $e');
    }
  }

  /// Loads the cached value for [name], or null if none / corrupt.
  static Future<dynamic> load(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(name));
      if (raw == null || raw.isEmpty) return null;
      final decrypted = await QueueCrypto.decryptPayload(raw);
      return jsonDecode(decrypted);
    } catch (e) {
      debugPrint('DiagnosticKioskCache.load($name) error: $e');
      return null;
    }
  }
}
