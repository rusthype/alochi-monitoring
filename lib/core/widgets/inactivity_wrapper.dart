import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../diagnostics/active_test_gate.dart';
import '../services/heartbeat_service.dart';
import '../session/logout.dart' show clearStudentSession;

class InactivityWrapper extends StatefulWidget {
  final Widget child;
  final Duration timeout;

  /// Explicit router: this widget is mounted ABOVE `MaterialApp.router`, so
  /// `GoRouter.of(context)` can never find one from here (prod crash
  /// "No GoRouter found in context" on 9 kiosks).
  final GoRouter router;

  const InactivityWrapper({
    super.key,
    required this.child,
    required this.router,
    this.timeout = const Duration(minutes: 30),
  });

  @override
  State<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends State<InactivityWrapper> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _handleInactivity);
  }

  Future<void> _handleInactivity() async {
    // A running (or teacher-paused) test is never logged out from under the
    // student: its own deadline / the teacher ends it. Any runner holds the
    // ActiveTestGate (the engine also registers with HeartbeatService).
    if (HeartbeatService.instance.testScreenActive ||
        ActiveTestGate.active.value) {
      _startTimer();
      return;
    }
    if (mounted) {
      // Same sequence as an explicit logout (api token, heartbeat identity,
      // cached credentials) so the next student on this shared PC inherits
      // nothing of the previous one. Awaited before navigating, otherwise
      // the next screen's read would race it.
      try {
        await clearStudentSession();
      } catch (e) {
        debugPrint('InactivityWrapper: clearStudentSession failed: $e');
      }
      if (!mounted) return;
      // Force pop to root route
      widget.router.go('/');
    }
  }

  void _resetTimer([_]) {
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _resetTimer,
      onPointerMove: _resetTimer,
      onPointerHover: _resetTimer,
      onPointerUp: _resetTimer,
      child: widget.child,
    );
  }
}
