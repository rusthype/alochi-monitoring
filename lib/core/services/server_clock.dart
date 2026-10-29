// lib/core/services/server_clock.dart
//
// Time-lock checks (`locked_until`) compare a SERVER timestamp with "now". The
// PC's own clock is not trustworthy (a reset to 2000 would lock every scheduled
// test, a clock running ahead would open one early), so "now" is the device
// clock plus an offset learned from the HTTP `Date` header of any successful
// API answer (no backend change) and persisted, so the last known offset also
// holds while offline or after a restart.
//
// A LAN session (teacher's hub) has its own clock: [ServerClock.hub] learns the
// hub's offset from the hub's responses and is NEVER mixed with the cloud one;
// [ServerClock.source] says which one the active session must read.
import 'dart:io' show HttpDate;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One clock's view of "server time minus device time", learned from the
/// `Date` header of its own responses. [ServerClock] keeps two: the cloud API
/// and the teacher's LAN hub. They may run on different clocks, so they are
/// never mixed.
class ClockWitness {
  ClockWitness(this._deviceNow, this._monotonicMs);

  final DateTime Function() _deviceNow;
  final int Function() _monotonicMs;

  Duration _offset = Duration.zero;
  bool _known = false; // an offset was observed or loaded
  int? _lastServerMs;
  int _lastMono = 0;
  int _seq = 0;
  final List<int> _recentUncertainty = [];

  Duration get offset => _offset;
  bool get known => _known;

  /// Accepted server observations (0 = the offset, if any, was only preloaded).
  int get observationCount => _seq;

  /// A `Date` older than the last accepted one (plus the time that passed
  /// since) by more than this is a cached answer, not "now".
  static const _staleTolerance = Duration(minutes: 1);

  /// Error margin (ms) of the `Date`-based offset: the header has 1 s
  /// resolution and reflects the server's send time, so the offset is low by up
  /// to the one-way latency (bounded by the round trip) plus a second. An
  /// unknown round trip counts as [_unknownUncertaintyMs].
  static const _unknownUncertaintyMs = 10 * 1000;
  static const _uncertaintyWindow = 4;

  /// Sets an offset that was not measured in this process (disk). No-op once
  /// something was observed.
  void preload(Duration offset) {
    if (_known) return;
    _offset = offset;
    _known = true;
  }

  /// Learns the offset from a response's `Date` header value; true when it was
  /// accepted. Unparsable or missing headers are ignored.
  ///
  /// A caching proxy can replay an old response: its `Age` header is added to
  /// the `Date` (RFC 9111), and a time that went BACKWARDS compared with what
  /// this process already learned is ignored instead of shifting every
  /// check by hours. (The device clock is deliberately not a reference: a PC
  /// reset to 2000 is exactly what this class corrects.)
  bool observe(String? dateHeader, {String? ageHeader, int? roundTripMs}) {
    final raw = dateHeader?.trim() ?? '';
    if (raw.isEmpty) return false;
    DateTime server;
    try {
      server = HttpDate.parse(raw);
    } catch (_) {
      return false;
    }
    final age = int.tryParse(ageHeader?.trim() ?? '');
    if (age != null && age > 0) server = server.add(Duration(seconds: age));
    final mono = _monotonicMs();
    final prev = _lastServerMs;
    if (prev != null) {
      final expected = prev + (mono - _lastMono);
      if (server.millisecondsSinceEpoch <
          expected - _staleTolerance.inMilliseconds) {
        debugPrint('ServerClock: ignoring a stale Date header ($raw)');
        return false;
      }
    }
    _lastServerMs = server.millisecondsSinceEpoch;
    _lastMono = mono;
    _offset = server.difference(_deviceNow().toUtc());
    _known = true;
    _seq++;
    _recentUncertainty.add(roundTripMs == null || roundTripMs < 0
        ? _unknownUncertaintyMs
        : roundTripMs + 1000);
    if (_recentUncertainty.length > _uncertaintyWindow) {
      _recentUncertainty.removeAt(0);
    }
    return true;
  }

