// lib/features/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/pack_cache.dart';
import '../../core/services/connectivity_service.dart';
import '../../shared/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _kServerUrl = 'server_url';
  static const _kDevUrl    = 'http://192.168.1.100:8000';
  static const _kProdUrl   = 'https://api.alochi.org';

  String _version    = '';
  String _build      = '';
  String _serverUrl  = _kProdUrl;
  String _guestPin   = '••••••••';
  bool   _pinVisible = false;
  bool   _isOnline   = false;
  bool   _clearing   = false;
  bool   _pinLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info  = await PackageInfo.fromPlatform();
    final prefs = await SharedPreferences.getInstance();
    final pin   = await PackCacheService.getGuestPin();
    final online = await ConnectivityService.check();
    if (!mounted) return;
    setState(() {
      _version    = info.version;
      _build      = info.buildNumber;
      _serverUrl  = prefs.getString(_kServerUrl) ?? _kProdUrl;
      _guestPin   = pin;
      _isOnline   = online;
      _pinLoading = false;
    });
  }

  Future<void> _setServer(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServerUrl, url);
    setState(() => _serverUrl = url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server: $url'), duration: const Duration(seconds: 2)));
    }
  }

  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cacheni tozalash'),
        content: const Text('Savollar cache o\'chiriladi. Keyingi kirishda server dan qayta yuklanadi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Bekor')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _clearing = true);
    await PackCacheService.clearCache();
    if (mounted) {
      setState(() => _clearing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache tozalandi ✓'), backgroundColor: Color(0xFF16A34A)));
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label nusxalandi'), duration: const Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('Sozlamalar',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [

        // ── Server ──────────────────────────────────────────────────────
        _SectionHeader(title: 'Server', icon: Icons.dns_rounded),
        _Card(child: Column(children: [
          _ServerOption(
            label: 'Production',
            subtitle: _kProdUrl,
            selected: _serverUrl == _kProdUrl,
            onTap: () => _setServer(_kProdUrl),
          ),
          const Divider(height: 1),
          _ServerOption(
            label: 'Development (lokal)',
            subtitle: _kDevUrl,
            selected: _serverUrl == _kDevUrl,
            onTap: () => _setServer(_kDevUrl),
          ),
        ])),
        const SizedBox(height: 8),
        // Internet holati
        _Card(child: Row(children: [
          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isOnline ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
            )),
          Text(_isOnline ? 'Internet: ulangan' : 'Internet: ulanmagan',
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: _isOnline ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            onPressed: () async {
              final online = await ConnectivityService.check();
              if (mounted) setState(() => _isOnline = online);
            },
          ),
        ])),

        const SizedBox(height: 20),
        // ── Xavfsizlik ───────────────────────────────────────────────────
        _SectionHeader(title: 'Xavfsizlik', icon: Icons.lock_outline_rounded),
        _Card(child: Column(children: [
          Row(children: [
            const Icon(Icons.pin_outlined, size: 18, color: AppColors.ink3),
            const SizedBox(width: 10),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Oddiy kirish PIN', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink1)),
              Text('Maktab admini bilishi kerak',
                  style: TextStyle(fontSize: 11, color: AppColors.ink3)),
            ])),
            if (_pinLoading)
              const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _pinVisible ? _guestPin : '•' * _guestPin.length,
                  key: ValueKey(_pinVisible),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      letterSpacing: 4, color: AppColors.ink1),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(_pinVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    size: 18, color: AppColors.ink3),
                onPressed: () => setState(() => _pinVisible = !_pinVisible),
              ),
              if (_pinVisible)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.ink3),
                  onPressed: () => _copyToClipboard(_guestPin, 'PIN'),
                ),
            ],
          ]),
          const Divider(height: 16),
          Text(
            'PIN ni boss.alochi.org/boss/test-packages sahifasidan o\'zgartirish mumkin.',
            style: const TextStyle(fontSize: 11, color: AppColors.ink3, height: 1.4),
          ),
        ])),
        const SizedBox(height: 20),
        // ── Cache ───────────────────────────────────────────────────────
        _SectionHeader(title: 'Saqlangan ma\'lumotlar', icon: Icons.storage_rounded),
        _Card(child: Column(children: [
          Row(children: [
            const Icon(Icons.quiz_rounded, size: 18, color: AppColors.ink3),
            const SizedBox(width: 10),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Savollar cache', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink1)),
              Text('API dan yuklangan savollar lokal saqlanadi',
                  style: TextStyle(fontSize: 11, color: AppColors.ink3)),
            ])),
            SizedBox(
              height: 36,
              child: OutlinedButton.icon(
                onPressed: _clearing ? null : _clearCache,
                icon: _clearing
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delete_outline_rounded, size: 16),
                label: Text(_clearing ? 'Tozalanmoqda...' : 'Tozalash'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ]),
        ])),

        const SizedBox(height: 20),
        // ── App info ─────────────────────────────────────────────────────
        _SectionHeader(title: 'Ilova haqida', icon: Icons.info_outline_rounded),
        _Card(child: Column(children: [
          _InfoRow(label: 'Ilova nomi', value: 'Alochi Monitoring'),
          const Divider(height: 1),
          _InfoRow(label: 'Versiya', value: 'v$_version'),
          const Divider(height: 1),
          _InfoRow(label: 'Build', value: _build.isEmpty ? '—' : _build),
          const Divider(height: 1),
          _InfoRow(label: 'Publisher', value: 'Alochi Education'),
          const Divider(height: 1),
          _InfoRow(label: 'Website', value: 'alochi.org'),
          const Divider(height: 1),
          _InfoRow(label: 'Backend', value: _serverUrl.replaceAll('https://', '')),
        ])),

        const SizedBox(height: 40),
        Center(child: Text('© 2026 Alochi Education',
            style: const TextStyle(fontSize: 11, color: AppColors.ink3))),
        const SizedBox(height: 20),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title; final IconData icon;
  const _SectionHeader({required this.title, required this.icon});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Icon(icon, size: 14, color: AppColors.ink3),
      const SizedBox(width: 6),
      Text(title.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 0.8, color: AppColors.ink3)),
    ]),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class _ServerOption extends StatelessWidget {
  final String label, subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _ServerOption({required this.label, required this.subtitle,
    required this.selected, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        AnimatedContainer(duration: const Duration(milliseconds: 200),
          width: 20, height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border, width: 2),
          ),
          child: selected ? Center(child: Container(
            width: 10, height: 10,
            decoration: const BoxDecoration(
              shape: BoxShape.circle, color: AppColors.brand))) : null),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink1)),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
        ])),
      ]),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [
      Text(label, style: const TextStyle(fontSize: 13, color: AppColors.ink2)),
      const Spacer(),
      Text(value, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink1)),
    ]),
  );
}
