// lib/core/services/proctor_service.dart
// Live proctoring (Windows kiosk): periodic screen-frame broadcast loop.
// Every failure path here just counts and reschedules — this must never
// throw out of _tick or interrupt the exam.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

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

  /// Called when the panel presses "Lock All" (frame response action=="lock").
  VoidCallback? onLock;

  /// Called when the panel presses "+N minutes" (frame response extra_seconds).
  ValueChanged<int>? onExtendSeconds;

  void start() {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    stop(); // idempotent restart
    _running = true;
    _scheduleNext(_baseInterval);
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _consecutiveFailures = 0;
    _usingBackoff = false;
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
      final jpeg = await captureScreenJpeg();
      if (jpeg != null) {
        final result = await api.proctorFrame(
          sessionId: sessionId,
          token: token,
          jpeg: jpeg,
          focus: isForegroundOurs(),
          monitorCount: monitorCount(),
          questionIndex: HeartbeatService.instance.currentQuestionIndex,
          totalQuestions: HeartbeatService.instance.totalQuestions,
          questionText: HeartbeatService.instance.currentQuestionText,
          selectedOptionText: HeartbeatService.instance.selectedOptionText,
        );
        if (result.isNotEmpty) {
          _consecutiveFailures = 0;
          _usingBackoff = false;
          if (result['action'] == 'lock') onLock?.call();
          final extra = result['extra_seconds'];
          if (extra is int) onExtendSeconds?.call(extra);
          // Backend-driven capture profile for the NEXT tick — target_width
          // 960 means spotlight (single-student close-up), anything else
          // (including missing/default) means grid.
          currentCaptureProfile = result['target_width'] == 960
              ? CaptureProfile.spotlight
              : CaptureProfile.grid;
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
