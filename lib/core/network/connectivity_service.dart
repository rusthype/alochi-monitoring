// lib/core/network/connectivity_service.dart
//
// Latency-based signal-strength probe for the backend, independent from
// HeartbeatService (session-presence heartbeat, 30s, hits /session-ping/)
// and SyncService (offline-queue flush trigger, 60s, only pings when a
// queue is pending). This service exists purely to answer "how good is the
// connection right now" for a UI indicator — it owns its own single
// Timer.periodic and never reacts to the other services' timers/streams.
import 'dart:async';
import '../api/api_client.dart';

/// 5-value latency bucket. `none` covers both a failed request and a
/// timeout — rendered as a red X by the UI, never as "0 bars" alongside the
/// other tiers. The remaining 4 values are ascending signal quality.
enum SignalTier { none, weak, fair, good, excellent }

class SignalReading {
  final SignalTier tier;
  final int? latencyMs;
  final DateTime measuredAt;
  // True only for the synthetic initial reading emitted before the first
  // measurement completes — lets the UI show a neutral "checking..." state
  // instead of flashing "offline" while the very first ping is in flight.
  final bool checking;

  const SignalReading({
    required this.tier,
    required this.latencyMs,
    required this.measuredAt,
    this.checking = false,
  });
}

/// A delay that a caller can force to complete right now via `cancel()`,
/// instead of waiting for its Timer to fire. `cancel()` completes the
/// Completer directly — it does NOT just cancel the backing Timer, because
/// `Timer.cancel()` skips the timer's callback entirely, and that callback
/// was the only thing that would have completed the Future. Cancelling the
/// Timer without also completing the Completer leaves the `await`er
/// hanging forever. Each call gets its own Completer/Timer pair (no shared
/// mutable field), so concurrent delays never step on each other.
({Future<void> future, void Function() cancel}) cancellableDelay(Duration d) {
  final completer = Completer<void>();
  final timer = Timer(d, () {
    if (!completer.isCompleted) completer.complete();
  });
  return (
    future: completer.future.whenComplete(timer.cancel),
    cancel: () {
      if (!completer.isCompleted) completer.complete();
    },
  );
}

/// Pings up to twice: a single transient failure (DNS blip, a response
/// that just barely misses [timeout], a transient 429/5xx) shouldn't read
/// the same as being genuinely offline. Only reports failure if BOTH
/// attempts fail. Latency is always the timing of the attempt that decided
/// the result, so a successful retry isn't penalized with a worse tier for
/// having needed one. Takes the ping call as a parameter (same seam as
/// `checkOnlineWithRetry` in login_screen.dart) so it's testable without a
/// real network call.
Future<({bool ok, int elapsedMs})> pingWithRetry(
  Future<bool> Function() ping, {
  required Duration timeout,
  required Duration retryDelay,
  // Overridable so ConnectivityService can back it with a cancellable
  // Timer (dispose() needs to be able to cut the wait short instead of
  // leaving a bare Future.delayed running); tests pass Duration.zero and
  // never touch this.
  Future<void> Function(Duration)? delay,
}) async {
  final wait = delay ?? (d) => Future.delayed(d);
  for (var attempt = 0; attempt < 2; attempt++) {
    final stopwatch = Stopwatch()..start();
    bool ok;
    try {
      ok = await ping().timeout(timeout, onTimeout: () => false);
    } catch (_) {
      ok = false;
    }
    stopwatch.stop();
    if (ok || attempt == 1) {
      return (ok: ok, elapsedMs: stopwatch.elapsedMilliseconds);
    }
    await wait(retryDelay);
  }
  throw StateError('unreachable'); // loop always returns on attempt == 1
}

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  static const Duration _interval = Duration(seconds: 15);
  static const Duration _timeout = Duration(seconds: 3);
  // Gap between the 2 attempts within one _measure() cycle. Worst case
  // (both attempts time out): timeout + _retryDelay + timeout ≈ 6.9s,
  // comfortably under the 15s _interval between cycles.
  static const Duration _retryDelay = Duration(milliseconds: 900);

  Timer? _timer;
  // Each in-flight retry wait registers its `cancel` callback here (added
  // in _cancellableDelay, removed once the wait resolves) so dispose() can
  // force-complete every one of them, not just the most recent — a single
  // shared Timer field would let a concurrent refresh()/periodic _measure()
  // overwrite the other's reference.
  final Set<void Function()> _pendingRetryCancels = {};
  bool _started = false;

  final StreamController<SignalReading> _controller =
      StreamController<SignalReading>.broadcast();

  SignalReading _last = SignalReading(
    tier: SignalTier.none,
    latencyMs: null,
    measuredAt: DateTime.now(),
    checking: true,
  );

  Stream<SignalReading> get readings => _controller.stream;
  SignalReading get last => _last;

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(_interval, (_) => _measure());
    unawaited(_measure());
  }

  Future<void> refresh() => _measure();

  Future<void> _cancellableDelay(Duration d) {
    final gate = cancellableDelay(d);
    _pendingRetryCancels.add(gate.cancel);
    return gate.future.whenComplete(() => _pendingRetryCancels.remove(gate.cancel));
  }

  Future<void> _measure() async {
    final result = await pingWithRetry(
      () => api.ping(),
      timeout: _timeout,
      retryDelay: _retryDelay,
      delay: _cancellableDelay,
    );

    final reading = result.ok
        ? SignalReading(
            tier: _tierForLatency(result.elapsedMs),
            latencyMs: result.elapsedMs,
            measuredAt: DateTime.now(),
          )
        : SignalReading(
            tier: SignalTier.none,
            latencyMs: null,
            measuredAt: DateTime.now(),
          );

    _last = reading;
    if (!_controller.isClosed) _controller.add(reading);
  }

  SignalTier _tierForLatency(int ms) {
    if (ms < 150) return SignalTier.excellent;
    if (ms < 400) return SignalTier.good;
    if (ms < 800) return SignalTier.fair;
    return SignalTier.weak;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    // Force-complete every in-flight retry wait ourselves — cancelling
    // their Timers would leave the awaits hanging (see cancellableDelay).
    for (final cancel in _pendingRetryCancels.toList()) {
      cancel();
    }
    _pendingRetryCancels.clear();
    _started = false;
  }
}
