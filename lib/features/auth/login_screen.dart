// lib/features/auth/login_screen.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/db/credential_cache.dart';
import '../../core/network/connectivity_provider.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/offline/lan_client_session.dart';
import '../../core/offline/offline_session.dart';
import '../../core/services/heartbeat_service.dart';
import '../../core/services/test_catalog_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/button_shape.dart';
import '../../shared/widgets/hover_region.dart';
import '../../shared/widgets/signal_strength_indicator.dart';

import '../local_test/sync_images_button.dart';
import '../offline/offline_control_center_dialog.dart';
import '../../core/offline/offline_errors.dart';

import '../../core/services/update_service.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../shared/widgets/language_switcher.dart';
import '../../shared/widgets/pending_results_chip.dart';
import '../../shared/widgets/update_progress_dialog.dart';
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
    // The first warm-up frame can tick before the first layout: `context.size`
    // would throw "RenderBox was not laid out".
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final size = box.size;
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
  bool _submitAttempted = false;
  // ponytail: tarjima matni state'da saqlanmaydi — checking/online/offline
  // holati saqlanadi, matn build vaqtida l10n orqali hisoblanadi (til
  // almashganda ham to'g'ri ko'rinishi uchun).
  String? _error;
  int _selectedTab = 0;

  /// Tab dictated by the open USB pack: 1 = diagnostic-only pack, 0 =
  /// monitoring-only pack, null = no pack (or a mixed/empty one: user's
  /// choice stays free).
  int? get _packTab {
    final s = OfflinePackSession.current;
    if (s == null) return null;
    return s.isDiagnosticOnly ? 1 : (s.isMonitoringOnly ? 0 : null);
  }

  // Only a pack being opened/closed moves the tab — never a plain rebuild.
  void _onPackChanged() {
    final t = _packTab;
    if (t != null && mounted && t != _selectedTab) {
      setState(() => _selectedTab = t);
    }
  }

  late final AnimationController _entranceController;
  late final Animation<double> _entranceOpacity;
  late final Animation<double> _entranceScale;
  late final AnimationController _pulseController;

  // ── Test katalog banner holati ─────────────────────────────────────────────
  List<CatalogEntry> _catalogEntries = [];

  // ── Yangilanish badge holati ────────────────────────────────────────────────
  // Progress endi UpdateProgressDialog o'z ichida boshqaradi (Task 4) — bu
  // yerda faqat _updateInfo != null ekanligi badge'ni ko'rsatish uchun kifoya.
  UpdateInfo? _updateInfo;
  // Fast double-tap guard: dialog opening is async, so without this a
  // second tap before the first frame commits could stack two dialogs both
  // downloading to the same save path concurrently.
  bool _updateDialogOpen = false;

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
    _selectedTab = _packTab ?? _selectedTab;
    OfflinePackSession.notifier.addListener(_onPackChanged);

    // All startup I/O is deliberately fire-and-forget. The complete login
    // card is already in the first frame; ping, catalog and update state
    // hydrate it in the background without gating the UI.
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetStudentIdentity());
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
    OfflinePackSession.notifier.removeListener(_onPackChanged);
    UpdateService.instance.stopPeriodicRecheck();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// The login screen is where a shared kiosk sits between students: nothing
  /// of the previous student's session may survive into the next login (a
  /// stale token or identity would be sent with the next student's results).
  /// In-memory identity only - the credential cache is NOT touched, it is what
  /// lets an earlier student sign in again while offline.
  ///
  /// The form is deliberately NOT pre-filled from that cache any more: there
  /// is no "remember me" choice, so pressing Login on a pre-filled form signed
  /// the next child in as the previous one.
  void _resetStudentIdentity() {
    if (!mounted) return;
    api.clearToken();
    HeartbeatService.instance.clearStudentContext();
    ProviderScope.containerOf(context)
        .read(currentStudentSessionProvider.notifier)
        .state = null;
  }

  Future<bool> _checkOnline() async {
    return checkOnlineWithRetry(() => api.ping());
  }

  Future<void> _login() async {
    final valid = _formKey.currentState!.validate();
    setState(() => _submitAttempted = true);
    if (!valid) return;
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
          HeartbeatService.instance.setStudentContext(
            schoolCode: session.schoolCode,
            name: session.studentName,
            studentCode: session.studentId,
          );
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
          final offlineMsg = localizeOfflineError(l10n, e);
          if (offlineMsg != null) {
            setState(() => _error = offlineMsg);
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
        HeartbeatService.instance.setStudentContext(
          schoolCode: session.schoolCode,
          name: session.studentName,
          studentCode: session.studentId,
        );
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
                            if (_updateInfo != null) ...[
                              _updateBadge(
                                palette,
                                compact: viewportWidth < 720,
                              ),
                              const SizedBox(width: 8),
                            ],
                            _languageCapsule(palette),
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
              // Teacher chip: results still only on this PC (hidden at 0).
              const Positioned(
                bottom: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: PendingResultsChip(),
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

  // 48 = DropdownButton's own height, so its hover/focus InkWell fills the
  // capsule exactly. The inner transparent Material keeps the ink above the
  // capsule fill; clipBehavior trims it to the capsule's rounded border.
  Widget _languageCapsule(_LoginPalette palette) => Container(
        height: kMinInteractiveDimension,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(kControlRadius),
          border: Border.all(color: palette.border),
          boxShadow: _floatingControlShadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: LanguageSwitcher(
              foregroundColor: palette.ink1,
              iconColor: palette.ink2,
              dropdownColor: palette.surface,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
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
    // A diagnostic-only USB pack has no monitoring tests: the catalog would
    // only lead to empty group screens.
    final blocked = _packTab == 1;
    final hasNew = downloadable > 0;

    return Semantics(
      button: true,
      enabled: !blocked,
      label: l10n.schools,
      child: Opacity(
        opacity: blocked ? .58 : 1,
        child: HoverRegion(
        builder: (context, isHovered) => GestureDetector(
          key: const ValueKey('login-schools-button'),
          onTap: blocked ? null : _showCatalogSheet,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: hasNew
                  ? (isHovered ? palette.brandMuted : palette.surface)
                  : (isHovered ? palette.hover : palette.surface),
              borderRadius: BorderRadius.circular(kControlRadius),
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
      ),
    );
  }

  void _showCatalogSheet() {
    context.push('/school_select').then((_) => _loadCatalog());
  }

  Widget _updateBadge(_LoginPalette palette, {bool compact = false}) {
    if (_updateInfo == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: l10n.newVersionAvailable,
      child: HoverRegion(
        builder: (context, isHovered) => GestureDetector(
          onTap: () async {
            if (_updateDialogOpen) return;
            _updateDialogOpen = true;
            await showUpdateProgressDialog(context, _updateInfo!);
            if (mounted) _updateDialogOpen = false;
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isHovered ? palette.brandMuted : palette.surface,
              borderRadius: BorderRadius.circular(kControlRadius),
              border: Border.all(color: palette.border),
              boxShadow: _floatingControlShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update_alt_rounded,
                  size: 16,
                  color: AppColors.brand,
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    l10n.newVersionAvailable,
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
              _buildOfflineSessionBanner(palette),
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
                    : _buildDiagnosticPanel(palette),
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

  /// Shown only while a pack / LAN-client session has swapped the global
  /// `api`: the normal login form cannot work in that state, so say so and
  /// offer the one-tap way out. Never auto-exits (a student may be mid-exam).
  Widget _buildOfflineSessionBanner(_LoginPalette palette) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: Listenable.merge(
          [OfflinePackSession.notifier, LanClientSession.notifier]),
      builder: (context, _) {
        if (!isOfflineModeOpen) return const SizedBox.shrink();
        return Consumer(
          builder: (context, ref, _) {
            final signal = ref.watch(signalProvider);
            // "Internet is up" is only meaningful for a USB pack; on a LAN
            // client the chip measures the hub link.
            final serverUp = OfflinePackSession.isActive &&
                !signal.checking &&
                signal.tier != SignalTier.none;
            return Padding(
              key: const ValueKey('offline-session-banner'),
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(13),
                  border:
                      Border.all(color: AppColors.brand.withValues(alpha: .35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.offlineSessionBannerTitle,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium.copyWith(
                            color: palette.ink1, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        serverUp
                            ? l10n.offlineSessionBannerOnlineHint
                            : l10n.offlineSessionBannerHint,
                        key: const ValueKey('offline-session-banner-hint'),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption
                            .copyWith(color: palette.ink2)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('offline-session-banner-exit'),
                      onPressed: () {
                        exitOfflineMode();
                        // Re-probe now instead of waiting for the next tick.
                        ref.read(signalProvider.notifier).refresh();
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(l10n.usbExitMode),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
    final packTab = _packTab;
    return Container(
      height: 54,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.segmentTrack,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        alignment: Alignment.center,
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
                  borderRadius: BorderRadius.circular(kChipRadius),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _routeButton(
                  key: const ValueKey('login-tab-student'),
                  icon: Icons.desktop_windows_rounded,
                  label: l10n.studentLoginButton,
                  active: _selectedTab == 0,
                  palette: palette,
                  disabled: packTab == 1,
                  onTap: () => setState(() => _selectedTab = 0),
                ),
              ),
              Expanded(
                child: _routeButton(
                  key: const ValueKey('login-tab-diagnostic'),
                  icon: Icons.task_alt_rounded,
                  label: l10n.diagnosticTabLabel,
                  active: _selectedTab == 1,
                  palette: palette,
                  disabled: packTab == 0,
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
        // Transparent Material so the ink paints above the track/indicator
        // fills, clipped to the same radius as the indicator.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: key,
            onTap: disabled ? null : onTap,
            borderRadius: BorderRadius.circular(kChipRadius),
            hoverColor: active ? Colors.white.withValues(alpha: .10) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: foreground),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: foreground,
                        fontSize: 11.5,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5C28E),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badge,
                        style: AppTextStyles.caption.copyWith(
                          color: const Color(0xFF7C3F0A),
                          fontSize: 8.5,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
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
                            borderRadius:
                                BorderRadius.circular(kControlRadius)),
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
                            borderRadius:
                                BorderRadius.circular(kControlRadius)),
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
              borderRadius: BorderRadius.circular(kControlRadius),
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
                borderRadius: BorderRadius.circular(kControlRadius),
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

  Widget _buildDiagnosticPanel(_LoginPalette palette) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      key: const ValueKey('diagnostic-panel'),
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
              Icons.task_alt_rounded,
              color: AppColors.flame,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.diagnosticLoginTab,
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium.copyWith(
              color: palette.ink1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.diagnosticSelectSchoolPrompt,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: palette.ink2),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/diagnostic_school_select'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.flame,
                backgroundColor: palette.fieldFill,
                side: const BorderSide(color: AppColors.flame, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kControlRadius),
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

  // ignore: unused_element
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
                  borderRadius: BorderRadius.circular(kControlRadius),
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
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: BottomChip(
              fill: palette.fieldFill,
              border: palette.border,
              minHeight: 42,
              child: const SyncImagesButton(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: BottomChip(
              fill: palette.fieldFill,
              border: palette.border,
              height: 42,
              child: TextButton.icon(
                onPressed: () => context.push('/history', extra: {}),
                style: bottomChipButtonStyle(foreground: palette.ink2),
                icon: const Icon(Icons.history_rounded, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(l10n.offlineHistory),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: BottomChip(
              fill: palette.fieldFill,
              border: palette.border,
              height: 42,
              child: TextButton.icon(
                onPressed: () => showOfflineControlCenter(context),
                style: bottomChipButtonStyle(foreground: palette.ink2),
                icon: const Icon(Icons.usb_rounded, size: 16),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(l10n.usbOfflineButton),
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
        animation: Listenable.merge([focusNode, controller]),
        builder: (context, child) {
          // hasError is derived live from the controller instead of a
          // separate error flag so the outer frame and the field's actual
          // emptiness never disagree — it's the single border painter for
          // this field (see errorBorder/focusedErrorBorder below, which are
          // deliberately BorderSide.none to avoid a second, misaligned
          // border stacking on top of this one after a failed submit).
          final hasError = _submitAttempted && controller.text.trim().isEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: palette.fieldFill,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasError
                    ? AppColors.err
                    : (focusNode.hasFocus ? AppColors.flame : palette.border),
                width: hasError || focusNode.hasFocus ? 1.5 : 1,
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
          );
        },
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
            hintText: hint.isEmpty ? label : hint,
            floatingLabelBehavior: FloatingLabelBehavior.never,
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
            // The outer AnimatedContainer above is the single border painter
            // for this field (including the red error state) — these two
            // stay BorderSide.none like the others so TextFormField never
            // draws a second, misaligned border on top of it.
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
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
