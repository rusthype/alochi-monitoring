// lib/features/onboarding/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/pack_cache.dart';
import '../../shared/theme/app_theme.dart';
import '../auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;
  late final Animation<double>   _fade;

  String _status     = 'Ishga tushirilmoqda...';
  double _progress   = 0;
  bool   _isOnline   = false;
  bool   _done       = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _init();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 600));

    // 1. Connectivity
    _setStatus("Internet tekshirilmoqda...", 0.2);
    _isOnline = await ConnectivityService.check(
        timeout: const Duration(seconds: 4));

    // 2. PIN cache
    _setStatus("Sozlamalar yuklanmoqda...", 0.45);
    await PackCacheService.getGuestPin();

    // 3. Version check
    _setStatus(
      _isOnline ? "Server bilan ulanilmoqda..." : "Offline rejim...",
      0.7,
    );
    await Future.delayed(const Duration(milliseconds: 500));

    // 4. Done
    _setStatus("Tayyor!", 1.0);
    await Future.delayed(const Duration(milliseconds: 400));

    if (mounted) {
      setState(() => _done = true);
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted) {
        Navigator.pushReplacement(context,
            PageRouteBuilder(
              pageBuilder: (_, a, __) => const LoginScreen(),
              transitionsBuilder: (_, anim, __, child) =>
                  FadeTransition(opacity: anim, child: child),
              transitionDuration: const Duration(milliseconds: 400),
            ));
      }
    }
  }

  void _setStatus(String msg, double progress) {
    if (!mounted) return;
    setState(() { _status = msg; _progress = progress; });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        // Background circles
        Positioned(
          top: -size.height * 0.15,
          right: -size.width * 0.15,
          child: Container(
            width: size.width * 0.6,
            height: size.width * 0.6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brand.withValues(alpha: .07),
            ),
          ),
        ),
        Positioned(
          bottom: -size.height * 0.1,
          left: -size.width * 0.1,
          child: Container(
            width: size.width * 0.5,
            height: size.width * 0.5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brand.withValues(alpha: .05),
            ),
          ),
        ),

        // Main content
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Logo
            ScaleTransition(
              scale: _scale,
              child: FadeTransition(
                opacity: _fade,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brand,
                    boxShadow: [BoxShadow(
                      color: AppColors.brand.withValues(alpha: .3),
                      blurRadius: 24, offset: const Offset(0, 8))],
                  ),
                  child: const Center(child: Text('A',
                      style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900,
                          color: Colors.white))),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // App name
            FadeTransition(
              opacity: _fade,
              child: const Column(children: [
                Text('Alochi', style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.ink1)),
                Text('Monitoring', style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w400,
                    color: AppColors.ink3, letterSpacing: 2)),
              ]),
            ),
            const SizedBox(height: 60),

            // Progress bar
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _progress,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color: _done ? AppColors.ok : AppColors.brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Status text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Row(key: ValueKey(_status),
                mainAxisAlignment: MainAxisAlignment.center, children: [
                if (!_done) ...[
                  SizedBox(width: 12, height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppColors.brand)),
                  const SizedBox(width: 8),
                ] else
                  const Icon(Icons.check_circle_rounded,
                      size: 14, color: AppColors.ok),
                const SizedBox(width: 6),
                Text(_status, style: TextStyle(
                    fontSize: 12,
                    color: _done ? AppColors.ok : AppColors.ink3,
                    fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(height: 8),

            // Online/offline badge
            AnimatedOpacity(
              opacity: _progress > 0.3 ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_isOnline
                      ? AppColors.ok : const Color(0xFFDC2626)).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isOnline ? AppColors.ok : const Color(0xFFDC2626))),
                  const SizedBox(width: 5),
                  Text(_isOnline ? 'Online' : 'Offline',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: _isOnline ? AppColors.ok : const Color(0xFFDC2626))),
                ]),
              ),
            ),
          ]),
        )),

        // Version
        Positioned(bottom: 24, left: 0, right: 0, child: Center(
          child: Text('alochi.org',
              style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
        )),
      ]),
    );
  }
}
