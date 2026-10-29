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
// SLEEP / SUSPEND: a monotonic source may stop while the PC is suspended
// (macOS `mach_absolute_time` / Dart [Stopwatch] does; Windows
// `GetTickCount64` is believed not to - unverified on hardware), which would
// hand the student the slept time back. [absorbSuspend] compares wall time
// with ticks since the last agreement and, when the wall clock ran ahead by
// more than [skewThresholdMs], believes the LARGER (wall) elapsed time - the
// same "larger of tick and wall" rule as [rebaseSavedDeadline]. A wall clock
// that went back, or a jump above [_maxSuspendCreditMs] (dead-CMOS reset,
// NTP fixing the year), is never credited, so time is only ever taken, never
// added. A date moved forward by hand is indistinguishable from a sleep and
// is credited the same way - unless SERVER TIME is available as a witness: a
// real suspend leaves the device-to-server offset unchanged (the server's
// clock advanced by the same gap), a manual date change moves it by the shift.
// [absorbSuspend] then holds the credit back until a server measurement taken
// AFTER the jump arrives (it triggers [probeServer]) and credits only the part
// the server confirms as elapsed. Offline / no measurement within
// [_serverWaitMs]: the behaviour above, unchanged. A gap the server confirms
// (offset unchanged) may be longer than the offline cap, up to
// [_maxConfirmedSuspendMs]. A suspend hidden by a wall clock reset (wall and
// ticks agree, so no jump is seen) shows only as a fresh server observation
// whose offset moved: [absorbSuspend] credits that movement too.
import 'dart:async';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/server_clock.dart';

typedef TicksFn = int Function();
typedef WallFn = int Function();

/// The learned device-to-server offset ([offsetMs] = server - device wall) and
/// how many server observations this process has made ([seq]).
typedef ServerSample = ({int offsetMs, int seq});
typedef ServerSampleFn = ServerSample? Function();

