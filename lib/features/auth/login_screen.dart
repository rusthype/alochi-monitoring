// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../shared/theme/app_theme.dart';
import '../test/package_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey  = GlobalKey<FormState>();
  bool _loading   = false;
  bool _showPass  = false;
  bool _isOnline  = true;
  String? _error;

  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim  = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();
    api.ping().then((ok) { if (mounted) setState(() => _isOnline = ok); });
  }

  @override
  void dispose() { _anim.dispose(); _userCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final session = await api.login(_userCtrl.text.trim(), _passCtrl.text);
      api.setToken(session.token);
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => PackageScreen(session: session)));
    } on ApiException catch (e) {
      setState(() {
        _error = e.statusCode == 400 ? "Login yoki parol noto'g'ri"
               : e.statusCode == 429 ? "Ko'p urinish. Biroz kuting."
               : "Server xatosi (${e.statusCode})";
      });
    } catch (_) { setState(() => _error = "Internet aloqasi yo'q"); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w > 700;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): _login},
        child: Focus(
          autofocus: true,
          child: isWide ? _wideLayout() : _narrowLayout(),
        ),
      ),
    );
  }

  Widget _wideLayout() => Row(children: [
    // ── Left branding panel ───────────────────────────────────────────
    Expanded(
      flex: 4,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFF97316), Color(0xFFFB923C), Color(0xFFEA580C)],
          ),
        ),
        child: Stack(children: [
          // Subtle pattern circles
          Positioned(top: -60, right: -60, child: _circle(220, .08)),
          Positioned(bottom: -80, left: -40, child: _circle(280, .07)),
          Positioned(top: 80, left: 30, child: _circle(60, .1)),
          // Content
          Center(child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(.15), blurRadius: 24, offset: const Offset(0,8))],
                ),
                child: Center(child: Text('A',
                    style: TextStyle(color: AppColors.brand, fontSize: 44, fontWeight: FontWeight.w900,
                        fontFamily: 'Inter', shadows: [Shadow(color: AppColors.brand.withOpacity(.3), blurRadius: 12)]))),
              ),
              const SizedBox(height: 24),
              const Text('Alochi', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              const Text('Monitoring tizimi', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(height: 32),
              _infoRow(Icons.keyboard, 'A, B, C, D — javob tanlash'),
              const SizedBox(height: 10),
              _infoRow(Icons.arrow_back_ios_new, 'Arrow tugmalar — navigatsiya'),
              const SizedBox(height: 10),
              _infoRow(Icons.wifi_off_outlined, 'Offline rejim qo\'llab-quvvatlanadi'),
            ]),
          )),
        ]),
      ),
    ),
    // ── Right form panel ─────────────────────────────────────────────
    Expanded(flex: 5, child: _formPanel()),
  ]);

  Widget _narrowLayout() => _formPanel();

  Widget _circle(double size, double opacity) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(opacity)),
  );

  Widget _infoRow(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.15), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: Colors.white, size: 14),
    ),
    const SizedBox(width: 10),
    Text(text, style: TextStyle(color: Colors.white.withOpacity(.8), fontSize: 13, fontWeight: FontWeight.w500)),
  ]);

  Widget _formPanel() => FadeTransition(
    opacity: _fade,
    child: SlideTransition(
      position: _slide,
      child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Status badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: (_isOnline ? const Color(0xFF10B981) : AppColors.ink3).withOpacity(.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: (_isOnline ? const Color(0xFF10B981) : AppColors.ink3).withOpacity(.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      color: _isOnline ? const Color(0xFF10B981) : AppColors.ink3),
                ),
                const SizedBox(width: 7),
                Text(_isOnline ? 'Server bilan ulandi' : 'Offline rejim',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: _isOnline ? const Color(0xFF10B981) : AppColors.ink2)),
              ]),
            ),
            const SizedBox(height: 28),
            Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Kirish', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink1, letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Text("Login va parolni o'qituvchingizdan oling",
                  style: TextStyle(fontSize: 13, color: AppColors.ink2)),
            ])),
            const SizedBox(height: 24),
            Form(
              key: _formKey,
              child: Column(children: [
                _field(
                  controller: _userCtrl,
                  label: 'Login',
                  hint: 'bolte_01',
                  icon: Icons.person_outline_rounded,
                  action: TextInputAction.next,
                  validator: (v) => v!.isEmpty ? 'Login kiriting' : null,
                ),
                const SizedBox(height: 14),
                _field(
                  controller: _passCtrl,
                  label: 'Parol',
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  obscure: !_showPass,
                  action: TextInputAction.done,
                  onSubmit: (_) => _login(),
                  validator: (v) => v!.isEmpty ? 'Parol kiriting' : null,
                  suffix: IconButton(
                    icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                    onPressed: () => setState(() => _showPass = !_showPass),
                    color: AppColors.ink3,
                  ),
                ),
                // Error
                AnimatedSize(duration: const Duration(milliseconds: 250), child: _error == null ? const SizedBox.shrink()
                  : Padding(
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
                        Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.err, fontSize: 13, fontWeight: FontWeight.w500))),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Login button
                SizedBox(
                  height: 52, width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                      shadowColor: AppColors.brand.withOpacity(.4),
                    ).copyWith(elevation: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.hovered) ? 4 : 0)),
                    child: _loading
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text('Kirish', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ]),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      )),
    ),
  );

  Widget _field({
    required TextEditingController controller, required String label, required String hint,
    required IconData icon, bool obscure = false, TextInputAction? action,
    void Function(String)? onSubmit, String? Function(String?)? validator, Widget? suffix,
  }) => TextFormField(
    controller: controller,
    obscureText: obscure,
    textInputAction: action,
    onFieldSubmitted: onSubmit,
    validator: validator,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.ink1),
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      prefixIcon: Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Icon(icon, size: 18, color: AppColors.ink3)),
      prefixIconConstraints: const BoxConstraints(minWidth: 46),
      suffixIcon: suffix,
      filled: true, fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.brand, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(13), borderSide: const BorderSide(color: AppColors.err)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      labelStyle: const TextStyle(color: AppColors.ink2, fontSize: 13),
    ),
  );
}
