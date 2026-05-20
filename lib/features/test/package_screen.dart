// lib/features/test/package_screen.dart
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../auth/login_screen.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import 'confirm_screen.dart';
import 'local_test_screen.dart';
import '../../core/services/pack_cache.dart';
import '../../core/services/connectivity_service.dart';
import '../home/update_banner.dart';
import '../settings/settings_screen.dart';

class PackageScreen extends StatefulWidget {
  final StudentSession session;
  final bool offline;
  const PackageScreen({super.key, required this.session, this.offline = false});
  @override State<PackageScreen> createState() => _PackageScreenState();
}

class _PackageScreenState extends State<PackageScreen> with SingleTickerProviderStateMixin {
  List<TestPackage> _packages = [];
  bool _loading = true;
  bool _loadingMonitoringTest = false;
  String? _error;
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    ConnectivityService.instance.startMonitoring();
    _load();
  }
  @override void dispose() { _anim.dispose(); super.dispose(); }

  Future<void> _confirmLogout(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Chiqish', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text("Hisobdan chiqmoqchimisiz?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.err,
              minimumSize: const Size(100, 40),
            ),
            child: const Text('Chiqish'),
          ),
        ],
      ),
    );
    if (ok == true && ctx.mounted) {
      api.clearToken();
      Navigator.pushAndRemoveUntil(
        ctx,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final pkgs = await api.getPackages(widget.session.grade);
      setState(() { _packages = pkgs; _loading = false; });
      _anim.forward(from: 0);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  /// Monitoring testni yuklab ochish:
  /// 1. PackCacheService.load() — version check → cache → fallback
  /// 2. LocalTestScreen ga o'tish
  Future<void> _openMonitoringTest() async {
    if (_loadingMonitoringTest) return;
    setState(() => _loadingMonitoringTest = true);
    try {
      final pack = await PackCacheService.load(grade: widget.session.grade);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LocalTestScreen(
            session: widget.session,
            preloadedPack: pack,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingMonitoringTest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      body: Column(children: [
        const UpdateBanner(),
        Expanded(child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Student header ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF9500), Color(0xFFF97316)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(child: Text(
                        s.studentName.isNotEmpty ? s.studentName[0].toUpperCase() : 'T',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                      )),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.studentName,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.ink1)),
                      const SizedBox(height: 4),
                      Row(children: [
                        _chip('\${s.grade}-sinf', AppColors.math),
                        const SizedBox(width: 6),
                        _chip('Variant \${s.variant}', AppColors.brand),
                        if (s.groupName != null) ...[
                          const SizedBox(width: 6),
                          _chip(s.groupName!, AppColors.ink2),
                        ],
                      ]),
                    ])),
                    // Settings button
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Sozlamalar',
                      child: IconButton(
                        onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen())),
                        icon: const Icon(Icons.settings_outlined, size: 20),
                        style: IconButton.styleFrom(
                          foregroundColor: AppColors.ink2,
                          backgroundColor: AppColors.bg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    // Logout button
                    const SizedBox(width: 8),
                    Tooltip(
                      message: "Chiqish",
                      child: IconButton(
                        onPressed: () => _confirmLogout(context),
                        icon: const Icon(Icons.logout_rounded, size: 20),
                        style: IconButton.styleFrom(
                          foregroundColor: AppColors.ink2,
                          backgroundColor: AppColors.bg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 28),
                const Text('Test tanlang',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink1,
                        letterSpacing: -0.5)),
                const SizedBox(height: 4),
                const Text('Mavjud monitoring testlaridan birini tanlang',
                    style: TextStyle(color: AppColors.ink2, fontSize: 13)),
                const SizedBox(height: 18),

                // ── Content ─────────────────────────────────────────
                if (_loading)
                  ..._buildSkeletons()
                else if (_error != null)
                  _buildError()
                else if (_packages.isEmpty)
                  _buildEmpty()
                else
                  FadeTransition(
                    opacity: _fade,
                    child: Column(children: [
                      // ── Local monitoring test (Vocab + Ingliz + Mat) ──
                      _buildLocalTestCard(),
                      const SizedBox(height: 4),
                      if (_packages.isNotEmpty) ..._packages.map((pkg) => _buildPackageCard(pkg)),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      )),
    ]),
  );
  }

  List<Widget> _buildSkeletons() => List.generate(2, (i) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _Skeleton(height: 88, radius: 16, delay: i * 0.15),
  ));

  Widget _buildError() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.err.withOpacity(.05),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.err.withOpacity(.2)),
    ),
    child: Column(children: [
      const Icon(Icons.wifi_off_outlined, color: AppColors.err, size: 36),
      const SizedBox(height: 12),
      const Text('Ulanishda xatolik', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.err)),
      const SizedBox(height: 4),
      Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.ink2), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      SizedBox(
        width: 160,
        child: ElevatedButton(onPressed: _load, child: const Text('Qayta urinish')),
      ),
    ]),
  );

  Widget _buildEmpty() => Container(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(color: AppColors.brandLight, borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.inbox_outlined, color: AppColors.brand, size: 32),
      ),
      const SizedBox(height: 16),
      const Text('Testlar hali yuklanmagan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink1)),
      const SizedBox(height: 4),
      const Text('O\'qituvchingiz test yuklagandan so\'ng qayta urinib ko\'ring',
          style: TextStyle(fontSize: 12, color: AppColors.ink2), textAlign: TextAlign.center),
    ]),
  );

  Widget _buildLocalTestCard() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _loadingMonitoringTest ? null : _openMonitoringTest,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFf59e0b), width: 1.5),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF7ED), Color(0xFFFFFFFF)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
          ),
          child: Row(children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFf59e0b), Color(0xFFf97316)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: _loadingMonitoringTest
                  ? const Center(child: SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)))
                  : const Center(child: Text('M', style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white))),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Monitoring Test',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                      color: AppColors.ink1)),
              const SizedBox(height: 6),
              Row(children: [
                _statChip('58', "Lug'at", const Color(0xFFf59e0b)),
                const SizedBox(width: 8),
                _statChip('25', 'Ingliz', const Color(0xFF0284c7)),
                const SizedBox(width: 8),
                _statChip('83', 'Jami', AppColors.ink2),
              ]),
            ])),
            const SizedBox(width: 8),
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFf59e0b), size: 20),
            ),
          ]),
        ),
      ),
    ),
  );

  Widget _buildPackageCard(TestPackage pkg) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ConfirmScreen(session: widget.session, package: pkg))),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                color: AppColors.brandLight, borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.assignment_outlined, color: AppColors.brand, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pkg.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.ink1)),
              const SizedBox(height: 8),
              Row(children: [
                _statChip('${pkg.mathCount}', 'Math', AppColors.math),
                const SizedBox(width: 8),
                _statChip('${pkg.engCount}', 'Ingliz', AppColors.eng),
                const SizedBox(width: 8),
                _statChip('${pkg.totalCount}', 'Jami', AppColors.ink2),
              ]),
            ])),
            const SizedBox(width: 8),
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.chevron_right_rounded, color: AppColors.ink2, size: 20),
            ),
          ]),
        ),
      ),
    ),
  );

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  );

  Widget _statChip(String val, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(.08), borderRadius: BorderRadius.circular(8)),
    child: RichText(text: TextSpan(children: [
      TextSpan(text: val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
      TextSpan(text: ' $label', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color.withOpacity(.7))),
    ])),
  );
}

// Shimmer-like skeleton widget
class _Skeleton extends StatefulWidget {
  final double height;
  final double radius;
  final double delay;
  const _Skeleton({required this.height, required this.radius, this.delay = 0});
  @override State<_Skeleton> createState() => _SkeletonState();
}
class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        color: Color.lerp(AppColors.gray100, AppColors.gray200, _anim.value),
      ),
    ),
  );
}
