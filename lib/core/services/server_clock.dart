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
  static bool _loaded = false;

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
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _load();
  }

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _loaded = true;
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

  /// Test seam: monotonic milliseconds (immune to device clock changes).
  @visibleForTesting
  static int Function() monotonicMs = () => _watch.elapsedMilliseconds;
  static final Stopwatch _watch = Stopwatch()..start();

  /// Server time (epoch ms) of the last accepted observation and the
  /// monotonic reading it was taken at.
  static int? _lastServerMs;
  static int _lastMono = 0;

  /// Accepted server observations in this process (0 = the offset, if any,
  /// was only loaded from disk). Lets a caller wait for a MEASUREMENT taken
  /// after some event, e.g. [MonitoredClock] verifying a clock jump.
  static int _seq = 0;
  static int get observationCount => _seq;

  /// A `Date` older than the last accepted one (plus the time that passed
  /// since) by more than this is a cached answer, not "now".
  static const _staleTolerance = Duration(minutes: 1);

  /// Learn the offset from a response's `Date` header value. Unparsable or
  /// missing headers are ignored. Fire-and-forget persist.
  ///
  /// A caching proxy can replay an old response: its `Age` header is added to
  /// the `Date` (RFC 9111), and a time that went BACKWARDS compared with what
  /// this process already learned is ignored instead of shifting every
  /// `locked_until` check by hours. (The device clock is deliberately not a
  /// reference: a PC reset to 2000 is exactly what this class corrects.)
  static void observe(String? dateHeader,
      {String? ageHeader, int? roundTripMs}) {
    final raw = dateHeader?.trim() ?? '';
    if (raw.isEmpty) return;
    DateTime server;
    try {
      server = HttpDate.parse(raw);
    } catch (_) {
      return;
    }
    final age = int.tryParse(ageHeader?.trim() ?? '');
    if (age != null && age > 0) server = server.add(Duration(seconds: age));
    final mono = monotonicMs();
    final prev = _lastServerMs;
    if (prev != null) {
      final expected = prev + (mono - _lastMono);
      if (server.millisecondsSinceEpoch <
          expected - _staleTolerance.inMilliseconds) {
        debugPrint('ServerClock: ignoring a stale Date header ($raw)');
        return;
      }
    }
    _lastServerMs = server.millisecondsSinceEpoch;
    _lastMono = mono;
    _offset = server.difference(deviceNow().toUtc());
    _known = true;
    _seq++;
    _recordUncertainty(roundTripMs);
    final ms = _offset.inMilliseconds;
    final last = _persistedMs;
    if (last != null && (ms - last).abs() < _persistThreshold.inMilliseconds) {
      return;
    }
    _persistedMs = ms;
    _persist(ms);
  }

  /// Error margin (ms) of the `Date`-based offset: the header has 1 s
  /// resolution and reflects the server's send time, so the offset is low by up
  /// to the one-way latency (bounded by the round trip) plus a second. An
  /// unknown round trip counts as [_unknownUncertaintyMs].
  static const _unknownUncertaintyMs = 10 * 1000;
  static const _uncertaintyWindow = 4;
  static final List<int> _recentUncertainty = [];

  static void _recordUncertainty(int? roundTripMs) {
    _recentUncertainty.add(roundTripMs == null || roundTripMs < 0
        ? _unknownUncertaintyMs
        : roundTripMs + 1000);
    if (_recentUncertainty.length > _uncertaintyWindow) {
      _recentUncertainty.removeAt(0);
    }
  }

  /// Worst error margin among the latest observations (comparing two offsets
  /// can be off by the larger of their errors); the unknown default when none.
  static int get uncertaintyMs => _recentUncertainty.isEmpty
      ? _unknownUncertaintyMs
      : _recentUncertainty.reduce((a, b) => a > b ? a : b);

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
    _loaded = false;
    _lastServerMs = null;
    _seq = 0;
    _recentUncertainty.clear();
    deviceNow = DateTime.now;
    monotonicMs = () => _watch.elapsedMilliseconds;
  }
}
