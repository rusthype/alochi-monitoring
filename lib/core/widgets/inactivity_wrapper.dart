import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../db/credential_cache.dart';

class InactivityWrapper extends StatefulWidget {
  final Widget child;
  final Duration timeout;

  const InactivityWrapper({
    super.key,
    required this.child,
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
    if (mounted) {
      // Talaba oldingi talabaning login/parolini ko'rmasligi uchun
      // saqlangan credential'larni tozalaymiz — navigatsiyadan oldin
      // await qilinadi, aks holda keyingi ekran o'qishi bilan poyga bo'ladi.
      await CredentialCache.clear();
      if (!mounted) return;
      // Force pop to root route
      GoRouter.of(context).go('/');
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
