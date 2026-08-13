// lib/features/auth/login_screen.dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/db/credential_cache.dart';
import '../../core/services/test_catalog_service.dart';
import '../../core/network/connectivity_provider.dart';
import '../../core/network/connectivity_service.dart' show SignalTier;
import '../../shared/widgets/signal_strength_indicator.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/student_palette.dart';
import '../../shared/widgets/hover_region.dart';
import '../../shared/widgets/segmented_tabs.dart';

import '../local_test/sync_images_button.dart';

import '../../core/services/update_service.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../core/widgets/skeleton.dart';
import '../../shared/widgets/language_switcher.dart';
import '../session/session_providers.dart';

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

/// Test mavjudlik oynasi matni ("14:00–17:00"). Faqat [entry.lockedUntil]
/// va [entry.availableUntil] ikkalasi ham bo'lganda chaqiriladi — aks
/// holda joriy bir nuqtali qulf ko'rinishi (dd.MM.yyyy HH:mm) o'zgarishsiz
/// qoladi (backward-compat, TASK: test availability window badge).
String _testTimeWindowLabel(CatalogEntry entry) {
  final from = DateFormat('HH:mm').format(entry.lockedUntil!.toLocal());
  final until = DateFormat('HH:mm').format(entry.availableUntil!.toLocal());
  return '$from–$until';
}

