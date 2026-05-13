// lib/features/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../shared/theme/app_theme.dart';
import '../test/package_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey  = GlobalKey<FormState>();
  bool _loading   = false;
  bool _showPass  = false;
  bool _isOnline  = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    api.ping().then((ok) { if (mounted) setState(() => _isOnline = ok); });
  }

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
               : "Server xatosi: ${e.statusCode}";
      });
    } catch (_) {
      setState(() => _error = "Internet aloqasi yo'q");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): _login},
        child: Focus(
          autofocus: true,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(children: [
                  // Logo
                  Container(
                    width: 68, height: 68,
                    decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(18)),
                    child: const Center(child: Text('A', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900))),
                  ),
                  const SizedBox(height: 20),
                  Text('Alochi Monitoring', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Test tizimiga kirish', style: TextStyle(color: AppColors.ink2, fontSize: 14)),
                  const SizedBox(height: 16),

                  // Online badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_isOnline ? AppColors.ok : AppColors.err).withOpacity(.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle, size: 8, color: _isOnline ? AppColors.ok : AppColors.err),
                      const SizedBox(width: 6),
                      Text(
                        _isOnline ? 'Server bilan ulandi' : 'Offline rejim',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: _isOnline ? AppColors.ok : AppColors.err),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 28),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(children: [
                          TextFormField(
                            controller: _userCtrl,
                            decoration: const InputDecoration(labelText: 'Login', prefixIcon: Icon(Icons.person_outline)),
                            autofocus: true,
                            textInputAction: TextInputAction.next,
                            validator: (v) => v!.isEmpty ? 'Login kiriting' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passCtrl,
                            decoration: InputDecoration(
                              labelText: 'Parol',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _showPass = !_showPass),
                              ),
                            ),
                            obscureText: !_showPass,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _login(),
                            validator: (v) => v!.isEmpty ? 'Parol kiriting' : null,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.err.withOpacity(.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(children: [
                                const Icon(Icons.error_outline, color: AppColors.err, size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.err, fontSize: 13))),
                              ]),
                            ),
                          ],
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: _loading ? null : _login,
                            child: _loading
                                ? const SizedBox(width: 20, height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Kirish'),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text("Login va parolni o'qituvchingizdan oling",
                      style: TextStyle(color: AppColors.ink3, fontSize: 12), textAlign: TextAlign.center),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { _userCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }
}
