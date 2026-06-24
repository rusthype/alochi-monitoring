// lib/features/test/package_screen.dart
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../auth/login_screen.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import 'confirm_screen.dart';
import '../interhouse/interhouse_data.dart';
import '../interhouse/interhouse_runner.dart';

class PackageScreen extends StatefulWidget {
  final StudentSession session;
  final bool offline;
  const PackageScreen({super.key, required this.session, this.offline = false});
  @override
  State<PackageScreen> createState() => _PackageScreenState();
}

class _PackageScreenState extends State<PackageScreen>
    with SingleTickerProviderStateMixin {
  List<TestPackage> _packages = [];
  bool _loading = true;
  String? _error;
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _confirmLogout(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Chiqish',
            style: TextStyle(fontWeight: FontWeight.w800)),
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
    if (!widget.session.hasActiveExam) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pkgs = await api.getPackages(widget.session.grade!);
      setState(() {
        _packages = pkgs;
        _loading = false;
      });
      _anim.forward(from: 0);
    } on ApiException catch (e) {
      setState(() {
        _error = e.statusCode == 403
            ? 'Faol imtihon topilmadi yoki muddati tugagan'
            : e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Yuklanmadi. Qayta urinib ko\'ring.';
        _loading = false;
      });
    }
  }

  // ── initials helper ─────────────────────────────────────────────────────
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'T';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  // ── meta string (sinf · Variant · guruh) ───────────────────────────────
  String _metaLine(StudentSession s) {
    final parts = <String>[];
    if (s.grade != null) parts.add('${s.grade}-sinf');
    if (s.variant != null) parts.add('Variant ${s.variant}');
    if (s.groupName != null) parts.add(s.groupName!);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header card ───────────────────────────────────────
                  _HeaderCard(
                    initials: _initials(s.studentName),
                    name: s.studentName,
                    meta: _metaLine(s),
                    onLogout: () => _confirmLogout(context),
                  ),
                  const SizedBox(height: 24),

                  // ── Section title ─────────────────────────────────────
                  const Text('Test tanlang',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink1,
                          letterSpacing: -0.4)),
                  const SizedBox(height: 4),
                  const Text('Mavjud monitoring testlaridan birini tanlang',
                      style: TextStyle(color: AppColors.ink2, fontSize: 13)),
                  const SizedBox(height: 20),

                  // ── Content ───────────────────────────────────────────
                  if (_loading)
                    ..._buildSkeletons()
                  else if (_error != null)
                    _buildError()
                  else if (!widget.session.hasActiveExam)
                    _buildNoExam()
                  else if (_packages.isEmpty)
                    _buildEmpty()
                  else
                    FadeTransition(
                      opacity: _fade,
                      child: Column(
                          children: _packages
                              .map((pkg) => _buildPackageCard(pkg))
                              .toList()),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Skeletons ─────────────────────────────────────────────────────────────
  List<Widget> _buildSkeletons() => List.generate(
      2,
      (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Skeleton(height: 86, radius: 18, delay: i * 0.15),
          ));

  // ── Error state ───────────────────────────────────────────────────────────
  Widget _buildError() => Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0FDC2626), blurRadius: 8, offset: Offset(0, 2)),
            BoxShadow(
                color: Color(0x0ADC2626),
                blurRadius: 24,
                offset: Offset(0, 10)),
          ],
        ),
        child: Column(children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppColors.errMuted,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(Icons.wifi_off_outlined,
                color: AppColors.err, size: 34),
          ),
          const SizedBox(height: 16),
          const Text('Ulanishda xatolik',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.ink1)),
          const SizedBox(height: 6),
          Text(_error!,
              style: const TextStyle(fontSize: 13, color: AppColors.ink2),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: _TealButton(
              onTap: _load,
              icon: Icons.refresh_rounded,
              label: 'Qayta urinish',
            ),
          ),
        ]),
      );

  // ── No exam ───────────────────────────────────────────────────────────────
  Widget _buildNoExam() => Container(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: _softShadow,
        ),
        child: Column(children: [
          _IconBox(
            icon: Icons.event_busy_outlined,
            bg: AppColors.warnMuted,
            color: AppColors.ink2,
          ),
          const SizedBox(height: 16),
          const Text('Aktiv imtihon yo\'q',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.ink1)),
          const SizedBox(height: 6),
          const Text('Sizga hali imtihon biriktirilmagan\nyoki muddati tugagan',
              style: TextStyle(fontSize: 13, color: AppColors.ink2),
              textAlign: TextAlign.center),
        ]),
      );

  // ── Empty ─────────────────────────────────────────────────────────────────
  Widget _buildEmpty() => Container(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: _softShadow,
        ),
        child: Column(children: [
          _IconBox(
            icon: Icons.assignment_outlined,
            bg: AppColors.brandLight,
            color: AppColors.brand,
          ),
          const SizedBox(height: 16),
          const Text('Testlar hali yuklanmagan',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.ink1)),
          const SizedBox(height: 6),
          const Text(
              'O\'qituvchingiz test yuklagandan so\'ng\nqayta urinib ko\'ring',
              style: TextStyle(fontSize: 13, color: AppColors.ink2),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: _TealButton(
              onTap: _load,
              icon: Icons.refresh_rounded,
              label: 'Yangilash',
            ),
          ),
        ]),
      );

  // ── Package card ──────────────────────────────────────────────────────────
  Widget _buildPackageCard(TestPackage pkg) {
    final isEven = _packages.indexOf(pkg).isEven;
    final iconBg = isEven ? AppColors.brandLight : AppColors.primaryMuted;
    final iconColor = isEven ? AppColors.brand : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _PressCard(
        onTap: () => _openPackage(pkg),
        child: Row(children: [
          // Icon box
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.description_outlined, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          // Title + stats
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(pkg.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.ink1)),
                const SizedBox(height: 8),
                Row(children: [
                  _StatChip(
                      val: '${pkg.mathCount}',
                      label: 'Math',
                      color: AppColors.math),
                  const SizedBox(width: 6),
                  _StatChip(
                      val: '${pkg.engCount}',
                      label: 'Ingliz',
                      color: AppColors.eng),
                  const SizedBox(width: 6),
                  _StatChip(
                      val: '${pkg.totalCount}',
                      label: 'Jami',
                      color: AppColors.ink2),
                ]),
              ])),
          const SizedBox(width: 8),
          // Chevron
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.chevron_right_rounded,
                color: AppColors.ink3, size: 20),
          ),
        ]),
      ),
    );
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _openPackage(TestPackage pkg) {
    if (pkg.title.toLowerCase().contains('interhouse')) {
      _launchInterhouse(pkg);
    } else {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ConfirmScreen(session: widget.session, package: pkg)));
    }
  }

  Future<void> _launchInterhouse(TestPackage pkg) async {
    final variant = widget.session.variant;
    if (variant == null) return;
    final testData = await IhLoader.load();
    if (!mounted) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => InterhouseRunner(
                  isOnline: true,
                  session: widget.session,
                  packageId: pkg.id,
                  variant: variant,
                  testData: testData,
                )));
  }
}

