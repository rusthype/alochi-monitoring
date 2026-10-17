// lib/core/security/monitored_clock.dart
//
// A clock that survives the student changing the system date/time mid-test.
//
//  * Durations / deadlines come from a MONOTONIC source: Windows
//    `GetTickCount64()` (ms since boot, unaffected by "set date and time"),
//    falling back to a process-wide [Stopwatch] elsewhere. [nowMs] is a
//    "trusted epoch": the wall clock sampled once at first use plus the
//    monotonic delta since — so test_engine.dart can keep its epoch-ms
//    deadline maths while no longer following wall-clock jumps.
//  * Every [checkEvery] the wall-clock delta is compared with the monotonic
//    delta; a difference above [skewThreshold] is RECORDED as a clock flag.
//  * A high-water mark of the latest wall time ever seen is kept in secure
//    storage; a wall clock behind it (or behind the pack's `created_at`) is
//    recorded as a flag.
//
// Decision 8 of the offline plan: flags are metadata for the teacher/boss —
// nothing here ever blocks or ends a test.
//
// KNOWN LIMITATION (sleep / hibernation): whether Windows' `GetTickCount64`
// keeps counting while the PC is suspended is NOT verified on hardware here.
// If it excludes suspended time, a student could close the lid mid-test and
// the countdown would not advance meanwhile (extra time); the wall-vs-monotonic
// skew check would then record a `clock_forward` flag on resume, but the test
// is not shortened. This is documented, not solved.
import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef TicksFn = int Function();
typedef WallFn = int Function();

/// Persistence for the wall-clock high-water mark.
abstract class HighWaterStore {
  Future<DateTime?> read();
  Future<void> write(DateTime utc);
}

class SecureHighWaterStore implements HighWaterStore {
  static const _key = 'last_known_max_utc';
  static const _storage = FlutterSecureStorage(
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  );
  const SecureHighWaterStore();

  @override
  Future<DateTime?> read() async {
    try {
      final v = await _storage.read(key: _key);
      return v == null ? null : DateTime.tryParse(v)?.toUtc();
    } catch (e) {
      debugPrint('SecureHighWaterStore.read failed (non-fatal): $e');
      return null;
    }
  }

  @override
  Future<void> write(DateTime utc) async {
    try {
      await _storage.write(key: _key, value: utc.toUtc().toIso8601String());
    } catch (e) {
      debugPrint('SecureHighWaterStore.write failed (non-fatal): $e');
    }
  }
}

/// Process-wide monotonic milliseconds. Windows: GetTickCount64 (since boot);
/// otherwise a [Stopwatch] started on first use.
int platformTicksMs() => _platformTicks();

int Function()? _winTicks;
final Stopwatch _fallbackWatch = Stopwatch()..start();

int _platformTicks() {
  if (!kIsWeb && Platform.isWindows) {
    try {
      _winTicks ??= DynamicLibrary.open('kernel32.dll')
          .lookupFunction<Uint64 Function(), int Function()>('GetTickCount64');
      return _winTicks!();
    } catch (e) {
      debugPrint('GetTickCount64 unavailable, using Stopwatch: $e');
      _winTicks = () => _fallbackWatch.elapsedMilliseconds;
    }
  }
  return _fallbackWatch.elapsedMilliseconds;
}

class MonitoredClock {
  /// Wall-vs-monotonic drift (ms) over one check interval that counts as a
  /// clock change.
  final int skewThresholdMs;
  final Duration checkEvery;
  final TicksFn _ticks;
  final WallFn _wall;
  final HighWaterStore _hwm;

  /// Persist the high-water mark at most this often (monotonic ms).
  static const int _hwmWriteEveryMs = 60 * 1000;

  /// A saved attempt older than this (in ticks) is treated as "different boot".
  static const int _maxRebaseElapsedMs = 12 * 60 * 60 * 1000;

  MonitoredClock({
    TicksFn? ticks,
    WallFn? wall,
    HighWaterStore? highWaterStore,
    this.skewThresholdMs = 5000,
    this.checkEvery = const Duration(seconds: 5),
  })  : _ticks = ticks ?? platformTicksMs,
        _wall = wall ?? (() => DateTime.now().millisecondsSinceEpoch),
        _hwm = highWaterStore ?? const SecureHighWaterStore() {
    _anchorWall = _wall();
    _anchorTicks = _ticks();
    _lastCheckWall = _anchorWall;
    _lastCheckTicks = _anchorTicks;
  }

  /// Production singleton. Tests replace it with a fake-driven instance.
  static MonitoredClock instance = MonitoredClock();

  late final int _anchorWall;
  late final int _anchorTicks;
  late int _lastCheckWall;
  late int _lastCheckTicks;
  int? _lastHwmWriteTicks;
  Timer? _timer;
  int _monitors = 0;

  /// Set by the offline pack session: a wall clock earlier than this means the
  /// date was set back before the pack even existed.
  DateTime? packCreatedAt;

  /// Bound on stored flags per attempt; further ones are counted, not lost
  /// silently (a `clock_flags_overflow` entry is appended on drain).
  static const int _maxFlags = 100;
  final List<Map<String, dynamic>> _flags = [];
  int _droppedFlags = 0;

