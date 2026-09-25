// lib/core/services/proctor_service.dart
// Live proctoring (Windows kiosk): periodic screen-frame broadcast loop.
// Every failure path here just counts and reschedules — this must never
// throw out of _tick or interrupt the exam.
import 'dart:async';
import 'dart:io' show Platform;

import '../api/api_client.dart';
import 'heartbeat_service.dart';
import 'screen_capture_win.dart';

class ProctorService {
  ProctorService._();
  static final ProctorService instance = ProctorService._();

  static const Duration _baseInterval = Duration(milliseconds: 2500);
  static const Duration _backoffInterval = Duration(milliseconds: 15000);

  Timer? _timer;
  // Guards against a stopped service re-arming itself: stop() can race a
  // _tick() call already in flight (e.g. a slow network request mid-dispose)
  // — without this flag, that in-flight tick's finally-block reschedule
  // would resurrect the timer after stop() already cancelled it, leaving a
  // dead session polling forever.
  bool _running = false;
  bool _inFlight = false;
  int _consecutiveFailures = 0;
  bool _usingBackoff = false;

  /// Admin-lock (pause)/warning/extra-time callbacks now live on
  /// [HeartbeatService] (see `reconcileProctorState`) since the SAME
  /// canonical state must reconcile both this frame-ingest channel AND the
  /// 30s ping channel — this service only forwards its own response's
  /// `locked`/`extra_time_seconds`/`commands` fields into it. The one
  /// exception is `request_keyframe`, which only makes sense while THIS
  /// capture loop is running, so `start`/`stop` own wiring that one
  /// callback directly.
  void start() {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    stop(); // idempotent restart
    resetCaptureStreamForNewSession();
    HeartbeatService.instance.onRequestKeyframe = forceNextKeyframe;
    _running = true;
    _scheduleNext(_baseInterval);
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _consecutiveFailures = 0;
    _usingBackoff = false;
    if (HeartbeatService.instance.onRequestKeyframe == forceNextKeyframe) {
      HeartbeatService.instance.onRequestKeyframe = null;
    }
  }

  void _scheduleNext(Duration delay) {
    if (!_running) return;
    _timer = Timer(delay, _tick);
  }

  Future<void> _tick() async {
    if (_inFlight) {
      _scheduleNext(_currentInterval());
      return;
    }
    final token = HeartbeatService.instance.proctorToken;
    final sessionId = HeartbeatService.instance.activeSessionId;
    if (token == null || sessionId == null) {
      _scheduleNext(_currentInterval());
      return;
    }
    _inFlight = true;
    try {
      final capture = await captureScreenJpeg();
      if (capture != null) {
        final result = await api.proctorFrame(
          sessionId: sessionId,
          token: token,
          jpeg: capture.jpeg,
          focus: isForegroundOurs(),
          monitorCount: monitorCount(),
          questionIndex: HeartbeatService.instance.currentQuestionIndex,
          totalQuestions: HeartbeatService.instance.totalQuestions,
          questionText: HeartbeatService.instance.currentQuestionText,
          selectedOptionText: HeartbeatService.instance.selectedOptionText,
          frameType: capture.frameType,
          x: capture.x,
          y: capture.y,
          w: capture.w,
          h: capture.h,
          streamEpoch: capture.streamEpoch,
          cursorX: capture.cursorX,
          cursorY: capture.cursorY,
          cursorVisible: capture.cursorVisible,
        );
        if (result.isNotEmpty) {
          _consecutiveFailures = 0;
          _usingBackoff = false;
          // `locked`/`extra_time_seconds`/`commands` (warning,
          // request_keyframe — process the WHOLE list, not just one) are
          // reconciled through the same canonical state the 30s ping
          // channel feeds too. See HeartbeatService.reconcileProctorState.
          HeartbeatService.instance.reconcileProctorState(
            locked: result['locked'] as bool?,
            extraTimeSeconds: result['extra_time_seconds'] as int?,
            commands: result['commands'] as List<dynamic>?,
          );
          // Backend-driven capture profile for the NEXT tick — target_width
          // 960 means spotlight (single-student close-up), anything else
          // (including missing/default) means grid.
          final nextProfile = result['target_width'] == 960
              ? CaptureProfile.spotlight
              : CaptureProfile.grid;
          if (nextProfile != currentCaptureProfile) forceNextKeyframe();
          currentCaptureProfile = nextProfile;
        } else {
          _consecutiveFailures++;
        }
      } else {
        _consecutiveFailures++;
      }
    } catch (_) {
      _consecutiveFailures++;
    } finally {
      _inFlight = false;
    }
    if (_consecutiveFailures >= 5) _usingBackoff = true;
    _scheduleNext(_currentInterval());
  }

  Duration _currentInterval() {
    if (_usingBackoff) return _backoffInterval;
    final ms = HeartbeatService.instance.proctorIntervalMs;
    return Duration(milliseconds: ms);
  }
}