// ── Shared shadow ─────────────────────────────────────────────────────────────
const _softShadow = [
  BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x06000000), blurRadius: 24, offset: Offset(0, 10)),
];

// ── Header card ───────────────────────────────────────────────────────────────
class _HeaderCard extends StatelessWidget {
  final String initials;
  final String name;
  final String meta;
  final VoidCallback onLogout;
  const _HeaderCard({
    required this.initials,
    required this.name,
    required this.meta,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0BE8954E), blurRadius: 4, offset: Offset(0, 2)),
          BoxShadow(
              color: Color(0x08E8954E), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1F6F65), Color(0xFF0EA5E9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Center(
            child: Text(initials,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.5)),
          ),
        ),
        const SizedBox(width: 12),
        // Name + meta
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink1)),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(meta,
                style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ])),
        const SizedBox(width: 8),
        // Logout
        Tooltip(
          message: 'Chiqish',
          child: GestureDetector(
            onTap: onLogout,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.logout_rounded,
                  color: AppColors.ink2, size: 18),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Icon box (for empty states) ───────────────────────────────────────────────
class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color color;
  const _IconBox({required this.icon, required this.bg, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: .12),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Icon(icon, color: color, size: 34),
      );
}

// ── Full-width teal button ────────────────────────────────────────────────────
class _TealButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  const _TealButton(
      {required this.onTap, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 22),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: 15),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ]),
          ),
        ),
      );
}

// ── Press card (scale on tap) ─────────────────────────────────────────────────
class _PressCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _PressCard({required this.onTap, required this.child});
  @override
  State<_PressCard> createState() => _PressCardState();
}

class _PressCardState extends State<_PressCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: _softShadow,
            ),
            child: widget.child,
          ),
        ),
      );
}

// ── Stat chip ─────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String val;
  final String label;
  final Color color;
  const _StatChip(
      {required this.val, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: RichText(
            text: TextSpan(children: [
          TextSpan(
              text: val,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: color)),
          TextSpan(
              text: ' $label',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: color.withValues(alpha: .7))),
        ])),
      );
}

// ── Shimmer skeleton ──────────────────────────────────────────────────────────
class _Skeleton extends StatefulWidget {
  final double height;
  final double radius;
  final double delay;
  const _Skeleton({required this.height, required this.radius, this.delay = 0});
  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            color:
                Color.lerp(AppColors.gray100, AppColors.gray200, _anim.value),
          ),
        ),
      );
}