  void _addFlag(Map<String, dynamic> flag) {
    if (_flags.length >= _maxFlags) {
      _droppedFlags++;
      return;
    }
    _flags.add(flag);
  }

  // ── time ───────────────────────────────────────────────────────────────────

  /// Raw monotonic milliseconds (only differences are meaningful).
  int get ticksMs => _ticks();

  /// Trusted epoch milliseconds: wall time at first use + monotonic delta.
  /// Unlike `DateTime.now()` this does NOT move when the user edits the date.
  int get nowMs => _anchorWall + (_ticks() - _anchorTicks);

  DateTime get nowUtc =>
      DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);

  /// What the (possibly tampered) system clock says right now.
  int get wallMs => _wall();

  // ── resume across a process restart ────────────────────────────────────────

  /// Values to persist next to a deadline so a restart can rebase it.
  Map<String, int> snapshot() =>
      {'epoch_at_save': nowMs, 'ticks_at_save': ticksMs};

  /// Re-expresses a deadline that was persisted by an earlier process in THIS
  /// process's trusted timeline.
  ///
  /// Same boot (ticks did not go backwards): remaining time is the saved
  /// remaining minus the monotonic time that passed, immune to a date change
  /// while the app was closed. Otherwise (reboot, or a legacy record without
  /// a snapshot) the stored epoch deadline is used unchanged.
  int rebaseSavedDeadline({
    required int deadlineEpochMs,
    int? epochAtSaveMs,
    int? ticksAtSaveMs,
  }) {
    if (epochAtSaveMs == null || ticksAtSaveMs == null) return deadlineEpochMs;
    final elapsed = ticksMs - ticksAtSaveMs;
    if (elapsed < 0 || elapsed > _maxRebaseElapsedMs) return deadlineEpochMs;
    final remaining = deadlineEpochMs - epochAtSaveMs - elapsed;
    return nowMs + remaining;
  }

  // ── skew / high-water-mark monitoring ──────────────────────────────────────

  /// Starts the periodic check (reference counted so nested screens are safe).
  void startMonitoring() {
    _monitors++;
    if (_timer != null) return;
    _lastCheckWall = _wall();
    _lastCheckTicks = _ticks();
    _timer = Timer.periodic(checkEvery, (_) => checkNow());
  }

  void stopMonitoring() {
    if (_monitors > 0) _monitors--;
    if (_monitors == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// One skew check. Public so tests can drive it with fake time.
  void checkNow() {
    final wall = _wall();
    final ticks = _ticks();
    final dWall = wall - _lastCheckWall;
    final dMono = ticks - _lastCheckTicks;
    final skew = dWall - dMono;
    if (skew.abs() > skewThresholdMs) {
      _addFlag({
        'type': skew > 0 ? 'clock_forward' : 'clock_backward',
        'skew_ms': skew,
        'wall_delta_ms': dWall,
        'monotonic_delta_ms': dMono,
        'wall_utc': _iso(wall),
        'trusted_utc': _iso(nowMs),
      });
    }
    _lastCheckWall = wall;
    _lastCheckTicks = ticks;
    final lastWrite = _lastHwmWriteTicks;
    if (lastWrite == null || ticks - lastWrite >= _hwmWriteEveryMs) {
      unawaited(_raiseHighWaterMark(wall));
    }
  }

  /// Compares the system clock with the stored high-water mark and the pack's
  /// `created_at`; records a flag for each violation and advances the mark.
  Future<void> checkHighWaterMark() async {
    final wall = _wall();
    final seen = await _hwm.read();
    if (seen != null && wall < seen.millisecondsSinceEpoch - skewThresholdMs) {
      _addFlag({
        'type': 'clock_before_high_water_mark',
        'high_water_utc': seen.toIso8601String(),
        'wall_utc': _iso(wall),
      });
    }
    final created = packCreatedAt;
    if (created != null && wall < created.millisecondsSinceEpoch) {
      _addFlag({
        'type': 'clock_before_pack_created',
        'pack_created_utc': created.toUtc().toIso8601String(),
        'wall_utc': _iso(wall),
      });
    }
    await _raiseHighWaterMark(wall);
  }

  Future<void> _raiseHighWaterMark(int wall) async {
    _lastHwmWriteTicks = _ticks();
    final seen = await _hwm.read();
    if (seen == null || wall > seen.millisecondsSinceEpoch) {
      await _hwm.write(DateTime.fromMillisecondsSinceEpoch(wall, isUtc: true));
    }
  }

  /// Returns the flags recorded since the last call and clears them.
  List<Map<String, dynamic>> drainFlags() {
    final out = List<Map<String, dynamic>>.from(_flags);
    if (_droppedFlags > 0) {
      out.add({'type': 'clock_flags_overflow', 'dropped': _droppedFlags});
    }
    _flags.clear();
    _droppedFlags = 0;
    return out;
  }

  List<Map<String, dynamic>> get pendingFlags => List.unmodifiable(_flags);

  static String _iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
}