  /// Worst error margin among the latest observations (comparing two offsets
  /// can be off by the larger of their errors); the unknown default when none.
  int get uncertaintyMs => _recentUncertainty.isEmpty
      ? _unknownUncertaintyMs
      : _recentUncertainty.reduce((a, b) => a > b ? a : b);

  void reset() {
    _offset = Duration.zero;
    _known = false;
    _lastServerMs = null;
    _lastMono = 0;
    _seq = 0;
    _recentUncertainty.clear();
  }
}

class ServerClock {
  static const _prefsKey = 'server_clock_offset_ms';

  /// Smaller drifts than this are not worth a prefs write.
  static const _persistThreshold = Duration(seconds: 2);

  /// The cloud API's clock (persisted: it also holds while offline).
  static final ClockWitness _cloud =
      ClockWitness(() => deviceNow(), () => monotonicMs());

  /// The teacher's LAN hub clock. Learned only from the hub's own responses
  /// while a LAN session is active, never persisted (an old hub is no witness)
  /// and never mixed with the cloud offset.
  static final ClockWitness hub =
      ClockWitness(() => deviceNow(), () => monotonicMs());

  static bool _hubActive = false;

  /// `hub` while a LAN client session is active, else `cloud`: which clock
  /// MonitoredClock must read for its server witness.
  static String get source => _hubActive ? 'hub' : 'cloud';

  /// Called by the LAN client session on activate / close. Turning it on
  /// forgets whatever a previous hub taught.
  static void useHub(bool on) {
    if (on) hub.reset();
    _hubActive = on;
  }

  /// The active clock's learned offset and observation count; null until that
  /// clock was actually heard from in THIS process (an offset loaded from disk
  /// may be stale and is no witness; the cloud offset is not the hub's).
  static ({int offsetMs, int seq})? activeSample() {
    final w = _hubActive ? hub : _cloud;
    final n = w.observationCount;
    return n == 0 ? null : (offsetMs: w.offset.inMilliseconds, seq: n);
  }

  /// Error margin of the active clock's latest observations.
  static int get activeUncertaintyMs =>
      (_hubActive ? hub : _cloud).uncertaintyMs;

  static int? _persistedMs;
  static bool _loaded = false;

  /// Test seam: the device clock.
  @visibleForTesting
  static DateTime Function() deviceNow = DateTime.now;

  /// Server time as far as it is known; the device clock when it never was.
  /// (Cloud time: time locks are scheduled by the cloud API.)
  static DateTime now() => deviceNow().add(_cloud.offset);

  static Duration get offset => _cloud.offset;

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
      if (ms != null && !_cloud.known) {
        _persistedMs = ms;
        _cloud.preload(Duration(milliseconds: ms));
      }
    } catch (e) {
      debugPrint('ServerClock: could not load the offset: $e');
    }
  }

  /// Test seam: monotonic milliseconds (immune to device clock changes).
  @visibleForTesting
  static int Function() monotonicMs = () => _watch.elapsedMilliseconds;
  static final Stopwatch _watch = Stopwatch()..start();

  /// Accepted CLOUD server observations in this process (0 = the offset, if
  /// any, was only loaded from disk).
  static int get observationCount => _cloud.observationCount;

  /// Learn the cloud offset from a response's `Date` header value. Unparsable,
  /// stale or missing headers are ignored. Fire-and-forget persist.
  static void observe(String? dateHeader,
      {String? ageHeader, int? roundTripMs}) {
    if (!_cloud.observe(dateHeader,
        ageHeader: ageHeader, roundTripMs: roundTripMs)) {
      return;
    }
    final ms = _cloud.offset.inMilliseconds;
    final last = _persistedMs;
    if (last != null && (ms - last).abs() < _persistThreshold.inMilliseconds) {
      return;
    }
    _persistedMs = ms;
    _persist(ms);
  }

  /// Worst error margin among the latest CLOUD observations.
  static int get uncertaintyMs => _cloud.uncertaintyMs;

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
    _cloud.reset();
    hub.reset();
    _hubActive = false;
    _persistedMs = null;
    _loaded = false;
    deviceNow = DateTime.now;
    monotonicMs = () => _watch.elapsedMilliseconds;
  }
}
