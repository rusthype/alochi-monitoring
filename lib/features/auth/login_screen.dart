// lib/features/auth/login_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../core/db/credential_cache.dart';
import '../../shared/theme/app_theme.dart';
import '../test/package_screen.dart';
import '../local_test/local_grade_screen.dart';

Future<bool> checkOnlineWithRetry(
  Future<bool> Function() ping, {
  int attempts = 3,
  Duration timeout = const Duration(seconds: 3),
  Duration retryDelay = const Duration(seconds: 1),
}) async {
  for (var i = 0; i < attempts; i++) {
    try {
      final ok = await ping().timeout(timeout, onTimeout: () => false);
      if (ok) return true;
    } catch (_) {}

    if (i < attempts - 1 && retryDelay > Duration.zero) {
      await Future.delayed(retryDelay);
    }
  }

  return false;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _Dot {
  double x, y, vx, vy, radius;
  Color color;

  _Dot(math.Random r, Size size)
      : x = r.nextDouble() * size.width,
        y = r.nextDouble() * size.height,
        vx = (r.nextDouble() - 0.5) * 0.8,
        vy = (r.nextDouble() - 0.5) * 0.8,
        radius = 1.5 + r.nextDouble() * 2.5,
        color = [
          const Color(0xFF4A90D9),
          const Color(0xFFF97316),
          const Color(0xFF7C3AED),
          const Color(0xFF0D9488),
          const Color(0xFFE11D48),
        ][r.nextInt(5)];

  void update(Size size) {
    x += vx;
    y += vy;
    if (x < 0 || x > size.width) vx = -vx;
    if (y < 0 || y > size.height) vy = -vy;
    x = x.clamp(0, size.width);
    y = y.clamp(0, size.height);
  }
}

class _NetworkPainter extends CustomPainter {
  final List<_Dot> dots;
  const _NetworkPainter(this.dots);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()..strokeWidth = 0.8;
    for (var i = 0; i < dots.length; i++) {
      for (var j = i + 1; j < dots.length; j++) {
        final dx = dots[i].x - dots[j].x;
        final dy = dots[i].y - dots[j].y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 130) {
          linePaint.color =
              dots[i].color.withValues(alpha: (1 - dist / 130) * 0.25);
          canvas.drawLine(
            Offset(dots[i].x, dots[i].y),
            Offset(dots[j].x, dots[j].y),
            linePaint,
          );
        }
      }
    }
    for (final dot in dots) {
      canvas.drawCircle(
        Offset(dot.x, dot.y),
        dot.radius,
        Paint()..color = dot.color.withValues(alpha: 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(_NetworkPainter oldDelegate) => true;
}

class _NetworkBg extends StatefulWidget {
  const _NetworkBg();

  @override
  State<_NetworkBg> createState() => _NetworkBgState();
}

class _NetworkBgState extends State<_NetworkBg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late List<_Dot> _dots;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )
      ..addListener(_tick)
      ..repeat();
  }

  void _tick() {
    if (!_initialized) return;
    final size = context.size;
    if (size == null) return;
    for (final dot in _dots) {
      dot.update(size);
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final size = MediaQuery.of(context).size;
      final rng = math.Random();
      _dots = List.generate(40, (_) => _Dot(rng, size));
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _NetworkPainter(_dots),
        child: const SizedBox.expand(),
      );
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _showPass = false;
  bool _isOnline = false;
  bool _checkingOnline = true;
  bool _autoLogging = true; // birinchi ochilganda auto-login urinish
  String _statusMsg = 'Server tekshirilmoqda...';
  String? _error;

  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _anim.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// App ochilganda jimgina login urinish — hech narsa ko'rinmaydi
  Future<void> _tryAutoLogin() async {
    try {
      final creds = await CredentialCache.loadCredentials();
      if (creds == null) {
        final online = await _checkOnline();
        if (mounted) _showForm(online: online);
        return;
      }

      final username = creds['username']!;
      final password = creds['password']!;

      final online = await _checkOnline();

      if (online) {
        try {
          final session = await api.login(username, password);
          api.setToken(session.token);
          await CredentialCache.saveSession(session, username, password);
          if (!mounted) return;
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => PackageScreen(session: session)));
          return;
        } on ApiException {
          // Login/parol o'zgargan — bo'sh forma
          await CredentialCache.clear();
          if (mounted) _showForm(online: true);
          return;
        } catch (_) {
          // Server xatosi — offline bazadan urinib ko'ramiz
        }
      }

      // Offline yoki server xatosi — lokal sessiyadan
      final session =
          await CredentialCache.loadOfflineSession(username, password);
      if (session != null && mounted) {
        api.setToken(session.token);
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    PackageScreen(session: session, offline: !online)));
        return;
      }

      if (mounted) _showForm(online: online);
    } catch (_) {
      if (mounted) _showForm();
    }
  }

  void _showForm({bool online = false}) {
    setState(() {
      _autoLogging = false;
      _isOnline = online;
      _checkingOnline = false;
      _statusMsg = online ? 'Server bilan ulandi' : 'Offline rejim';
    });
    _anim.forward();
  }

  Future<bool> _checkOnline() async {
    if (mounted) {
      setState(() {
        _checkingOnline = true;
        _statusMsg = 'Server tekshirilmoqda...';
      });
    }

    final online = await checkOnlineWithRetry(() => api.ping());

    if (mounted) {
      setState(() {
        _isOnline = online;
        _checkingOnline = false;
        _statusMsg = online ? 'Server bilan ulandi' : 'Offline rejim';
      });
    }

    return online;
  }

  Future<void> _retryOnlineCheck() async {
    setState(() => _error = null);
    await _checkOnline();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    try {
      // Avval online login urinib ko'ramiz
      final online = await _checkOnline();

      if (online) {
        // ── Online ────────────────────────────────────────────────
        try {
          final session = await api.login(username, password);
          api.setToken(session.token);
          await CredentialCache.saveCredentials(username, password);
          await CredentialCache.saveSession(session, username, password);
          if (!mounted) return;
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => PackageScreen(session: session)));
          return;
        } on ApiException catch (e) {
          // 400 = login/parol xato — offline ham urinma
          if (e.statusCode == 400) {
            setState(() => _error = "Login yoki parol noto'g'ri");
            return;
          }
          if (e.statusCode == 429) {
            setState(() => _error = "Ko'p urinish. Biroz kuting.");
            return;
          }
          // Boshqa server xatosi — offline bazadan urinib ko'ramiz
        }
      }

      // ── Offline yoki server xatosi — lokal bazadan ────────────
      final session =
          await CredentialCache.loadOfflineSession(username, password);
      if (session != null) {
        api.setToken(session.token);
        if (!mounted) return;
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    PackageScreen(session: session, offline: !online)));
        return;
      }

      // Hech narsa topilmadi
      if (!mounted) return;
      setState(() => _error = online
          ? "Server xatosi. Qayta urinib ko'ring."
          : "Internet yo'q va bu login ilgari saqlanmagan.");
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Ulanishda xato. Qayta urinib ko'ring.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _guestLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pin = await api.fetchGuestPin();
      if (pin == null || pin.isEmpty) {
        setState(() => _error = "Mehmon kirish mavjud emas.");
        return;
      }
      final session = await api.login('guest', pin);
      api.setToken(session.token);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => PackageScreen(session: session)),
      );
    } catch (_) {
      setState(() => _error = "Kirish muvaffaqiyatsiz.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-login urinayotganda spinner
    if (_autoLogging) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: AppColors.brand)),
          SizedBox(height: 16),
          Text('Kirish...',
              style: TextStyle(
                  fontSize: 14,
                  color: AppColors.ink3,
                  fontWeight: FontWeight.w500)),
        ])),
      );
    }

    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): _login},
        child: Focus(
          autofocus: true,
          child: w > 700 ? _wideLayout() : _narrowLayout(),
        ),
      ),
    );
  }

  Widget _wideLayout() => Stack(children: [
        Positioned.fill(child: Container(color: const Color(0xFFF5F0E8))),
        const Positioned.fill(child: _NetworkBg()),
        Row(children: [
          Expanded(flex: 4, child: _leftPanel()),
          Expanded(flex: 5, child: _formPanel()),
        ]),
      ]);

  Widget _narrowLayout() => Stack(children: [
        Positioned.fill(child: Container(color: const Color(0xFFF5F0E8))),
        const Positioned.fill(child: _NetworkBg()),
        _formPanel(),
      ]);

  Widget _leftPanel() => Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF97316), Color(0xFFFB923C), Color(0xFFEA580C)],
        )),
        child: Stack(children: [
          Positioned(top: -60, right: -60, child: _circle(220, .08)),
          Positioned(bottom: -80, left: -40, child: _circle(280, .07)),
          Positioned(top: 80, left: 30, child: _circle(60, .1)),
          Center(
              child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .15),
                        blurRadius: 24,
                        offset: const Offset(0, 8))
                  ],
                ),
                child: const Center(
                    child: Text('A',
                        style: TextStyle(
                            color: AppColors.brand,
                            fontSize: 44,
                            fontWeight: FontWeight.w900))),
              ),
              const SizedBox(height: 24),
              const Text('Alochi',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Monitoring tizimi',
                  style: TextStyle(color: Colors.white70, fontSize: 16)),
              const SizedBox(height: 32),
              _infoRow(Icons.keyboard, "A, B, C, D - javob tanlash"),
              const SizedBox(height: 10),
              _infoRow(Icons.arrow_forward, "Arrow tugmalar - navigatsiya"),
              const SizedBox(height: 10),
              _infoRow(Icons.wifi_off, "Offline rejim qollab-quvvatlanadi"),
            ]),
          )),
        ]),
      );

  Widget _circle(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: opacity)),
      );

  Widget _infoRow(IconData icon, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.white, size: 14),
        ),
        const SizedBox(width: 10),
        Text(text,
            style: TextStyle(
                color: Colors.white.withValues(alpha: .8), fontSize: 13)),
      ]);

  Widget _formPanel() => FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Center(
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (MediaQuery.of(context).size.width < 700) ...[
                  Row(children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .08),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'A',
                          style: TextStyle(
                            color: AppColors.brand,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alochi',
                          style: TextStyle(
                            color: AppColors.ink1,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Monitoring tizimi',
                          style: TextStyle(color: AppColors.ink2, fontSize: 13),
                        ),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 26),
                ],
                // Online/offline status
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: _statusColor.withValues(alpha: .2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _checkingOnline
                        ? SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _statusColor,
                            ))
                        : Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: _statusColor)),
                    const SizedBox(width: 7),
                    Text(_statusMsg,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _checkingOnline
                                ? AppColors.brand
                                : (_isOnline ? AppColors.ok : AppColors.ink2))),
                  ]),
                ),
                if (!_isOnline && !_checkingOnline) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _loading ? null : _retryOnlineCheck,
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text("Qayta urinib ko'rish"),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brand,
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Kirish',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink1)),
                          SizedBox(height: 4),
                          Text("Login va parolni o'qituvchingizdan oling",
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.ink2)),
                        ])),
                const SizedBox(height: 24),
                Form(
                    key: _formKey,
                    child: Column(children: [
                      _field(
                        controller: _userCtrl,
                        label: 'Login',
                        hint: '',
                        icon: Icons.person_outline_rounded,
                        action: TextInputAction.next,
                        validator: (v) => v!.isEmpty ? 'Login kiriting' : null,
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _passCtrl,
                        label: 'Parol',
                        hint: '',
                        icon: Icons.lock_outline_rounded,
                        obscure: !_showPass,
                        action: TextInputAction.done,
                        onSubmit: (_) => _login(),
                        validator: (v) => v!.isEmpty ? 'Parol kiriting' : null,
                        suffix: IconButton(
                          icon: Icon(
                              _showPass
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 18),
                          onPressed: () =>
                              setState(() => _showPass = !_showPass),
                          color: AppColors.ink3,
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        child: _error == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: AppColors.err.withValues(alpha: .07),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: AppColors.err
                                            .withValues(alpha: .2)),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.error_outline_rounded,
                                        color: AppColors.err, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(_error!,
                                            style: const TextStyle(
                                                color: AppColors.err,
                                                fontSize: 13))),
                                  ]),
                                ),
                              ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                      Text(
                                          _isOnline
                                              ? 'Kirish'
                                              : 'Offline kirish',
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(width: 6),
                                      Icon(
                                          _isOnline
                                              ? Icons.arrow_forward_rounded
                                              : Icons.wifi_off_rounded,
                                          size: 18),
                                    ]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _loading ? null : _guestLogin,
                        icon:
                            const Icon(Icons.person_outline_rounded, size: 16),
                        label: const Text("Oddiy kirish (faqat ism)"),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.ink2,
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // ── Offline Test tugmasi ──────────────────────────────
                      SizedBox(
                        height: 46,
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LocalGradeScreen())),
                          icon: const Icon(Icons.wifi_off_rounded, size: 17),
                          label: const Text('Offline test (server kerak emas)',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.ink2,
                            side: const BorderSide(
                                color: AppColors.border, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)),
                            backgroundColor: AppColors.surface,
                          ),
                        ),
                      ),
                    ])),
              ]),
            ),
          )),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputAction? action,
    void Function(String)? onSubmit,
    String? Function(String?)? validator,
    Widget? suffix,
  }) =>
      TextFormField(
        controller: controller,
        obscureText: obscure,
        textInputAction: action,
        onFieldSubmitted: onSubmit,
        validator: validator,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink1),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(icon, size: 18, color: AppColors.ink3)),
          prefixIconConstraints: const BoxConstraints(minWidth: 46),
          suffixIcon: suffix,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: AppColors.brand, width: 2)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: AppColors.err)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          labelStyle: const TextStyle(color: AppColors.ink2, fontSize: 13),
        ),
      );

  Color get _statusColor {
    if (_checkingOnline) return AppColors.brand;
    return _isOnline ? AppColors.ok : AppColors.ink3;
  }
}
