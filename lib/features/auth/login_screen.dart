// lib/features/auth/login_screen.dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../core/db/credential_cache.dart';
import '../../core/services/test_catalog_service.dart';
import '../../shared/theme/app_theme.dart';
import '../test/package_screen.dart';
import '../local_test/local_grade_screen.dart';
import '../local_test/sync_images_button.dart';
import '../local_test/history_screen.dart';
import '../combined/combined_screen.dart';
import '../test/school_launch_screen.dart';
import '../../core/db/test_cache.dart' as testcache;

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
      );
}

class _LoginScreenState extends State<LoginScreen> {
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
  bool _expanded = false; // accordion: login form revealed

  // ── Test katalog banner holati ─────────────────────────────────────────────
  List<CatalogEntry> _catalogEntries = [];
  final Set<String> _downloadedKeys = {};
  // Maktab bo'yicha yuklash holati
  final Set<String> _downloadingSchools = {};
  final Map<String, double> _schoolProgress = {};
  String? _expandedSchoolCode;

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final entries = await testCatalogService.refresh();
      if (mounted) setState(() => _catalogEntries = entries);
    } catch (e) {
      debugPrint('LoginScreen._loadCatalog error: $e');
    }
  }

  Future<void> _launchSchoolTest(CatalogEntry entry, SchoolButton btn) async {
    final testData = await testcache.TestCache.get(entry.testKey);
    if (!mounted) return;
    if (testData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keshdan test topilmadi. Qayta yuklab ko\'ring.'),
          backgroundColor: AppColors.err,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final blob = testData['test_data'] is Map
        ? Map<String, dynamic>.from(testData['test_data'] as Map)
        : testData;
    final rawVariants = blob['variants'];
    final variantCount = rawVariants is Map ? rawVariants.length : 0;

    int? preselectedVariant;
    if (btn.randomVariant) {
      preselectedVariant =
          variantCount > 0 ? math.Random().nextInt(variantCount) + 1 : 1;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SchoolLaunchScreen(
          testData: testData,
          schoolCode: btn.schoolCode,
          schoolLabel: btn.label,
          variantCount: variantCount > 0 ? variantCount : 15,
          preselectedVariant: preselectedVariant,
          pin: btn.pin,
        ),
      ),
    );
  }

  /// Maktab bo'yicha guruhlangan test kartalar ro'yxatini hisoblaydi.
  List<_SchoolGroup> _computeSchoolGroups() {
    final seen = <String>{};
    final groups = <_SchoolGroup>[];
    for (final entry in _catalogEntries) {
      for (final btn in entry.schoolButtons) {
        if (btn.label.isEmpty || btn.schoolCode.isEmpty) continue;
        final code = btn.schoolCode;
        if (!seen.contains(code)) {
          seen.add(code);
          final groupEntries = _catalogEntries
              .where((e) => e.schoolButtons.any((b) => b.schoolCode == code))
              .toList();
          groups.add(_SchoolGroup(
            schoolCode: code,
            label: btn.label,
            pin: btn.pin,
            randomVariant: btn.randomVariant,
            entries: groupEntries,
          ));
        }
      }
    }
    return groups;
  }

  /// Maktab guruhidagi barcha testlarni ketma-ket yuklab, ro'yxatni ko'rsatadi.
  Future<void> _downloadSchool(
      String schoolCode, List<CatalogEntry> entries) async {
    if (_downloadingSchools.contains(schoolCode)) return;

    final toDownload = entries
        .where((e) =>
            e.status == CatalogStatus.notDownloaded ||
            e.status == CatalogStatus.updatable)
        .toList();

    if (toDownload.isEmpty) {
      setState(() => _expandedSchoolCode = schoolCode);
      return;
    }

    setState(() {
      _downloadingSchools.add(schoolCode);
      _schoolProgress[schoolCode] = 0.0;
    });

    final n = toDownload.length;
    var doneCount = 0;
    var failCount = 0;

    for (final entry in toDownload) {
      final ok = await testCatalogService.download(
        entry.testKey,
        onProgress: (done, total) {
          if (mounted) {
            final frac = total > 0 ? done / total : 1.0;
            setState(() {
              _schoolProgress[schoolCode] = (doneCount + frac) / n;
            });
          }
        },
      );
      doneCount++;
      if (ok) {
        _downloadedKeys.add(entry.testKey);
      } else {
        failCount++;
      }
      if (mounted) {
        setState(() => _schoolProgress[schoolCode] = doneCount / n);
      }
    }

    if (mounted) {
      setState(() {
        _downloadingSchools.remove(schoolCode);
        _schoolProgress.remove(schoolCode);
        _expandedSchoolCode = schoolCode;
      });
      if (failCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failCount == n
                  ? 'Yuklab bo\'lmadi. Internetni tekshiring.'
                  : '$failCount ta test yuklanmadi. Qayta urinib ko\'ring.',
            ),
            backgroundColor: AppColors.err,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _loadCatalog();
    }
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Avto-login o'rniga faqat login/parolni formaga to'ldirib qo'yadi
  Future<void> _tryAutoLogin() async {
    try {
      if (!kIsWeb) {
        final creds = await CredentialCache.loadCredentials();
        if (creds != null) {
          _userCtrl.text = creds['username'] ?? '';
          _passCtrl.text = creds['password'] ?? '';
        }
      }

      // Server holatini tekshirish
      final online = await api
          .ping()
          .timeout(const Duration(seconds: 4), onTimeout: () => false);

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
    } catch (e) {
      debugPrint('_login unexpected error: $e');
      if (mounted) {
        setState(() => _error = e is ApiException
            ? e.message
            : "Ulanishda xato. Qayta urinib ko'ring.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-login urinayotganda spinner
    if (_autoLogging) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: AppColors.brand)),
          const SizedBox(height: 16),
          Text('Kirish...',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink3)),
        ])),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_expanded) _login();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(
                  child: ColoredBox(color: Color(0xFFF5F0E8))),
              const Positioned.fill(child: _NetworkBg()),
              Positioned.fill(
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 32),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Logo in white rounded box
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: AppColors.border),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: .10),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Image.asset('assets/logo.png',
                                    width: 56, height: 56, fit: BoxFit.contain),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text('Alochi Monitoring',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.titleLarge
                                    .copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text("Ta'lim monitoring platformasi",
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodyMedium
                                    .copyWith(color: AppColors.ink2)),
                            const SizedBox(height: 24),
                            _catalogBanner(),
                            _routeButtons(),
                            _accordion(),
                            const SizedBox(height: 16),
                            // Bottom row: sync + history
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SyncImagesButton(),
                                const SizedBox(width: 4),
                                TextButton.icon(
                                  onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const HistoryScreen())),
                                  icon: const Icon(Icons.history_rounded,
                                      size: 16),
                                  label: const Text('Oflayn Tarix'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.ink2,
                                    textStyle: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Katalog banner: maktab bo'yicha guruhlanган kartalar.
  /// Maktabsiz testlar (school_buttons bo'sh) ko'rsatilmaydi.
  Widget _catalogBanner() {
    final groups = _computeSchoolGroups();

    if (groups.isEmpty) {
      if (_catalogEntries.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.muted,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 18, color: AppColors.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Internet kerak (testlarni yuklash uchun)',
                  style:
                      AppTextStyles.labelMedium.copyWith(color: AppColors.ink2),
                ),
              ),
            ]),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: groups.map(_schoolCard).toList(),
      ),
    );
  }

  Widget _schoolCard(_SchoolGroup group) {
    final isDownloading = _downloadingSchools.contains(group.schoolCode);
    final progress = _schoolProgress[group.schoolCode];
    final isExpanded = _expandedSchoolCode == group.schoolCode;

    final allCached = group.entries.every((e) =>
        e.status == CatalogStatus.cached ||
        e.status == CatalogStatus.cachedOnly ||
        e.status == CatalogStatus.updatable ||
        _downloadedKeys.contains(e.testKey));

    final isOffline = group.entries.isNotEmpty &&
        group.entries.every((e) => e.status == CatalogStatus.cachedOnly);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isOffline ? AppColors.muted : AppColors.primaryMuted,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isOffline
                    ? AppColors.border
                    : AppColors.primary.withValues(alpha: .25),
              ),
            ),
            child: Row(children: [
              Icon(
                allCached
                    ? Icons.check_circle_rounded
                    : (isOffline
                        ? Icons.offline_pin_rounded
                        : Icons.cloud_download_rounded),
                size: 20,
                color: allCached
                    ? AppColors.ok
                    : (isOffline ? AppColors.ink3 : AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.label,
                      style: AppTextStyles.labelLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isOffline ? AppColors.ink2 : AppColors.ink1,
                      ),
                    ),
                    Text(
                      '${group.entries.length} ta test',
                      style:
                          AppTextStyles.caption.copyWith(color: AppColors.ink2),
                    ),
                    if (isDownloading && progress != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            color: AppColors.primary,
                            backgroundColor:
                                AppColors.primary.withValues(alpha: .18),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isDownloading)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                      value: progress,
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      '${(progress * 100).round()}%',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ])
              else if (allCached)
                GestureDetector(
                  onTap: () => setState(() {
                    _expandedSchoolCode =
                        isExpanded ? null : group.schoolCode;
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: isExpanded ? AppColors.ink3 : AppColors.ok,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.list_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isExpanded ? 'Yopish' : 'Testlar',
                        style: AppTextStyles.caption.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ]),
                  ),
                )
              else
                GestureDetector(
                  onTap: () =>
                      _downloadSchool(group.schoolCode, group.entries),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.download_rounded,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        'Yuklash',
                        style: AppTextStyles.caption.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
          if (isExpanded) _buildSchoolTestList(group),
        ],
      ),
    );
  }

  Widget _buildSchoolTestList(_SchoolGroup group) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: group.entries.map((entry) {
          final btn = entry.schoolButtons.firstWhere(
            (b) => b.schoolCode == group.schoolCode,
            orElse: () => SchoolButton(
              label: group.label,
              schoolCode: group.schoolCode,
              randomVariant: group.randomVariant,
              pin: group.pin,
            ),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                const Icon(Icons.assignment_rounded,
                    size: 18, color: AppColors.ink3),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.title,
                    style: AppTextStyles.labelLarge
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                GestureDetector(
                  onTap: () => _launchSchoolTest(entry, btn),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.play_arrow_rounded,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'Boshlash',
                        style: AppTextStyles.caption.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _routeButtons() {
    return IntrinsicHeight(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _routeButton(
            icon: Icons.monitor_rounded,
            label: 'Alochi Monitoring',
            active: _expanded,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _routeButton(
            icon: Icons.quiz_rounded,
            label: 'Testlar',
            active: false,
            disabled: true,
            badge: 'Tez kunda',
            onTap: null,
          ),
        ),
      ],
    ));
  }

  Widget _routeButton({
    required IconData icon,
    required String label,
    required bool active,
    VoidCallback? onTap,
    bool disabled = false,
    String? badge,
  }) {
    final iconColor =
        disabled ? AppColors.ink3 : (active ? Colors.white : AppColors.ink2);
    final labelColor =
        disabled ? AppColors.ink3 : (active ? Colors.white : AppColors.ink1);

    Widget cardChild = Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: iconColor),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
        if (badge != null)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge,
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 9.5,
                ),
              ),
            ),
          ),
      ],
    );

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: disabled
            ? AppColors.muted
            : (active ? AppColors.brand : AppColors.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? AppColors.brand : AppColors.border,
          width: active ? 2 : 1,
        ),
      ),
      child: cardChild,
    );

    return disabled
        ? Opacity(opacity: .6, child: content)
        : GestureDetector(onTap: onTap, child: content);
  }

  Widget _accordion() {
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: !_expanded
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Server status row
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _checkingOnline
                                ? SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: _statusColor))
                                : Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _statusColor)),
                            const SizedBox(width: 7),
                            Text(_statusMsg,
                                style: AppTextStyles.labelMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: _checkingOnline
                                        ? AppColors.brand
                                        : (_isOnline
                                            ? AppColors.ok
                                            : AppColors.ink2))),
                            if (!_checkingOnline && !_isOnline) ...[
                              const Spacer(),
                              TextButton(
                                onPressed: _retryOnlineCheck,
                                style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    minimumSize: const Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap),
                                child: Text('Qayta tekshirish',
                                    style: AppTextStyles.labelMedium
                                        .copyWith(color: AppColors.brand)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Kirish',
                            style: AppTextStyles.titleMedium
                                .copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text("Login va parolni o'qituvchingizdan oling",
                            style: AppTextStyles.labelMedium
                                .copyWith(color: AppColors.ink2)),
                        const SizedBox(height: 16),
                        _field(
                          controller: _userCtrl,
                          label: 'Login',
                          hint: '',
                          icon: Icons.person_outline_rounded,
                          action: TextInputAction.next,
                          validator: (v) =>
                              v!.isEmpty ? 'Login kiriting' : null,
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
                          validator: (v) =>
                              v!.isEmpty ? 'Parol kiriting' : null,
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
                        // Error box
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
                                      color:
                                          AppColors.err.withValues(alpha: .07),
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
                                              style: AppTextStyles.labelLarge
                                                  .copyWith(
                                                      color: AppColors.err,
                                                      fontWeight:
                                                          FontWeight.w400))),
                                    ]),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 18),
                        // Primary "Kirish" — KEEP dynamic online/offline text+icon
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _loading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brand,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13)),
                            ),
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Icon(_isOnline
                                    ? Icons.arrow_forward_rounded
                                    : Icons.wifi_off_rounded),
                            label: Text(_isOnline ? 'Kirish' : 'Offline kirish',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const LocalGradeScreen())),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.ink2,
                              side: const BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13)),
                            ),
                            icon: const Icon(Icons.groups_rounded, size: 18),
                            label: const Text(
                                'Oddiy kirish (Internet kerak emas)',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const CombinedScreen())),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF5B21B6),
                              side: const BorderSide(
                                  color: Color(0xFF7C3AED), width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13)),
                            ),
                            icon: const Icon(Icons.menu_book_rounded,
                                size: 18, color: Color(0xFF7C3AED)),
                            label: const Text('Monitoring Test Unit 1',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

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
        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink1),
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

// ─────────────────────────────────────────────────────────────────────────────
// _SchoolGroup — maktab bo'yicha guruhlangan test ro'yxati
// ─────────────────────────────────────────────────────────────────────────────

class _SchoolGroup {
  final String schoolCode;
  final String label;
  final String? pin;
  final bool randomVariant;
  final List<CatalogEntry> entries;

  const _SchoolGroup({
    required this.schoolCode,
    required this.label,
    this.pin,
    required this.randomVariant,
    required this.entries,
  });
}