/// "NEW" pill yonida ko'rsatiladigan sana matni ("Qo'shildi: 30.07.2026").
/// Faqat [entry.isNew] va [entry.createdAt] != null bo'lganda chaqiriladi.
String _newBadgeDateLabel(AppLocalizations l10n, CatalogEntry entry) {
  final date = DateFormat('dd.MM.yyyy').format(entry.createdAt!.toLocal());
  return l10n.newBadgeAddedOn(date);
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
          AppColors.flame,
          AppColors.violet,
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
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _showPass = false;
  bool _isOnline = false;
  bool _checkingOnline = true;
  bool _autoLogging = true; // birinchi ochilganda auto-login urinish
  // ponytail: tarjima matni state'da saqlanmaydi — checking/online/offline
  // holati saqlanadi, matn build vaqtida l10n orqali hisoblanadi (til
  // almashganda ham to'g'ri ko'rinishi uchun).
  bool? _statusOnline; // null = tekshirilmoqda
  String? _error;
  // Accordion: login form revealed. Starts expanded — the "Войти как ученик"
  // segment is pre-selected/active per the pixel-perfect mockup (shot12.png),
  // so the form is visible on first paint instead of requiring a tap.
  bool _expanded = true;

  // ── Test katalog banner holati ─────────────────────────────────────────────
  List<CatalogEntry> _catalogEntries = [];

  // ── Yangilanish badge holati ────────────────────────────────────────────────
  UpdateInfo? _updateInfo;
  bool _isDownloadingUpdate = false;
  double _updateProgress = 0.0;

  // ── Ilova versiyasi (login ekranida pastki chapda ko'rsatish uchun) ────────
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _tryAutoLogin();
    _loadCatalog();
    UpdateService.instance.fetchUpdateInfo().then((info) {
      if (mounted && info != null) setState(() => _updateInfo = info);
    });
    // The login screen is where a machine sits idle between test sessions,
    // often for hours — re-check periodically so a machine whose startup
    // check failed (slow/unreliable lab wifi) still learns about an update
    // without needing a full app relaunch.
    UpdateService.instance.startPeriodicRecheck((info) {
      if (mounted) setState(() => _updateInfo = info);
    });
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {
      // silent — version badge simply won't render
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final entries = await testCatalogService.refresh();
      if (mounted) setState(() => _catalogEntries = entries);
      // Fire-and-forget background pre-download so locked tests are already
      // cached on-device by the time their lock lifts.
      _autoPrefetchLocked(entries);
    } catch (e) {
      debugPrint('LoginScreen._loadCatalog error: $e');
    }
  }

  /// Background pre-download for locked-but-not-yet-downloaded tests, so the
  /// device already has the package cached once the lock lifts. Randomized
  /// 5-35s delay between each download avoids a thundering herd against the
  /// backend when many devices refresh their catalog around the same time.
  Future<void> _autoPrefetchLocked(List<CatalogEntry> entries) async {
    final targets = entries.where(
      (e) => e.lockedUntil != null && e.status == CatalogStatus.notDownloaded,
    );
    for (final entry in targets) {
      await Future.delayed(Duration(seconds: 5 + math.Random().nextInt(30)));
      if (!mounted) return;
      try {
        await testCatalogService.download(entry.testKey);
      } catch (e) {
        debugPrint(
            'LoginScreen._autoPrefetchLocked(${entry.testKey}) error: $e');
      }
    }
  }

  @override
  void dispose() {
    UpdateService.instance.stopPeriodicRecheck();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
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
      _statusOnline = online;
    });
  }

  Future<bool> _checkOnline() async {
    if (mounted) {
      setState(() {
        _checkingOnline = true;
        _statusOnline = null;
      });
    }

    final online = await checkOnlineWithRetry(() => api.ping());

    if (mounted) {
      setState(() {
        _isOnline = online;
        _checkingOnline = false;
        _statusOnline = online;
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
          // Offline-cache write is a nice-to-have (lets the student log in
          // again without internet later) — it must NOT block a student who
          // already authenticated successfully with the server. A platform
          // storage failure here (e.g. Windows DPAPI unavailable in a
          // locked-down kiosk account) used to surface as a generic
          // "Ulanishda xato" even though login had already succeeded.
          try {
            await CredentialCache.saveCredentials(username, password);
            await CredentialCache.saveSession(session, username, password);
          } catch (cacheError) {
            debugPrint('CredentialCache write failed (non-fatal): $cacheError');
          }
          if (!mounted) return;
          ProviderScope.containerOf(context)
              .read(currentStudentSessionProvider.notifier)
              .state = session;
          context.pushReplacement('/my_tests', extra: {'session': session});
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
        ProviderScope.containerOf(context)
            .read(currentStudentSessionProvider.notifier)
            .state = session;
        context.pushReplacement('/my_tests',
            extra: {'session': session, 'offline': !online});
        return;
      }

      // Hech narsa topilmadi
      if (!mounted) return;
      setState(() => _error = online
          ? "Server xatosi. Qayta urinib ko'ring."
          : "Internet yo'q va bu login ilgari saqlanmagan.");
    } catch (e) {
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
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);

    // Auto-login urinayotganda spinner
    if (_autoLogging) {
      return Scaffold(
        backgroundColor: pal.chipBg,
        body: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: AppColors.brand)),
          const SizedBox(height: 16),
          Text(l10n.loggingIn,
              style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3)),
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
              Positioned.fill(child: ColoredBox(color: pal.chipBg)),
              const Positioned.fill(child: _NetworkBg()),
              Positioned.fill(
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 32),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Container(
                          // Single pixel-perfect card (shot12.png): logo,
                          // title, status, tab switcher, form and bottom
                          // sync/history row all live inside this one shell
                          // instead of floating separately over the network
                          // background.
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: pal.surface,
                            borderRadius: AppRadii.roundedXl2,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Logo in rounded box
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: pal.surface,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: pal.border),
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
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.contain),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(l10n.appTitle,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.titleLarge.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: pal.ink1)),
                              const SizedBox(height: 4),
                              Text(l10n.appSubtitle,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodyMedium
                                      .copyWith(color: pal.ink2)),
                              const SizedBox(height: 10),
                              // Always-visible online/offline + signal-strength
                              // indicator. Sourced purely from signalProvider —
                              // independent of _isOnline/_statusMsg (accordion
                              // dot) and the retry-based
                              // checkOnlineWithRetry()/_checkOnline() flow.
                              Consumer(
                                builder: (context, ref, _) {
                                  final signal = ref.watch(signalProvider);
                                  final isOnline = !signal.checking &&
                                      signal.tier != SignalTier.none;
                                  final label = signal.checking
                                      ? l10n.serverChecking
                                      : (isOnline
                                          ? l10n.serverConnected
                                          : l10n.offlineMode);
                                  final dotColor = signal.checking
                                      ? AppColors.brand
                                      : (isOnline ? AppColors.ok : pal.ink3);
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      signal.checking
                                          ? SizedBox(
                                              width: 8,
                                              height: 8,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 1.5,
                                                  color: dotColor),
                                            )
                                          : Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: dotColor),
                                            ),
                                      const SizedBox(width: 6),
                                      Text(label,
                                          style: AppTextStyles.caption
                                              .copyWith(color: dotColor)),
                                      const SizedBox(width: 10),
                                      SignalStrengthIndicator(
                                          tier: signal.tier),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 20),
                              // 3-segment tab switcher (shot12.png): student
                              // login is the only functional segment, the
                              // other two are locked "coming soon" chips —
                              // see lib/shared/widgets/segmented_tabs.dart.
                              SegmentedTabsRow(
                                pal: pal,
                                items: [
                                  SegmentedTabItem(
                                    icon: Icons.desktop_windows_rounded,
                                    label: l10n.studentLoginButton,
                                    selected: _expanded,
                                    onTap: () => setState(
                                        () => _expanded = !_expanded),
                                  ),
                                  SegmentedTabItem(
                                    icon: Icons.lock_outline_rounded,
                                    label: l10n.teacherProctorLogin,
                                    disabled: true,
                                    badge: l10n.comingSoon,
                                  ),
                                  SegmentedTabItem(
                                    icon: Icons.quiz_rounded,
                                    label: l10n.testsRoute,
                                    disabled: true,
                                    badge: l10n.comingSoon,
                                  ),
                                ],
                              ),
                              _accordion(pal),
                              const SizedBox(height: 16),
                              // Bottom card: offline-image sync + offline
                              // history, each row with a trailing chevron.
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: pal.border),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                      child: Row(
                                        children: [
                                          const Expanded(
                                            child: Align(
                                              alignment:
                                                  Alignment.centerLeft,
                                              child: SyncImagesButton(),
                                            ),
                                          ),
                                          Icon(Icons.chevron_right_rounded,
                                              size: 18, color: pal.ink3),
                                          const SizedBox(width: 6),
                                        ],
                                      ),
                                    ),
                                    Divider(height: 1, color: pal.border),
                                    _bottomActionRow(
                                      icon: Icons.history_rounded,
                                      label: l10n.offlineHistory,
                                      pal: pal,
                                      onTap: () => context
                                          .push('/history', extra: {}),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _newTestsButton(),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _languagePill(pal),
                        if (_updateInfo != null) ...[
                          const SizedBox(height: 8),
                          _updateBadge(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _appVersionBadge(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Top-right pill wrapping the shared [LanguageSwitcher] dropdown so it
  /// reads as a pill button per the mockup, matching the "Школы" pill's
  /// visual weight without touching the shared widget itself.
  Widget _languagePill(StudentPalette pal) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const LanguageSwitcher(),
      );

  /// One row of the bottom sync/history card: icon + label + trailing
  /// chevron, matching shot12.png.
  Widget _bottomActionRow({
    required IconData icon,
    required String label,
    required StudentPalette pal,
    required VoidCallback onTap,
  }) =>
      HoverRegion(
        builder: (context, isHovered) => GestureDetector(
          onTap: onTap,
          child: Container(
            color: isHovered ? pal.hoverBg : Colors.transparent,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: pal.ink2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: AppTextStyles.labelLarge
                          .copyWith(color: pal.ink1, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: pal.ink3),
              ],
            ),
          ),
        ),
      );

  Widget _appVersionBadge() {
    if (_appVersion.isEmpty) return const SizedBox.shrink();
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Text(
      'v$_appVersion',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: pal.ink3.withValues(alpha: .45),
      ),
    );
  }

  Widget _newTestsButton() {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final downloadable = _catalogEntries
        .where((e) =>
            e.status == CatalogStatus.notDownloaded ||
            e.status == CatalogStatus.updatable)
        .length;
    final hasNew = downloadable > 0;

    return Semantics(
      button: true,
      label: l10n.schools,
      child: HoverRegion(
        builder: (context, isHovered) => GestureDetector(
          onTap: _showCatalogSheet,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: hasNew
                  ? (isHovered ? AppColors.brand : AppColors.primary)
                  : (isHovered ? pal.hoverBg : pal.surface),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasNew ? AppColors.primary : pal.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.school_rounded,
                  size: 16,
                  color: hasNew ? Colors.white : pal.ink2,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.schools,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: hasNew ? Colors.white : pal.ink1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCatalogSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CatalogBottomSheet(
        initialEntries: _catalogEntries,
        onRefreshed: _loadCatalog,
      ),
    ).whenComplete(_loadCatalog);
  }

  /// Downloads+installs the current [_updateInfo], showing a persistent
  /// SnackBar with a manual retry action if it ultimately fails (after
  /// UpdateService's own internal retries) instead of relying solely on the
  /// silently-opened browser fallback tab, which a distracted lab proctor
  /// can easily miss. The SnackBar's retry action re-invokes this same
  /// method, so tapping it starts a fresh download attempt.
  Future<void> _attemptUpdateDownload() async {
    if (_isDownloadingUpdate || _updateInfo == null) return;
    setState(() {
      _isDownloadingUpdate = true;
      _updateProgress = 0.0;
    });
    final success = await UpdateService.instance.downloadAndInstallUpdate(
      _updateInfo!,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _updateProgress = progress);
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _isDownloadingUpdate = false;
    });
    if (!success) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.updateDownloadFailedMsg),
        backgroundColor: AppColors.err,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: l10n.retry,
          textColor: Colors.white,
          onPressed: _attemptUpdateDownload,
        ),
      ));
    }
  }

  Widget _updateBadge() {
    if (_updateInfo == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: _isDownloadingUpdate ? l10n.loadingLabelDots : l10n.newVersionAvailable,
      child: HoverRegion(
        builder: (context, isHovered) => GestureDetector(
          onTap: _attemptUpdateDownload,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isHovered ? AppColors.brand : AppColors.primary,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isDownloadingUpdate)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                      value: _updateProgress > 0 ? _updateProgress : null,
                    ),
                  )
                else
                  const Icon(
                    Icons.system_update_alt_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                const SizedBox(width: 6),
                Text(
                  _isDownloadingUpdate
                      ? '${l10n.loadingLabelDots} ${(_updateProgress * 100).toInt()}%'
                      : l10n.newVersionAvailable,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _accordion(StudentPalette pal) {
    final l10n = AppLocalizations.of(context)!;
    return ClipRect(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: !_expanded
            ? const SizedBox(width: double.infinity)
            : Padding(
                // No nested card chrome here — the outer white card (build())
                // already frames this content per shot12.png, so this is just
                // the login form itself, not a second box-in-a-box.
                padding: const EdgeInsets.only(top: 16),
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
                                        strokeWidth: 2,
                                        color: _statusColor(pal)))
                                : Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _statusColor(pal))),
                            const SizedBox(width: 7),
                            Text(
                                _statusOnline == null
                                    ? l10n.serverChecking
                                    : (_statusOnline!
                                        ? l10n.serverConnected
                                        : l10n.offlineMode),
                                style: AppTextStyles.labelMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: _checkingOnline
                                        ? AppColors.brand
                                        : (_isOnline
                                            ? AppColors.ok
                                            : pal.ink2))),
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
                                child: Text(l10n.retryCheck,
                                    style: AppTextStyles.labelMedium
                                        .copyWith(color: AppColors.brand)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(l10n.loginTitle,
                            style: AppTextStyles.titleMedium.copyWith(
                                fontWeight: FontWeight.w800, color: pal.ink1)),
                        const SizedBox(height: 2),
                        Text(l10n.loginInstruction,
                            style: AppTextStyles.labelMedium
                                .copyWith(color: pal.ink2)),
                        const SizedBox(height: 16),
                        _field(
                          pal: pal,
                          controller: _userCtrl,
                          focusNode: _userFocus,
                          label: l10n.usernameLabel,
                          hint: '',
                          icon: Icons.person_outline_rounded,
                          action: TextInputAction.next,
                          onSubmit: (_) => _passFocus.requestFocus(),
                          validator: (v) =>
                              v!.isEmpty ? l10n.usernameRequired : null,
                        ),
                        const SizedBox(height: 14),
                        _field(
                          pal: pal,
                          controller: _passCtrl,
                          focusNode: _passFocus,
                          label: l10n.passwordLabel,
                          hint: '',
                          icon: Icons.lock_outline_rounded,
                          obscure: !_showPass,
                          action: TextInputAction.done,
                          onSubmit: (_) => _login(),
                          validator: (v) =>
                              v!.isEmpty ? l10n.passwordRequired : null,
                          suffix: IconButton(
                            icon: Icon(
                                _showPass
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 18),
                            onPressed: () =>
                                setState(() => _showPass = !_showPass),
                            color: pal.ink3,
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
                            label: Text(
                                _isOnline ? l10n.loginTitle : l10n.offlineLogin,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                context.push('/local_grade', extra: {}),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.ink2,
                              side: const BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13)),
                            ),
                            icon: const Icon(Icons.groups_rounded, size: 18),
                            label: Text(l10n.localGradeEntry,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                context.push('/combined', extra: {}),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.violetDark,
                              side: const BorderSide(
                                  color: AppColors.violet, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13)),
                            ),
                            icon: const Icon(Icons.menu_book_rounded,
                                size: 18, color: AppColors.violet),
                            label: Text(l10n.monitoringTestUnit1,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  Widget _field({
    required StudentPalette pal,
    required TextEditingController controller,
    FocusNode? focusNode,
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
        focusNode: focusNode,
        obscureText: obscure,
        textInputAction: action,
        onFieldSubmitted: onSubmit,
        validator: validator,
        style: AppTextStyles.bodyMedium.copyWith(color: pal.ink1),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(icon, size: 18, color: pal.ink3)),
          prefixIconConstraints: const BoxConstraints(minWidth: 46),
          suffixIcon: suffix,
          filled: true,
          fillColor: pal.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: pal.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(color: pal.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: AppColors.brand, width: 2)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: AppColors.err)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          labelStyle: TextStyle(color: pal.ink2, fontSize: 13),
        ),
      );

  Color _statusColor(StudentPalette pal) {
    if (_checkingOnline) return AppColors.brand;
    return _isOnline ? AppColors.ok : pal.ink3;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CatalogBottomSheet — "Yangi testlar" modal panel
// ─────────────────────────────────────────────────────────────────────────────

class _CatalogBottomSheet extends StatefulWidget {
  final List<CatalogEntry> initialEntries;
  final VoidCallback onRefreshed;

  const _CatalogBottomSheet({
    required this.initialEntries,
    required this.onRefreshed,
  });

  @override
  State<_CatalogBottomSheet> createState() => _CatalogBottomSheetState();
}

class _CatalogBottomSheetState extends State<_CatalogBottomSheet> {
  late List<CatalogEntry> _entries;
  final Set<String> _downloadingKeys = {};
  bool _loading = true;

  List<Map<String, String>> _schools = [];

  @override
  void initState() {
    super.initState();
    _entries = List.from(widget.initialEntries);
    _loading = _entries.isEmpty;
    _initialLoad();
  }

  Future<void> _initialLoad() async {
    try {
      final results = await Future.wait([
        testCatalogService.refresh(),
        api.fetchCatalogSchools(),
      ]);
      if (!mounted) return;
      setState(() {
        _entries = results[0] as List<CatalogEntry>;
        _schools = results[1] as List<Map<String, String>>;
        _loading = false;
      });
    } catch (e) {
      debugPrint('CatalogSheet initialLoad error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final fresh = await testCatalogService.refresh();
      if (mounted) {
        setState(() {
          _entries = fresh;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('CatalogSheet refresh error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(CatalogEntry entry) async {
    if (_downloadingKeys.contains(entry.testKey)) return;
    setState(() => _downloadingKeys.add(entry.testKey));
    try {
      final ok = await testCatalogService.download(entry.testKey);
      if (!mounted) return;
      if (ok) {
        widget.onRefreshed();
        await _refresh();
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${entry.title} ${l10n.downloaded}'),
            backgroundColor: AppColors.ok,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ));
        }
      } else {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.downloadError),
            backgroundColor: AppColors.err,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } finally {
      if (mounted) setState(() => _downloadingKeys.remove(entry.testKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFAF8F4),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.download_rounded,
                        size: 18, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Text(l10n.schools,
                      style: AppTextStyles.titleMedium
                          .copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: 4,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, __) =>
                          const Skeleton(height: 72, borderRadius: 16),
                    )
                  : (_entries.isEmpty && _schools.isEmpty)
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_rounded,
                                  size: 36, color: AppColors.ink3),
                              const SizedBox(height: 8),
                              Text(l10n.testsNotFound,
                                  style: AppTextStyles.bodyMedium
                                      .copyWith(color: AppColors.ink2)),
                            ],
                          ),
                        )
                      : _buildGroupedList(scrollCtrl),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList(ScrollController scrollCtrl) {
    const umumiy = '__umumiy__';
    final Map<String, String> codeToLabel = {};
    final Map<String, List<CatalogEntry>> groups = {};

    for (final entry in _entries) {
      if (entry.schoolButtons.isEmpty) {
        groups.putIfAbsent(umumiy, () => []).add(entry);
      } else {
        for (final sb in entry.schoolButtons) {
          codeToLabel[sb.schoolCode] = sb.label;
          groups.putIfAbsent(sb.schoolCode, () => []).add(entry);
        }
      }
    }

    final codes = groups.keys.toList()
      ..sort((a, b) {
        if (a == umumiy) return 1;
        if (b == umumiy) return -1;
        final aNum = int.tryParse(a);
        final bNum = int.tryParse(b);
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }
        return a.compareTo(b);
      });

    final widgets = <Widget>[];
    final schoolCodes = codes.where((c) => c != umumiy).toList();
    final coveredCodes = codes.where((c) => c != umumiy).toSet();
    final otherSchools = _schools
        .where((s) => !coveredCodes.contains(s['school_code']))
        .toList();

    final List<Widget> schoolWidgets = [];

    // 1. Add schools that have catalog entries
    for (final code in schoolCodes) {
      final l10n = AppLocalizations.of(context)!;
      final label = codeToLabel[code] ?? l10n.schoolPrefix(code);
      schoolWidgets.add(_buildSchoolCard(code, label, groups[code]!.first));
    }

    // 2. Add other schools from the global list
    for (final school in otherSchools) {
      final l10n = AppLocalizations.of(context)!;
      final schoolCode = school['school_code'] ?? '';
      final schoolLabel = school['label'] ?? '';
      final label =
          schoolLabel.isNotEmpty ? schoolLabel : l10n.schoolPrefix(schoolCode);
      schoolWidgets.add(_buildSchoolCard(schoolCode, label, null));
    }

    if (schoolWidgets.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Color(0x1ADE8E52),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.school_rounded,
                            color: AppColors.accent, size: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.schools,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.charcoal,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: schoolWidgets
                      .expand((w) => [w, const SizedBox(width: 12)])
                      .toList()
                    ..removeLast(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (codes.contains(umumiy)) {
      final groupEntries = groups[umumiy]!
        ..sort((a, b) =>
            (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));

      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0x1ADE8E52),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.library_books_rounded,
                      color: AppColors.accent, size: 14),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)!.generalTests,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.charcoal,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      );

      final List<Widget> testItems = [];
      for (var i = 0; i < groupEntries.length; i++) {
        testItems.add(_buildItem(groupEntries[i]));
        if (i < groupEntries.length - 1) {
          testItems.add(const Divider(height: 1, color: Color(0x99E5E7EB)));
        }
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                children: testItems,
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      itemCount: widgets.length,
      itemBuilder: (_, i) => widgets[i],
    );
  }

  Widget _buildItem(CatalogEntry entry) {
    final l10n = AppLocalizations.of(context)!;
    final isDownloading = _downloadingKeys.contains(entry.testKey);
    final isDone = entry.status == CatalogStatus.cached ||
        entry.status == CatalogStatus.cachedOnly;
    final isUpdatable = entry.status == CatalogStatus.updatable;
    final isLocked =
        entry.lockedUntil != null && entry.lockedUntil!.isAfter(DateTime.now());

    void openSession() {
      final container = ProviderScope.containerOf(context);
      container.read(selectedCatalogEntryProvider.notifier).state = entry;
      // No specific school tapped here (this is the "Umumiy testlar" list) —
      // clear any stale value left over from a previous school-card tap so
      // SessionSetupScreen falls back to schoolButtons.first correctly.
      container.read(selectedSchoolCodeProvider.notifier).state = null;
      context.pop();
      context.push('/session_setup', extra: {'testKey': entry.testKey});
    }

    void handleStartTap() {
      if (isLocked) {
        final lockMessage = entry.availableUntil != null
            ? _testTimeWindowLabel(entry)
            : '🔒 ${DateFormat('dd.MM.yyyy HH:mm').format(entry.lockedUntil!.toLocal())} ${l10n.opensAt}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(lockMessage),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      openSession();
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDone
            ? handleStartTap
            : (isDownloading ? null : () => _download(entry)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDone ? const Color(0x1ADE8E52) : AppColors.gray100,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isDownloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        )
                      : Icon(
                          isLocked
                              ? Icons.lock_clock_rounded
                              : (isDone
                                  ? Icons.check_rounded
                                  : Icons.cloud_download_rounded),
                          color: isDone ? AppColors.accent : AppColors.ink3,
                          size: 20,
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.charcoal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.isNew) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              l10n.newBadge,
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 9.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          isDownloading
                              ? Icons.sync_rounded
                              : (isDone
                                  ? Icons.file_download_done_rounded
                                  : Icons.download_rounded),
                          size: 12,
                          color: AppColors.stone,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isLocked
                              ? (entry.availableUntil != null
                                  ? _testTimeWindowLabel(entry)
                                  : '🔒 ${DateFormat('dd.MM.yyyy HH:mm').format(entry.lockedUntil!.toLocal())} ${l10n.opensAt}')
                              : isUpdatable && !isDownloading
                                  ? l10n.newVersionAvailable
                                  : isDownloading
                                      ? l10n.downloading
                                      : isDone
                                          ? l10n.downloaded
                                          : l10n.notDownloaded,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.stone,
                          ),
                        ),
                      ],
                    ),
                    if (entry.isNew && entry.createdAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _newBadgeDateLabel(l10n, entry),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.stone,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (isUpdatable && !isDownloading)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () => _download(entry),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.accent,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.accent),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 0),
                        minimumSize: const Size(0, 36),
                      ),
                      child: Text(
                        l10n.update,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ElevatedButton.icon(
                onPressed: isDone
                    ? handleStartTap
                    : (isDownloading ? null : () => _download(entry)),
                icon: isDownloading
                    ? const SizedBox.shrink()
                    : Icon(
                        isDone
                            ? Icons.play_arrow_rounded
                            : Icons.cloud_download_rounded,
                        size: 16,
                      ),
                label: Text(
                  isDone ? l10n.start : l10n.download,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isDone ? AppColors.accent : AppColors.gray100,
                  foregroundColor: isDone ? Colors.white : AppColors.charcoal,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSchoolCard(
      String schoolCode, String label, CatalogEntry? entry) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            context.pop();
            final targetEntry = entry ??
                CatalogEntry(
                  testKey: '',
                  title: label,
                  grade: 0,
                  version: 0,
                  status: CatalogStatus.notDownloaded,
                  schoolButtons: [
                    SchoolButton(
                      pin: '',
                      label: label,
                      schoolCode: schoolCode,
                      randomVariant: false,
                    ),
                  ],
                );
            final container = ProviderScope.containerOf(context);
            container.read(selectedCatalogEntryProvider.notifier).state =
                targetEntry;
            container.read(selectedSchoolCodeProvider.notifier).state =
                schoolCode;
            context.push('/session_setup',
                extra: {'testKey': targetEntry.testKey});
          },
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0x1ADE8E52),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.school_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.charcoal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
