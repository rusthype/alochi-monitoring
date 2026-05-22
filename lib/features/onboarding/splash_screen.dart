// lib/features/onboarding/splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/pack_cache.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/particle_canvas.dart';
import '../auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoCtrl;
  late final AnimationController _fadeCtrl;
  late final Animation<double>   _logoScale;
  late final Animation<double>   _logoRotate;
  late final Animation<double>   _titleFade;
  late final Animation<Offset>   _titleSlide;

  String _status   = 'Ishga tushirilmoqda...';
  double _progress = 0;
  bool   _isOnline = false;
  bool   _done     = false;
  bool   _showBadge = false;
  int    _statusIdx = 0; // unique key counter

  static const _statuses = [
    (0.0,  'Ishga tushirilmoqda...'),
    (0.18, 'Internet tekshirilmoqda...'),
    (0.42, 'Sozlamalar yuklanmoqda...'),
    (0.68, 'Server bilan ulanilmoqda...'),
    (0.95, 'Tayyor!'),
  ];

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));

    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoRotate = Tween<double>(begin: -0.21, end: 0.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic));

    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _fadeCtrl,
            curve: const Interval(0.3, 1.0, curve: Curves.easeOut)));
    _titleSlide = Tween<Offset>(
        begin: const Offset(0, 0.3), end: Offset.zero).animate(
        CurvedAnimation(parent: _fadeCtrl,
            curve: const Interval(0.3, 1.0, curve: Curves.easeOut)));

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _logoCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _fadeCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 1100), _init);
  }

  @override
  void dispose() {
    _barTimer?.cancel();
    _logoCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
    // Animated progress bar
    _animBar();

    // 1. Connectivity
    _setStatus('Internet tekshirilmoqda...', 0.2);
    _isOnline = await ConnectivityService.check(
        timeout: const Duration(seconds: 4));

    // 2. PIN cache
    _setStatus('Sozlamalar yuklanmoqda...', 0.45);
    await PackCacheService.getGuestPin();

    // 3. Server
    _setStatus(_isOnline ? 'Server bilan ulanilmoqda...' : 'Offline rejim...', 0.7);
    await Future.delayed(const Duration(milliseconds: 500));

    // 4. Done
    _setStatus('Tayyor!', 1.0);
    setState(() { _done = true; _showBadge = true; });
    await Future.delayed(const Duration(milliseconds: 600));

    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    });
    } catch (e) {
      debugPrint('SplashScreen._init error: $e');
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Timer? _barTimer;
  void _animBar() {
    double pct = 0;
    int mi = 0;
    _barTimer = Timer.periodic(const Duration(milliseconds: 22), (t) {
      if (!mounted) { t.cancel(); return; }
      pct = (pct + 1.1).clamp(0, 100);
      final frac = pct / 100;
      while (mi < _statuses.length && frac >= _statuses[mi].$1) {
        _setStatus(_statuses[mi].$2, frac);
        mi++;
      }
      if (pct >= 100) t.cancel();
    });
  }

  void _setStatus(String msg, double progress) {
    if (!mounted) return;
    setState(() { _status = msg; _progress = progress; _statusIdx++; });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeNotifier>().isDark;
    final bgColor = isDark ? AppColors.darkBg : AppColors.lightBg;
    final inkColor = isDark ? AppColors.darkInk1 : AppColors.lightInk1;
    final ink3 = isDark ? AppColors.darkInk3 : AppColors.lightInk3;

    return Scaffold(
      backgroundColor: bgColor,
      body: ParticleCanvas(
        darkMode: isDark,
        child: Center(
          child: SizedBox(
            width: 320,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // ── Logo ──
              AnimatedBuilder(
                animation: _logoCtrl,
                builder: (_, __) => Transform.scale(
                  scale: _logoScale.value,
                  child: Transform.rotate(
                    angle: _logoRotate.value,
                    child: Container(
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: Colors.white,
                        boxShadow: [BoxShadow(
                          color: AppColors.brand.withValues(alpha: .35),
                          blurRadius: 40, offset: const Offset(0, 12))],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // ── Title ──
              SlideTransition(
                position: _titleSlide,
                child: FadeTransition(
                  opacity: _titleFade,
                  child: Column(children: [
                    Text('Alochi', style: TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w900,
                        letterSpacing: -0.5, color: inkColor)),
                    const SizedBox(height: 4),
                    Text('MONITORING', style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        letterSpacing: 4, color: AppColors.brand)),
                  ]),
                ),
              ),
              const SizedBox(height: 52),

              // ── Progress bar ──
              FadeTransition(
                opacity: _titleFade,
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: isDark
                          ? AppColors.darkBorder : AppColors.lightBorder,
                      color: _done ? AppColors.ok : AppColors.brand,
                      minHeight: 3,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Status
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      key: ValueKey(_statusIdx),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!_done) ...[
                          SizedBox(width: 10, height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.brand)),
                          const SizedBox(width: 7),
                        ] else ...[
                          const Icon(Icons.check_circle_rounded,
                              size: 13, color: AppColors.ok),
                          const SizedBox(width: 6),
                        ],
                        Text(_status, style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w500,
                            fontFamily: 'monospace',
                            color: _done ? AppColors.ok : ink3)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Online badge
                  AnimatedOpacity(
                    opacity: _showBadge ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: (_isOnline ? AppColors.ok
                            : AppColors.err).withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (_isOnline ? AppColors.ok
                              : AppColors.err).withValues(alpha: .25)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isOnline ? AppColors.ok : AppColors.err)),
                        const SizedBox(width: 5),
                        Text(_isOnline ? 'Online' : 'Offline',
                          style: TextStyle(fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _isOnline ? AppColors.ok : AppColors.err)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
