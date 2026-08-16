// lib/features/auth/login_screen.dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/db/credential_cache.dart';
import '../../core/network/connectivity_provider.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/services/test_catalog_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/hover_region.dart';
import '../../shared/widgets/signal_strength_indicator.dart';

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

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _showPass = false;
  bool _userEdited = false;
  bool _passwordEdited = false;
  // ponytail: tarjima matni state'da saqlanmaydi — checking/online/offline
  // holati saqlanadi, matn build vaqtida l10n orqali hisoblanadi (til
  // almashganda ham to'g'ri ko'rinishi uchun).
  String? _error;
  int _selectedTab = 0;

  late final AnimationController _entranceController;
  late final Animation<double> _entranceOpacity;
  late final Animation<double> _entranceScale;
  late final AnimationController _pulseController;

  // ── Test katalog banner holati ─────────────────────────────────────────────
  List<CatalogEntry> _catalogEntries = [];

  // ── Yangilanish badge holati ────────────────────────────────────────────────
  UpdateInfo? _updateInfo;
  // null = yuklanmayapti; ValueNotifier — progress har chaqirilganda butun
  // login formasini setState bilan qayta qurmaslik uchun (ekran
  // "provisaydi" degan xabar shundan edi — _updateBadge() ValueListenableBuilder
  // bilan o'raladi, faqat shu widget qayta quriladi).
  final ValueNotifier<double?> _updateProgress = ValueNotifier(null);

  // ── Ilova versiyasi (login ekranida pastki chapda ko'rsatish uchun) ────────
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    final entranceCurve = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _entranceOpacity = entranceCurve;
    _entranceScale = Tween<double>(begin: .95, end: 1).animate(entranceCurve);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _entranceController.forward();

    // All startup I/O is deliberately fire-and-forget. The complete login
    // card is already in the first frame; credentials, ping, catalog and
    // update state hydrate it in the background without gating the UI.
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
    _updateProgress.dispose();
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Avto-login o'rniga faqat login/parolni formaga to'ldirib qo'yadi
  Future<void> _tryAutoLogin() async {
    try {
      if (!kIsWeb) {
        final creds = await CredentialCache.loadCredentials();
        if (creds != null) {
          // Frame one is immediately interactive. Never let a slower cache
          // read overwrite credentials the user has already started typing.
          if (!_userEdited) _userCtrl.text = creds['username'] ?? '';
          if (!_passwordEdited) _passCtrl.text = creds['password'] ?? '';
        }
      }
    } catch (_) {
      // Credentials are only a convenience; the form is already usable.
    }
  }

  Future<bool> _checkOnline() async {
    return checkOnlineWithRetry(() => api.ping());
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
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
            setState(() => _error = l10n.invalidCredentials);
            return;
          }
          if (e.statusCode == 429) {
            setState(() => _error = l10n.tooManyAttempts);
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
      setState(() =>
          _error = online ? l10n.serverErrorRetry : l10n.offlineNoSavedLogin);
    } catch (e) {
      if (mounted) {
        setState(() => _error = l10n.connectionError);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _LoginPalette.from(context);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final horizontalInset = viewportWidth < 520 ? 16.0 : 24.0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_selectedTab == 0) _login();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: palette.canvas,
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [palette.canvas, palette.canvasWarm],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 760,
                      height: 760,
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            Color(0x1FFF7A1A),
                            Color(0x08FF7A1A),
                            Colors.transparent,
                          ],
                          stops: [0, .38, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: RepaintBoundary(child: _NetworkBg()),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        horizontalInset,
                        76,
                        horizontalInset,
                        32,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(0, constraints.maxHeight - 108),
                        ),
                        child: Center(
                          child: FadeTransition(
                            opacity: _entranceOpacity,
                            child: ScaleTransition(
                              scale: _entranceScale,
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 460),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: _buildUnifiedCard(palette),
                                ),
                              ),
                            ),
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
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _newTestsButton(palette),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _languageCapsule(palette),
                            if (_updateInfo != null) ...[
                              const SizedBox(width: 8),
                              _updateBadge(
                                palette,
                                compact: viewportWidth < 720,
                              ),
                            ],
                          ],
                        ),
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
                    child: _appVersionBadge(palette),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appVersionBadge(_LoginPalette palette) {
    if (_appVersion.isEmpty) return const SizedBox.shrink();
    return Text(
      'v$_appVersion',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: palette.ink3.withValues(alpha: .55),
      ),
    );
  }

  Widget _languageCapsule(_LoginPalette palette) => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
          boxShadow: _floatingControlShadow,
        ),
        child: Center(
          child: LanguageSwitcher(
            foregroundColor: palette.ink1,
            iconColor: palette.ink2,
            dropdownColor: palette.surface,
          ),
        ),
      );

  Widget _newTestsButton(_LoginPalette palette) {
    final l10n = AppLocalizations.of(context)!;
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
                  ? (isHovered ? palette.brandMuted : palette.surface)
                  : (isHovered ? palette.hover : palette.surface),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
              boxShadow: _floatingControlShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.school_rounded,
                  size: 16,
                  color: hasNew ? AppColors.brand : palette.ink2,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.schools,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: palette.ink1,
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
    if (_updateProgress.value != null || _updateInfo == null) return;
    _updateProgress.value = 0.0;
    final success = await UpdateService.instance.downloadAndInstallUpdate(
      _updateInfo!,
      onProgress: (progress) {
        if (mounted) _updateProgress.value = progress;
      },
    );
    if (!mounted) return;
    _updateProgress.value = null;
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

  Widget _updateBadge(_LoginPalette palette, {bool compact = false}) {
    if (_updateInfo == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    // ValueListenableBuilder: progress tick'lari faqat shu kichik widget'ni
    // qayta quradi — butun login formasini emas (avvalgi setState har bir
    // tarmoq chunk'ida to'liq ekranni qayta chizib, interfeysni "provisirib"
    // yuborardi).
    return ValueListenableBuilder<double?>(
      valueListenable: _updateProgress,
      builder: (context, progress, _) {
        final isDownloading = progress != null;
        return Semantics(
          button: true,
          label:
              isDownloading ? l10n.loadingLabelDots : l10n.newVersionAvailable,
          child: HoverRegion(
            builder: (context, isHovered) => GestureDetector(
              onTap: _attemptUpdateDownload,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isHovered ? palette.brandMuted : palette.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: palette.border),
                  boxShadow: _floatingControlShadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDownloading)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.brand,
                          ),
                          value: progress > 0 ? progress : null,
                        ),
                      )
                    else
                      const Icon(
                        Icons.system_update_alt_rounded,
                        size: 16,
                        color: AppColors.brand,
                      ),
                    if (!compact) ...[
                      const SizedBox(width: 6),
                      Text(
                        isDownloading
                            ? '${l10n.loadingLabelDots} ${(progress * 100).toInt()}%'
                            : l10n.newVersionAvailable,
                        style: AppTextStyles.labelMedium.copyWith(
                          color: palette.ink1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnifiedCard(_LoginPalette palette) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          key: const ValueKey('login-unified-card'),
          width: 460,
          margin: const EdgeInsets.only(top: 46),
          padding: const EdgeInsets.fromLTRB(24, 68, 24, 20),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .06),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.appTitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.titleLarge.copyWith(
                  color: palette.ink1,
                  fontSize: 22,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.45,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.appSubtitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: palette.ink2,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              _buildNetworkStatus(palette),
              const SizedBox(height: 16),
              _buildSegmentedControl(palette),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: _selectedTab == 0
                    ? _buildLoginForm(palette)
                    : _buildProctorPanel(palette),
              ),
              const SizedBox(height: 18),
              _buildDivider(palette),
              const SizedBox(height: 12),
              _buildOfflineActions(palette),
            ],
          ),
        ),
        Container(
          width: 92,
          height: 92,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: palette.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .10),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
        ),
      ],
    );
  }

  Widget _buildNetworkStatus(_LoginPalette palette) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer(
      builder: (context, ref, _) {
        final signal = ref.watch(signalProvider);
        final isOnline = !signal.checking && signal.tier != SignalTier.none;
        final label = signal.checking
            ? l10n.serverChecking
            : (isOnline ? l10n.serverConnected : l10n.offlineMode);
        final color = signal.checking
            ? AppColors.brand
            : (isOnline ? palette.success : palette.ink2);

        return Center(
          child: TextButton(
            onPressed: signal.checking
                ? null
                : () => ref.read(signalProvider.notifier).refresh(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: isOnline ? palette.successMuted : palette.muted,
              shape: const StadiumBorder(),
              foregroundColor: color,
              disabledForegroundColor: color,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: Tween<double>(begin: .55, end: 1).animate(
                    _pulseController,
                  ),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .86, end: 1.18).animate(
                      CurvedAnimation(
                        parent: _pulseController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                SignalStrengthIndicator(
                  tier: signal.tier,
                  maxHeight: 11,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSegmentedControl(_LoginPalette palette) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 54,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.segmentTrack,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOutCubic,
            alignment:
                _selectedTab == 0 ? Alignment.centerLeft : Alignment.center,
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8A3D), Color(0xFFFF6B00)],
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF7A1A).withValues(alpha: .22),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _routeButton(
                  key: const ValueKey('login-tab-student'),
                  icon: Icons.desktop_windows_rounded,
                  label: l10n.studentLoginButton,
                  active: _selectedTab == 0,
                  palette: palette,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
              ),
              Expanded(
                child: _routeButton(
                  key: const ValueKey('login-tab-proctor'),
                  icon: Icons.lock_outline_rounded,
                  label: l10n.proctorLoginTab,
                  active: _selectedTab == 1,
                  palette: palette,
                  onTap: () => setState(() => _selectedTab = 1),
                ),
              ),
              Expanded(
                child: _routeButton(
                  key: const ValueKey('login-tab-tests'),
                  icon: Icons.help_outline_rounded,
                  label: l10n.testsRoute,
                  active: false,
                  palette: palette,
                  disabled: true,
                  badge: l10n.comingSoon,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _routeButton({
    Key? key,
    required IconData icon,
    required String label,
    required bool active,
    required _LoginPalette palette,
    VoidCallback? onTap,
    bool disabled = false,
    String? badge,
  }) {
    final foreground = active ? Colors.white : palette.ink2;
    return Semantics(
      button: true,
      enabled: !disabled,
      selected: active,
      label: label,
      child: Opacity(
        opacity: disabled ? .58 : 1,
        child: InkWell(
          key: key,
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: foreground),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption.copyWith(
                          color: foreground,
                          fontSize: 10.5,
                          height: 1.05,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (badge != null)
                  Positioned(
                    right: 2,
                    bottom: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5C28E),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge,
                        style: AppTextStyles.caption.copyWith(
                          color: const Color(0xFF7C3F0A),
                          fontSize: 8,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
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

  Widget _buildLoginForm(_LoginPalette palette) {
    final l10n = AppLocalizations.of(context)!;
    return ClipRect(
      key: const ValueKey('login-form'),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Container(
            padding: EdgeInsets.zero,
            color: Colors.transparent,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(
                    palette: palette,
                    controller: _userCtrl,
                    focusNode: _userFocus,
                    label: l10n.usernameLabel,
                    hint: '',
                    icon: Icons.person_outline_rounded,
                    action: TextInputAction.next,
                    onChanged: (_) => _userEdited = true,
                    onSubmit: (_) => _passFocus.requestFocus(),
                    validator: (v) => v!.isEmpty ? l10n.usernameRequired : null,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    palette: palette,
                    controller: _passCtrl,
                    focusNode: _passFocus,
                    label: l10n.passwordLabel,
                    hint: '',
                    icon: Icons.lock_outline_rounded,
                    obscure: !_showPass,
                    action: TextInputAction.done,
                    onChanged: (_) => _passwordEdited = true,
                    onSubmit: (_) => _login(),
                    validator: (v) => v!.isEmpty ? l10n.passwordRequired : null,
                    suffix: IconButton(
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.elasticOut,
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        ),
                        child: Icon(
                          _showPass
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          key: ValueKey(_showPass),
                          size: 19,
                          color: palette.ink3,
                        ),
                      ),
                      onPressed: () => setState(() => _showPass = !_showPass),
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
                                color: AppColors.err.withValues(alpha: .07),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: AppColors.err.withValues(alpha: .2)),
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
                                                fontWeight: FontWeight.w400))),
                              ]),
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  _buildPrimaryButton(l10n, palette),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/local_grade', extra: {}),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: palette.fieldFill,
                        foregroundColor: palette.ink2,
                        side: BorderSide(color: palette.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.groups_rounded, size: 18),
                      label: Text(l10n.localGradeEntry,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/combined', extra: {}),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: palette.fieldFill,
                        foregroundColor: AppColors.flame,
                        side: const BorderSide(
                            color: AppColors.flame, width: 1.2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.menu_book_rounded,
                          size: 18, color: AppColors.flame),
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
      ),
    );
  }

  Widget _buildPrimaryButton(
    AppLocalizations l10n,
    _LoginPalette palette,
  ) =>
      SizedBox(
        height: 50,
        child: HoverRegion(
          builder: (context, isHovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(
              0,
              isHovered && !_loading ? -2 : 0,
              0,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _loading
                    ? const [Color(0xFFD97735), Color(0xFFC95300)]
                    : const [Color(0xFFFF8A3D), Color(0xFFFF6B00)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF7A1A).withValues(
                    alpha: isHovered ? .30 : .20,
                  ),
                  blurRadius: isHovered ? 18 : 14,
                  offset: Offset(0, isHovered ? 8 : 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _loading ? null : _login,
                borderRadius: BorderRadius.circular(14),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: _loading
                        ? const SizedBox(
                            key: ValueKey('login-loading'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            key: const ValueKey('login-ready'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.loginTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 19,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildProctorPanel(_LoginPalette palette) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      key: const ValueKey('proctor-panel'),
      constraints: const BoxConstraints(minHeight: 318),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: palette.muted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: palette.brandMuted,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.school_outlined,
              color: AppColors.flame,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.proctorLoginTab,
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.ink1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.selectSchool,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: palette.ink2),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _showCatalogSheet,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.flame,
                backgroundColor: palette.fieldFill,
                side: const BorderSide(color: AppColors.flame, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.school_rounded, size: 18),
              label: Text(
                l10n.schools,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(_LoginPalette palette) => Row(
        children: [
          Expanded(child: Divider(color: palette.border, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: palette.border,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: Divider(color: palette.border, height: 1)),
        ],
      );

  Widget _buildOfflineActions(_LoginPalette palette) {
    final l10n = AppLocalizations.of(context)!;
    final chipDecoration = BoxDecoration(
      color: palette.fieldFill,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: palette.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .035),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Container(
              constraints: const BoxConstraints(minHeight: 42),
              decoration: chipDecoration,
              child: const Center(child: SyncImagesButton()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Container(
              height: 42,
              decoration: chipDecoration,
              child: TextButton.icon(
                onPressed: () => context.push('/history', extra: {}),
                style: TextButton.styleFrom(
                  foregroundColor: palette.ink2,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.history_rounded, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(l10n.offlineHistory),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required _LoginPalette palette,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputAction? action,
    ValueChanged<String>? onChanged,
    void Function(String)? onSubmit,
    String? Function(String?)? validator,
    Widget? suffix,
  }) =>
      AnimatedBuilder(
        animation: focusNode,
        builder: (context, child) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: palette.fieldFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focusNode.hasFocus ? AppColors.flame : palette.border,
              width: focusNode.hasFocus ? 1.5 : 1,
            ),
            boxShadow: focusNode.hasFocus
                ? const [
                    BoxShadow(
                      color: Color(0x2BFF7A1A),
                      blurRadius: 10,
                    ),
                  ]
                : const [],
          ),
          child: child,
        ),
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          textInputAction: action,
          onChanged: onChanged,
          onFieldSubmitted: onSubmit,
          validator: validator,
          style: AppTextStyles.bodyMedium.copyWith(color: palette.ink1),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint.isEmpty ? null : hint,
            floatingLabelStyle: const TextStyle(color: AppColors.flame),
            labelStyle: TextStyle(color: palette.ink2),
            prefixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(icon, size: 18, color: palette.ink3),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 46),
            suffixIcon: suffix,
            filled: true,
            fillColor: Colors.transparent,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.err),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.err, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            hintStyle: TextStyle(color: palette.ink2, fontSize: 14),
          ),
        ),
      );

  List<BoxShadow> get _floatingControlShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: .08),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
}

class _LoginPalette {
  final Color canvas;
  final Color canvasWarm;
  final Color surface;
  final Color fieldFill;
  final Color segmentTrack;
  final Color muted;
  final Color hover;
  final Color border;
  final Color cardBorder;
  final Color ink1;
  final Color ink2;
  final Color ink3;
  final Color brandMuted;
  final Color success;
  final Color successMuted;

  const _LoginPalette({
    required this.canvas,
    required this.canvasWarm,
    required this.surface,
    required this.fieldFill,
    required this.segmentTrack,
    required this.muted,
    required this.hover,
    required this.border,
    required this.cardBorder,
    required this.ink1,
    required this.ink2,
    required this.ink3,
    required this.brandMuted,
    required this.success,
    required this.successMuted,
  });

  factory _LoginPalette.from(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? const _LoginPalette(
            canvas: Color(0xFF121214),
            canvasWarm: Color(0xFF171412),
            surface: Color(0xFF1E1E22),
            fieldFill: Color(0xFF232328),
            segmentTrack: Color(0xFF28282E),
            muted: Color(0xFF28282E),
            hover: Color(0xFF303037),
            border: Color(0xFF38383F),
            cardBorder: Color(0x0FFFFFFF),
            ink1: Color(0xFFF7F7F8),
            ink2: Color(0xFFA1A1AA),
            ink3: Color(0xFF71717A),
            brandMuted: Color(0xFF3B261C),
            success: Color(0xFF22C98B),
            successMuted: Color(0xFF17352C),
          )
        : const _LoginPalette(
            canvas: Color(0xFFF8F9FA),
            canvasWarm: Color(0xFFFAF7F2),
            surface: Color(0xFFFFFFFF),
            fieldFill: Color(0xFFFFFFFF),
            segmentTrack: Color(0xFFF3F4F6),
            muted: Color(0xFFF7F7F8),
            hover: Color(0xFFF5F5F5),
            border: Color(0xFFE5E7EB),
            cardBorder: Color(0xFFF0F1F3),
            ink1: Color(0xFF171717),
            ink2: Color(0xFF6B7280),
            ink3: Color(0xFF9CA3AF),
            brandMuted: Color(0xFFFFF1E6),
            success: Color(0xFF0F9A6E),
            successMuted: Color(0xFFECFDF5),
          );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LaunchArgs — result of the launch dialog
// ─────────────────────────────────────────────────────────────────────────────

class _LaunchArgs {
  final int variant;
  final String firstName;
  final String lastName;
  final String school;
  final String? group;

  const _LaunchArgs({
    required this.variant,
    required this.firstName,
    required this.lastName,
    required this.school,
    this.group,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// _LaunchDialog — variant selector + student info form (2-step)
// Follows the same step pattern as CombinedScreen.
// ─────────────────────────────────────────────────────────────────────────────

class _LaunchDialog extends StatefulWidget {
  final CatalogEntry entry;
  const _LaunchDialog({required this.entry});

  @override
  State<_LaunchDialog> createState() => _LaunchDialogState();
}

class _LaunchDialogState extends State<_LaunchDialog> {
  int _step = 0; // 0 = variant, 1 = student info
  int? _variant;

  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _schoolCtrl = TextEditingController();
  final _groupCtrl = TextEditingController();

  final _firstFocus = FocusNode();
  final _lastFocus = FocusNode();
  final _schoolFocus = FocusNode();
  final _groupFocus = FocusNode();

  String? _err;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _schoolCtrl.dispose();
    _groupCtrl.dispose();
    _firstFocus.dispose();
    _lastFocus.dispose();
    _schoolFocus.dispose();
    _groupFocus.dispose();
    super.dispose();
  }

  void _start() {
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    final school = _schoolCtrl.text.trim();
    final l10n = AppLocalizations.of(context)!;
    if (first.isEmpty || last.isEmpty) {
      setState(() => _err = l10n.enterNameError);
      return;
    }
    if (school.isEmpty) {
      setState(() => _err = l10n.enterSchoolError);
      return;
    }

    context.pop(
      _LaunchArgs(
        variant: _variant!,
        firstName: first,
        lastName: last,
        school: school,
        group: _groupCtrl.text.trim().isEmpty ? null : _groupCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                if (_step == 1)
                  GestureDetector(
                    onTap: () => setState(() {
                      _step = 0;
                      _err = null;
                    }),
                    child: const Icon(Icons.arrow_back_rounded,
                        size: 20, color: AppColors.ink2),
                  )
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _step == 0
                        ? AppLocalizations.of(context)!.selectVariant
                        : AppLocalizations.of(context)!.studentInfoTitle,
                    style: AppTextStyles.titleMedium,
                  ),
                ),
                GestureDetector(
                  onTap: () => context.pop(),
                  child: const Icon(Icons.close_rounded,
                      size: 20, color: AppColors.ink2),
                ),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              widget.entry.title,
              style: AppTextStyles.bodyMedium,
            ),

            const SizedBox(height: 16),

            if (_step == 0) _buildVariantStep() else _buildStudentStep(),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantStep() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.1,
      ),
      itemCount: 15,
      itemBuilder: (_, i) {
        final v = i + 1;
        final selected = _variant == v;
        return GestureDetector(
          onTap: () => setState(() {
            _variant = v;
            _step = 1;
            _err = null;
          }),
          child: Container(
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.muted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$v',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.ink1,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentStep() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_err != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.errorMuted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _err!,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.err),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _lastCtrl,
          focusNode: _lastFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _firstFocus.requestFocus(),
          decoration: InputDecoration(labelText: l10n.lastName),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _firstCtrl,
          focusNode: _firstFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _schoolFocus.requestFocus(),
          decoration: InputDecoration(labelText: l10n.firstName),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _schoolCtrl,
          focusNode: _schoolFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _groupFocus.requestFocus(),
          decoration: InputDecoration(labelText: l10n.schoolCodeOrName),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _groupCtrl,
          focusNode: _groupFocus,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _start(),
          decoration: InputDecoration(labelText: l10n.groupOptional),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _start,
          child: Text('${l10n.variant} $_variant · ${l10n.start}'),
        ),
      ],
    );
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
