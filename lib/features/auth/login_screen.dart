// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../core/db/credential_cache.dart';
import '../../core/models/models.dart';
import '../../core/services/connectivity_service.dart';
import '../../shared/theme/app_theme.dart';
import '../test/local_test_screen.dart';
import '../test/package_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _userCtrl  = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _nameCtrl  = TextEditingController(); // oddiy kirish uchun
  final _formKey   = GlobalKey<FormState>();
  final _guestKey  = GlobalKey<FormState>();
  bool _loading    = false;
  bool _showPass   = false;
  bool _isOnline   = false;
  bool _autoLogging = true;
  bool _showGuest  = false; // oddiy kirish paneli
  int  _guestGrade = 1;
  String? _guestPinError;
  final _pinCtrl = TextEditingController();
  String? _error;

  late final AnimationController _anim;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _anim  = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _tryAutoLogin();
  }

  @override
  void dispose() {
    _anim.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  /// App ochilganda jimgina login urinish — hech narsa ko'rinmaydi
  Future<void> _tryAutoLogin() async {
    try {
      final creds = await CredentialCache.loadCredentials();
      if (creds == null) { _showForm(); return; }

      final username = creds['username']!;
      final password = creds['password']!;

      final online = await ConnectivityService.check(
          timeout: const Duration(seconds: 5));

      if (online) {
        try {
          final session = await api.login(username, password);
          api.setToken(session.token);
          await CredentialCache.saveSession(session, username, password);
          if (!mounted) return;
          Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => PackageScreen(session: session)));
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
      final session = await CredentialCache.loadOfflineSession(username, password);
      if (session != null && mounted) {
        api.setToken(session.token);
        Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => PackageScreen(session: session, offline: !online)));
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
      _isOnline    = online;
    });
    _anim.forward();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    try {
      // Avval online login urinib ko'ramiz
      final online = await api.ping().timeout(const Duration(seconds: 4), onTimeout: () => false);

      if (online) {
        // ── Online ────────────────────────────────────────────────
        try {
          final session = await api.login(username, password);
          api.setToken(session.token);
          await CredentialCache.saveCredentials(username, password);
          await CredentialCache.saveSession(session, username, password);
          if (!mounted) return;
          Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => PackageScreen(session: session)));
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
      final session = await CredentialCache.loadOfflineSession(username, password);
      if (session != null) {
        api.setToken(session.token);
        if (!mounted) return;
        Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => PackageScreen(session: session, offline: !online)));
        return;
      }

      // Hech narsa topilmadi
      if (!mounted) return;
      setState(() => _error = online
        ? "Server xatosi. Qayta urinib ko'ring."
        : "Internet yo'q va bu login ilgari saqlanmagan.");

    } catch (_) {
      if (mounted) setState(() => _error = "Ulanishda xato. Qayta urinib ko'ring.");
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
        body: Center(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 36, height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3, color: AppColors.brand)),
          SizedBox(height: 16),
          Text('Kirish...', style: TextStyle(
            fontSize: 14, color: AppColors.ink3, fontWeight: FontWeight.w500)),
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

  Widget _wideLayout() => Row(children: [
    Expanded(flex: 4, child: Container(
      decoration: const BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFFF97316), Color(0xFFFB923C), Color(0xFFEA580C)],
      )),
      child: Stack(children: [
        Positioned(top: -60, right: -60, child: _circle(220, .08)),
        Positioned(bottom: -80, left: -40, child: _circle(280, .07)),
        Positioned(top: 80, left: 30,     child: _circle(60, .1)),
        Center(child: Padding(padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.15), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Center(child: Text('A', style: TextStyle(
                color: AppColors.brand, fontSize: 44, fontWeight: FontWeight.w900))),
            ),
            const SizedBox(height: 24),
            const Text('Alochi', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Monitoring tizimi', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 32),
            _infoRow(Icons.keyboard,    "A, B, C, D - javob tanlash"),
            const SizedBox(height: 10),
            _infoRow(Icons.arrow_forward, "Arrow tugmalar - navigatsiya"),
            const SizedBox(height: 10),
            _infoRow(Icons.wifi_off,    "Offline rejim qollab-quvvatlanadi"),
          ]),
        )),
      ]),
    )),
    Expanded(flex: 5, child: _formPanel()),
  ]);

  Widget _narrowLayout() => _formPanel();

  Widget _circle(double size, double opacity) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
      color: Colors.white.withOpacity(opacity)),
  );

  Widget _infoRow(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: Colors.white, size: 14),
    ),
    const SizedBox(width: 10),
    Text(text, style: TextStyle(color: Colors.white.withOpacity(.8), fontSize: 13)),
  ]);

  // Oddiy kirish — faqat ism va sinf
  void _guestLogin() {
    if (!_guestKey.currentState!.validate()) return;
    // PIN tekshirish
    const guestPin = '1234'; // TODO: settings dan olish
    if (_pinCtrl.text.trim() != guestPin) {
      setState(() => _guestPinError = 'PIN noto\'g\'ri');
      return;
    }
    setState(() => _guestPinError = null);
    final name  = _nameCtrl.text.trim();
    final grade = _guestGrade;
    // Local guest session — server kerak emas
    final session = StudentSession(
      token:       'guest',
      studentId:   'guest_${DateTime.now().millisecondsSinceEpoch}',
      studentName: name,
      variant:     grade, // grade = variant (1→A, 2→B, 3→C, 4→D)
      grade:       grade,
      groupName:   null,
    );
    if (!mounted) return;
    Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (_) => LocalTestScreen(session: session)));
  }

  Widget _formPanel() => FadeTransition(
    opacity: _fade,
    child: SlideTransition(
      position: _slide,
      child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Online/offline status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: (_isOnline ? AppColors.ok : AppColors.ink3).withOpacity(.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: (_isOnline ? AppColors.ok : AppColors.ink3).withOpacity(.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: _isOnline ? AppColors.ok : AppColors.ink3)),
                const SizedBox(width: 7),
                Text(_isOnline ? 'Server bilan ulandi' : 'Offline rejim',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: _isOnline ? AppColors.ok : AppColors.ink2)),
              ]),
            ),
            const SizedBox(height: 28),
            const Align(alignment: Alignment.centerLeft, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Kirish', style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink1)),
              SizedBox(height: 4),
              Text("Login va parolni o'qituvchingizdan oling",
                style: TextStyle(fontSize: 13, color: AppColors.ink2)),
            ])),
            const SizedBox(height: 24),
            Form(key: _formKey, child: Column(children: [
              _field(
                controller: _userCtrl, label: 'Login', hint: '',
                icon: Icons.person_outline_rounded, action: TextInputAction.next,
                validator: (v) => v!.isEmpty ? 'Login kiriting' : null,
              ),
              const SizedBox(height: 14),
              _field(
                controller: _passCtrl, label: 'Parol', hint: '',
                icon: Icons.lock_outline_rounded, obscure: !_showPass,
                action: TextInputAction.done, onSubmit: (_) => _login(),
                validator: (v) => v!.isEmpty ? 'Parol kiriting' : null,
                suffix: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  onPressed: () => setState(() => _showPass = !_showPass),
                  color: AppColors.ink3,
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                child: _error == null ? const SizedBox.shrink() : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: AppColors.err.withOpacity(.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.err.withOpacity(.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.err, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                        style: const TextStyle(color: AppColors.err, fontSize: 13))),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(height: 52, width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand, foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(_isOnline ? 'Kirish' : 'Offline kirish',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        Icon(_isOnline ? Icons.arrow_forward_rounded : Icons.wifi_off_rounded, size: 18),
                      ]),
                ),
              ),

              // ── Oddiy kirish ajratgich ──────────────────────────────
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('yoki', style: TextStyle(
                    fontSize: 12, color: AppColors.ink3, fontWeight: FontWeight.w500)),
                ),
                const Expanded(child: Divider(color: AppColors.border)),
              ]),
              const SizedBox(height: 16),

              // ── Toggle: Oddiy kirish ──────────────────────────────
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: _showGuest
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: SizedBox(
                  height: 48, width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _showGuest = true),
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: const Text('Oddiy kirish (faqat ism)',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink2,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                  ),
                ),
                secondChild: _guestPanel(),
              ),
            ])),
          ]),
        ),
      )),
    ),
  );

  Widget _guestPanel() => Form(
    key: _guestKey,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFF16A34A)),
          const SizedBox(width: 6),
          const Text('Oddiy kirish',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: Color(0xFF15803D))),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() { _showGuest = false; _nameCtrl.clear(); }),
            child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF6B7280)),
          ),
        ]),
        const SizedBox(height: 2),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('Ism kiriting va monitoring testni boshlang',
            style: TextStyle(fontSize: 11, color: Color(0xFF4B5563))),
        ),
        const SizedBox(height: 14),
        // Ism
        TextFormField(
          controller: _nameCtrl,
          textInputAction: TextInputAction.next,
          validator: (v) => v == null || v.trim().isEmpty ? 'Ism kiriting' : null,
          style: const TextStyle(fontSize: 14, color: AppColors.ink1,
              fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Ism Familiya',
            prefixIcon: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.person_rounded, size: 16, color: AppColors.ink3)),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            filled: true, fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF16A34A), width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            labelStyle: const TextStyle(fontSize: 12, color: AppColors.ink2),
          ),
        ),
        const SizedBox(height: 10),
        // PIN kod
        TextFormField(
          controller: _pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          textInputAction: TextInputAction.next,
          validator: (v) => v == null || v.trim().isEmpty ? 'PIN kiriting' : null,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
              letterSpacing: 8, color: AppColors.ink1),
          decoration: InputDecoration(
            labelText: 'Kirish kodi (PIN)',
            counterText: '',
            errorText: _guestPinError,
            prefixIcon: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.ink3)),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            filled: true, fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF16A34A), width: 2)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFDC2626))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            labelStyle: const TextStyle(fontSize: 12, color: AppColors.ink2),
          ),
        ),
        const SizedBox(height: 10),
        // Sinf tanlash
        DropdownButtonFormField<int>(
          value: _guestGrade,
          onChanged: (v) => setState(() => _guestGrade = v ?? 1),
          decoration: InputDecoration(
            labelText: 'Sinf',
            prefixIcon: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.school_rounded, size: 16, color: AppColors.ink3)),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            filled: true, fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF16A34A), width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            labelStyle: const TextStyle(fontSize: 12, color: AppColors.ink2),
          ),
          items: const [
            DropdownMenuItem(value: 1, child: Text('1-sinf')),
            DropdownMenuItem(value: 2, child: Text('2-sinf')),
            DropdownMenuItem(value: 3, child: Text('3-sinf')),
            DropdownMenuItem(value: 4, child: Text('4-sinf')),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(height: 48, width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _guestLogin,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Testni boshlash',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    ),
  );

  Widget _field({
    required TextEditingController controller, required String label,
    required String hint, required IconData icon, bool obscure = false,
    TextInputAction? action, void Function(String)? onSubmit,
    String? Function(String?)? validator, Widget? suffix,
  }) => TextFormField(
    controller: controller, obscureText: obscure,
    textInputAction: action, onFieldSubmitted: onSubmit, validator: validator,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink1),
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      prefixIcon: Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Icon(icon, size: 18, color: AppColors.ink3)),
      prefixIconConstraints: const BoxConstraints(minWidth: 46),
      suffixIcon: suffix,
      filled: true, fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.brand, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: AppColors.err)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: const TextStyle(color: AppColors.ink2, fontSize: 13),
    ),
  );
}