/// Null until the server was actually heard from in THIS process (an offset
/// loaded from disk may be stale and is no witness).
///
/// Which clock this is (cloud API vs the LAN hub) follows the active session
/// ([ServerClock.source]); the two offsets are never mixed.
ServerSample? _serverClockSample() => ServerClock.activeSample();

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
  final ServerSampleFn _server;

  /// Which server clock [_server] reads right now: `cloud` or `hub`. A server
  /// witness is only comparable with one of the SAME source.
  final String Function() _source;
  late String _lastSource;

  /// Worst-case error (ms) of a device-to-server offset measurement: the
  /// `Date` header has 1 s resolution and arrives a round trip late.
  final int Function() _uncertainty;

  /// Asks for a fresh server measurement (a cheap ping whose `Date` header
  /// ServerClock reads). Fire-and-forget; wired by the test engine.
  void Function()? probeServer;

  /// Device-to-server offset movement that counts as the clock having been
  /// changed (the `Date` header has 1 s resolution). Widened per measurement
  /// by the observation's own uncertainty, see [_offsetToleranceMs].
  static const int _offsetAgreeToleranceMs = 5 * 1000;

  /// A server-confirmed suspend may exceed [_maxSuspendCreditMs]; this is the
  /// sanity ceiling.
  static const int _maxConfirmedSuspendMs = 7 * 24 * 60 * 60 * 1000;

  /// A baseline server sample older than this (monotonic ms) is not compared
  /// with a new observation: slow device-vs-server drift would look like a
  /// clock change.
  static const int _baselineMaxAgeMs = 60 * 1000;

  /// How long a jump waits for a server measurement before the offline rule
  /// applies.
  static const int _serverWaitMs = 10 * 1000;

  /// Persist the high-water mark at most this often (monotonic ms).
  static const int _hwmWriteEveryMs = 60 * 1000;

  /// A saved attempt older than this (in ticks) is treated as "different boot".
  static const int _maxRebaseElapsedMs = 12 * 60 * 60 * 1000;
  static const int _clockBackTolerance = 60 * 1000;
  /// A wall-vs-ticks gap above this is a clock reset / NTP year fix, not a
  /// sleep: ignored (matches [_maxRebaseElapsedMs]).
  static const int _maxSuspendCreditMs = _maxRebaseElapsedMs;
  /// Trusted-clock vs tick elapsed time may differ by this much (NTP step or
  /// drift between two processes) before the larger one is believed.
  static const int _wallAgreeTolerance = 5 * 60 * 1000;

  MonitoredClock({
    TicksFn? ticks,
    WallFn? wall,
    HighWaterStore? highWaterStore,
    ServerSampleFn? serverSample,
    String Function()? serverSource,
    int Function()? offsetUncertaintyMs,
    this.probeServer,
    this.skewThresholdMs = 5000,
    this.checkEvery = const Duration(seconds: 5),
  })  : _ticks = ticks ?? platformTicksMs,
        _wall = wall ?? (() => DateTime.now().millisecondsSinceEpoch),
        _hwm = highWaterStore ?? const SecureHighWaterStore(),
        _server = serverSample ?? _serverClockSample,
        _source = serverSource ?? (() => ServerClock.source),
        _uncertainty =
            offsetUncertaintyMs ?? (() => ServerClock.activeUncertaintyMs) {
    _anchorWall = _wall();
    _anchorTicks = _ticks();
    _lastCheckWall = _anchorWall;
    _lastCheckTicks = _anchorTicks;
    _syncWall = _anchorWall;
    _syncTicks = _anchorTicks;
    _baseline = _server();
    _baselineTicks = _anchorTicks;
    _lastSource = _source();
  }

  /// Production singleton. Tests replace it with a fake-driven instance.
  static MonitoredClock instance = MonitoredClock();

  late final int _anchorWall;
  late final int _anchorTicks;
  late int _lastCheckWall;
  late int _lastCheckTicks;
  // Last point where wall time and ticks were believed to agree
  // ([absorbSuspend]) and the suspended time credited to [nowMs] since.
  late int _syncWall;
  late int _syncTicks;
  int _suspendCreditMs = 0;
  // Server offset at the last tick without a jump, and the jump (if any) still
  // waiting for a post-jump server measurement.
  ServerSample? _baseline;
  late int _baselineTicks;
  ({int skew, ServerSample base, int seq, int sinceTicks})? _pending;
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
  int get nowMs => _anchorWall + (_ticks() - _anchorTicks) + _suspendCreditMs;

  DateTime get nowUtc =>
      DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);

  /// What the (possibly tampered) system clock says right now.
  int get wallMs => _wall();

  // ── resume across a process restart ────────────────────────────────────────

  /// The wall clock still agrees with the ticks since the last agreement. The
  /// server offset was learned from an earlier wall reading, so it is only
  /// valid for `wall + offset` while the wall clock has not moved since.
  bool get _wallConsistent =>
      ((_wall() - _syncWall) - (_ticks() - _syncTicks)).abs() <=
      skewThresholdMs;

  /// The server sample, only while it is a usable witness: heard from in this
  /// process, no jump awaiting its verdict, and the wall clock not moved since.
  ServerSample? _witness() =>
      _pending == null && _wallConsistent ? _server() : null;

  /// Offset movement that still counts as "unchanged".
  int get _offsetToleranceMs =>
      math.max(_offsetAgreeToleranceMs, _uncertainty());

  /// Values to persist next to a deadline so a restart can rebase it.
  ///
  /// `server_epoch_at_save_ms` (server time at the save, when the server was
  /// heard from in this process and no clock jump is awaiting verification)
  /// is the independent witness [rebaseSavedDeadline] uses while online;
  /// records without it use the tick / trusted-clock rule.
  Map<String, int> snapshot() {
    final s = _witness();
    return {
      'epoch_at_save': nowMs,
      'ticks_at_save': ticksMs,
      if (s != null) 'server_epoch_at_save_ms': _wall() + s.offsetMs,
    };
  }

  /// [snapshot] plus `server_source` (`cloud` | `hub`) whenever a server witness
  /// is stored: the engine / recovery records persist this one, so a restart
  /// never compares a hub timestamp with a cloud offset. A record without
  /// `server_source` is a cloud witness (written before hub offsets existed).
  Map<String, Object> snapshotRecord() {
    final snap = snapshot();
    return {
      ...snap,
      if (snap.containsKey('server_epoch_at_save_ms')) 'server_source': _source(),
    };
  }

  /// Re-expresses a deadline that was persisted by an earlier process in THIS
  /// process's trusted timeline.
  ///
  /// There is no boot id, so "same boot" is inferred from the monotonic ticks
  /// not having gone backwards (and not being absurdly far apart). Because a
  /// reboot can leave the ticks looking continuous (saved 30 min after boot 1,
  /// returned 45 min after boot 2), the elapsed time is the LARGER of the tick
  /// delta and the trusted-clock delta whenever those disagree by more than
  /// [_wallAgreeTolerance]: the student is never granted more time than the
  /// larger of the two says has passed. (A date moved BACK is therefore
  /// ignored; a date moved forward while the app was closed shortens the
  /// attempt - self-inflicted, and the answers are submitted, not lost.)
  ///
  /// A wall gap above [_maxSuspendCreditMs] on the same boot is ignored (see
  /// the branch below); on a different boot the wall delta always counts.
  ///
  /// SERVER WITNESS: with [serverEpochAtSaveMs] and a server measurement from
  /// this process, the elapsed time is server-now minus server-at-save on the
  /// server's own timeline - authoritative over ticks and wall (an overnight
  /// same-boot gap, a date change, a reboot all read correctly); negative is
  /// clamped to 0 so no extra time is ever granted.
  ///
  /// Ticks unusable (reboot with smaller uptime, > 12 h apart, or a legacy
  /// record without a snapshot): the stored epoch deadline is used, so
  /// power-off time counts and a long abandonment is expired (the recovery
  /// sweep / engine then auto-submits the saved answers). One guard remains
  /// for a PC whose RTC is wrong after a power cut: the clock reads EARLIER
  /// than the save time by more than [_clockBackTolerance] (reset to 1970/2000
  /// or moved back) - granting `deadline - now` would hand out decades, so the
  /// REMAINING time recorded at save is kept instead.
  int rebaseSavedDeadline({
    required int deadlineEpochMs,
    int? epochAtSaveMs,
    int? ticksAtSaveMs,
    int? serverEpochAtSaveMs,
    String? serverSourceAtSave,
  }) {
    if (epochAtSaveMs == null || ticksAtSaveMs == null) return deadlineEpochMs;
    final remainingAtSave = deadlineEpochMs - epochAtSaveMs;
    // A witness saved against the cloud clock says nothing about the hub's (and
    // vice versa): ignored on a source mismatch, the tick rule applies.
    final sameSource = (serverSourceAtSave ?? 'cloud') == _source();
    final server =
        serverEpochAtSaveMs == null || !sameSource ? null : _witness();
    if (serverEpochAtSaveMs != null && server != null) {
      final elapsed = _wall() + server.offsetMs - serverEpochAtSaveMs;
      return nowMs + remainingAtSave - (elapsed < 0 ? 0 : elapsed);
    }
    final tickElapsed = ticksMs - ticksAtSaveMs;
    final sinceSave = nowMs - epochAtSaveMs;
    if (tickElapsed >= 0 && tickElapsed <= _maxRebaseElapsedMs) {
      // Same boot: the ticks are authoritative. The wall delta is believed only
      // while it exceeds them by a suspend-sized amount ([_maxSuspendCreditMs],
      // as in [absorbSuspend]); a bigger gap is an NTP / dead-CMOS year step
      // between the save and this process (nowMs is anchored to the wall clock
      // once, at start) and credits nothing - it must not expire a live attempt.
      final gap = sinceSave - tickElapsed;
      final elapsed = gap > _wallAgreeTolerance && gap <= _maxSuspendCreditMs
          ? sinceSave
          : tickElapsed;
      return nowMs + remainingAtSave - elapsed;
    }
    if (sinceSave < -_clockBackTolerance) return nowMs + remainingAtSave;
    return deadlineEpochMs;
  }

  // ── skew / high-water-mark monitoring ──────────────────────────────────────

  /// Credits time the PC spent suspended (wall ran ahead of the ticks by more
  /// than [skewThresholdMs]) to [nowMs]; returns the ms credited. Call on every
  /// countdown tick and on resume. Wall behind the ticks, or ahead by more
  /// than [_maxSuspendCreditMs], credits nothing (the baseline is re-agreed).
  /// A small gap (NTP slew, a few seconds) is left to accumulate until it is
  /// big enough to be believed, then credited in full.
  int absorbSuspend() {
    // The active server clock changed (a LAN session opened / closed): the
    // baseline and a verdict waiting for a measurement belong to the OTHER
    // clock and are not comparable with the next one.
    var carried = 0;
    final source = _source();
    if (source != _lastSource) {
      _lastSource = source;
      _baseline = null;
      _baselineTicks = _ticks();
      final held = _pending;
      _pending = null;
      // No verdict can arrive any more: the offline rule applies.
      if (held != null) carried = _creditSuspend(held.skew);
    }
    return carried + _absorbSuspend();
  }

  int _absorbSuspend() {
    final wall = _wall();
    final ticks = _ticks();
    final skew = (wall - _syncWall) - (ticks - _syncTicks);
    final jump = skew.abs() > skewThresholdMs;
    if (jump) {
      _syncWall = wall;
      _syncTicks = ticks;
    }
    final sample = _server();
    final pending = _pending;
    if (pending == null) {
      if (!jump) {
        final base = _baseline;
        final baseTicks = _baselineTicks;
        _baseline = sample;
        _baselineTicks = ticks;
        // Wall and ticks agree, yet a NEW measurement says the offset moved
        // up: the PC slept (ticks frozen) and the wall was put back. Only a
        // positive move counts - a negative one cannot be a sleep.
        if (base != null &&
            sample != null &&
            sample.seq > base.seq &&
            ticks - baseTicks <= _baselineMaxAgeMs) {
          final moved = sample.offsetMs - base.offsetMs;
          if (moved > _offsetToleranceMs) return _settleJump(skew, moved);
        }
        return 0;
      }
      final base = _baseline;
      // No witness (offline, or the server never heard from in this process):
      // the plain suspend rule.
      if (base == null || sample == null) return _creditSuspend(skew);
      _hold(skew: skew, base: base, seq: sample.seq, ticks: ticks);
      return 0;
    }
    if (jump) {
      // A second jump while waiting: one verdict for both.
      _hold(
          skew: pending.skew + skew,
          base: pending.base,
          seq: sample?.seq ?? pending.seq,
          ticks: pending.sinceTicks);
      return 0;
    }
    if (sample != null && sample.seq > pending.seq) {
      _pending = null;
      _baseline = sample;
      _baselineTicks = ticks;
      return _settleJump(pending.skew, sample.offsetMs - pending.base.offsetMs);
    }
    if (ticks - pending.sinceTicks >= _serverWaitMs) {
      _pending = null;
      return _creditSuspend(pending.skew);
    }
    return 0;
  }

  void _hold(
      {required int skew,
      required ServerSample base,
      required int seq,
      required int ticks}) {
    _pending = (skew: skew, base: base, seq: seq, sinceTicks: ticks);
    try {
      probeServer?.call();
    } catch (e) {
      debugPrint('MonitoredClock: server probe failed (non-fatal): $e');
    }
  }

  /// The pre-witness rule: wall ahead of the ticks by a suspend-sized amount
  /// is slept time; wall behind, or a year-sized step, credits nothing.
  int _creditSuspend(int skew, {bool confirmed = false}) {
    final cap = confirmed ? _maxConfirmedSuspendMs : _maxSuspendCreditMs;
    if (skew < 0 || skew > cap) return 0;
    _suspendCreditMs += skew;
    return skew;
  }

  /// A jump of [skew] (wall minus ticks) whose device-to-server offset moved by
  /// [offsetDelta]. Unmoved: real elapsed time. Moved: the clock was changed;
  /// only what the server says really elapsed ([skew] + [offsetDelta], 0 for a
  /// pure date change) is credited, and the change is flagged.
  int _settleJump(int skew, int offsetDelta) {
    if (offsetDelta.abs() <= _offsetToleranceMs) {
      return _creditSuspend(skew, confirmed: true);
    }
    final real = skew + offsetDelta;
    _addFlag({
      'type': 'clock_change_server_confirmed',
      'skew_ms': skew,
      'offset_delta_ms': offsetDelta,
      'trusted_utc': _iso(nowMs),
    });
    return real > skewThresholdMs ? _creditSuspend(real, confirmed: true) : 0;
  }

  /// Drops a clock-jump verdict still waiting for its server measurement.
  /// For callers that rebuild their deadline from [nowMs] right after
  /// [absorbSuspend] (screen start, lock pause / resume): the held time is not
  /// theirs to lose or gain, and a late verdict would land inside the rebuilt
  /// deadline.
  void discardPending() => _pending = null;

  /// Starts the periodic check (reference counted so nested screens are safe).
  void startMonitoring() {
    // Whatever happened before this screen opened (an idle laptop that slept on
    // the login screen) is not part of the test: agree the baseline first.
    if (_monitors == 0) {
      absorbSuspend();
      // A verdict still pending from before this screen would land inside the
      // test: that time is not the test's.
      discardPending();
    }
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
    final out = pendingFlags;
    _flags.clear();
    _droppedFlags = 0;
    return out;
  }

  /// What [drainFlags] would return now, including the overflow counter item
  /// (so a size measured from this is what the drain will really write).
  List<Map<String, dynamic>> get pendingFlags => [
        ..._flags,
        if (_droppedFlags > 0)
          {'type': 'clock_flags_overflow', 'dropped': _droppedFlags},
      ];

  static String _iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
}
