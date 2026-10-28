// lib/core/services/server_clock.dart
//
// Time-lock checks (`locked_until`) compare a SERVER timestamp with "now". The
// PC's own clock is not trustworthy (a reset to 2000 would lock every scheduled
// test, a clock running ahead would open one early), so "now" is the device
// clock plus an offset learned from the HTTP `Date` header of any successful
// API answer (no backend change) and persisted, so the last known offset also
// holds while offline or after a restart.
import 'dart:io' show HttpDate;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ServerClock {
  static const _prefsKey = 'server_clock_offset_ms';

  /// Smaller drifts than this are not worth a prefs write.
  static const _persistThreshold = Duration(seconds: 2);

  static Duration _offset = Duration.zero;
  static bool _known = false; // an offset was observed or loaded
  static int? _persistedMs;
  static Future<void>? _loading;

  /// Test seam: the device clock.
  @visibleForTesting
  static DateTime Function() deviceNow = DateTime.now;

  /// Server time as far as it is known; the device clock when it never was.
  static DateTime now() => deviceNow().add(_offset);

  static Duration get offset => _offset;

  /// [t] (a server timestamp such as `locked_until`) is still in the future by
  /// server time. Null = not in the future.
  static bool isFuture(DateTime? t) => t != null && t.isAfter(now());

  /// Time left until [t] by server time (zero when past or null).
  static Duration until(DateTime? t) {
    if (t == null) return Duration.zero;
    final d = t.difference(now());
    return d > Duration.zero ? d : Duration.zero;
  }

  /// Loads the persisted offset once (never throws). Call before the first
  /// [now] that matters while offline; later calls are free.
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_prefsKey);
      // A fresher offset observed meanwhile wins over the stored one.
      if (ms != null && !_known) {
        _offset = Duration(milliseconds: ms);
        _persistedMs = ms;
        _known = true;
      }
    } catch (e) {
      debugPrint('ServerClock: could not load the offset: $e');
    }
  }

  /// Learn the offset from a response's `Date` header value. Unparsable or
  /// missing headers are ignored. Fire-and-forget persist.
  static void observe(String? dateHeader) {
    final raw = dateHeader?.trim() ?? '';
    if (raw.isEmpty) return;
    final DateTime server;
    try {
      server = HttpDate.parse(raw);
    } catch (_) {
      return;
    }
    _offset = server.difference(deviceNow().toUtc());
    _known = true;
    final ms = _offset.inMilliseconds;
    final last = _persistedMs;
    if (last != null && (ms - last).abs() < _persistThreshold.inMilliseconds) {
      return;
    }
    _persistedMs = ms;
    _persist(ms);
  }

  static Future<void> _persist(int ms) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, ms);
    } catch (e) {
      debugPrint('ServerClock: could not persist the offset: $e');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _offset = Duration.zero;
    _known = false;
    _persistedMs = null;
    _loading = null;
    deviceNow = DateTime.now;
  }
}
