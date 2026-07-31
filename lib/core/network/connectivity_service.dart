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

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  static const Duration _interval = Duration(seconds: 15);
  static const Duration _timeout = Duration(seconds: 3);

  Timer? _timer;
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

  Future<void> _measure() async {
    final stopwatch = Stopwatch()..start();
    bool ok;
    try {
      // Single attempt, no retry loop: a slow-but-successful ping should
      // read as "weak", not be masked by a retry that finds a faster path
      // and skews the latency reading.
      ok = await api.ping().timeout(_timeout, onTimeout: () => false);
    } catch (_) {
      ok = false;
    }
    stopwatch.stop();

    final reading = ok
        ? SignalReading(
            tier: _tierForLatency(stopwatch.elapsedMilliseconds),
            latencyMs: stopwatch.elapsedMilliseconds,
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
    _started = false;
  }
}
