// lib/features/session/my_tests_screen.dart
//
// Student self-login flow — Step 2: the student is already authenticated
// (StudentSession from LoginScreen's accordion form → api.login()) and sees
// ONLY the tests belonging to their own group, with NO group-selection step
// (unlike the proctor flow in group_select_screen.dart, which is untouched
// and still requires school → group → student picking from a roster).
//
// The backend derives `group_id` server-side from the JWT-authenticated
// student's actual active group whenever an `Authorization: Bearer <token>`
// header is present on /tests/catalog/ and /tests/<key>/ — so this screen
// deliberately never sends `group_id` itself (see api.fetchTestCatalog /
// api.fetchTest `authToken` param in core/api/api_client.dart).
//
// Deliberately does NOT reuse services/test_catalog_service.dart's
// download()/TestCache flow (that's the proctor's offline pre-download
// cache, keyed only by test_key and shared across schools/groups) — this
// screen fetches the full test JSON live, right when the student taps a
// card, and hands it straight to EngineHostScreen (unchanged, per plan).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/db/credential_cache.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/hover_region.dart';
import '../auth/login_screen.dart';

/// Lightweight catalog row for the self-login flow — intentionally separate
/// from services/test_catalog_service.dart's `CatalogEntry` (which tracks
/// download/cache status the proctor flow doesn't need here).
class _StudentTest {
  final String testKey;
  final String title;
  final int grade;
  final DateTime? lockedUntil;
  final DateTime? availableUntil;
  final DateTime? createdAt;

  const _StudentTest({
    required this.testKey,
    required this.title,
    required this.grade,
    this.lockedUntil,
    this.availableUntil,
    this.createdAt,
  });

  bool get isLocked =>
      lockedUntil != null && lockedUntil!.isAfter(DateTime.now());

  static const _newThreshold = Duration(days: 3);
  bool get isNew =>
      createdAt != null &&
      DateTime.now().difference(createdAt!) < _newThreshold;

  factory _StudentTest.fromJson(Map<String, dynamic> j) => _StudentTest(
        testKey: j['test_key']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        grade: int.tryParse(j['grade']?.toString() ?? '') ?? 0,
        lockedUntil: _tryParse(j['locked_until']),
        availableUntil: _tryParse(j['available_until']),
        createdAt: _tryParse(j['created_at']),
      );

  static DateTime? _tryParse(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

class MyTestsScreen extends StatefulWidget {
  final StudentSession session;
  final bool offline;

  const MyTestsScreen({super.key, required this.session, this.offline = false});

  @override
  State<MyTestsScreen> createState() => _MyTestsScreenState();
}

class _MyTestsScreenState extends State<MyTestsScreen> {
  bool _loading = true;
  String? _error;
  List<_StudentTest> _tests = [];
  final Set<String> _startingKeys = {};

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // No groupId/schoolCode — the backend resolves the student's own
      // active group from the Authorization header (see file header).
      final raw = await api.fetchTestCatalog(authToken: widget.session.token);
      final entries = raw
          .map(_StudentTest.fromJson)
          .where((t) => t.testKey.isNotEmpty)
          .toList()
        ..sort((a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      if (!mounted) return;
      setState(() {
        _tests = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context)!.loadFailed;
      });
    }
  }

  int _pickVariant(Map<String, dynamic> data) {
    final blob = (data['test_data'] is Map)
        ? Map<String, dynamic>.from(data['test_data'] as Map)
        : data;
    final variants = blob['variants'];
    if (variants is Map && variants.isNotEmpty) {
      final keys = variants.keys.map((k) => k.toString()).toList()..shuffle();
      return int.tryParse(keys.first) ?? 1;
    }
    return 1;
  }

  /// Mandatory kiosk-security step: this machine is shared between students,
  /// so a self-login session must never survive past its own use. Mirrors
  /// the proven pattern in features/test/package_screen.dart's
  /// _confirmLogout (api.clearToken + CredentialCache.clear).
  Future<void> _clearSession() async {
    api.clearToken();
    await CredentialCache.clear();
  }

  /// Hard-resets to a fresh LoginScreen so back-navigation can never reach
  /// this (now stale) authenticated screen again.
  void _goToLoginReplacingStack() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _logoutNow() async {
    await _clearSession();
    _goToLoginReplacingStack();
  }

  Future<void> _startTest(_StudentTest test) async {
    if (_startingKeys.contains(test.testKey)) return;
    setState(() => _startingKeys.add(test.testKey));

    Map<String, dynamic>? data;
    try {
      data = await api.fetchTest(test.testKey, authToken: widget.session.token);
    } finally {
      if (mounted) setState(() => _startingKeys.remove(test.testKey));
    }

    if (!mounted) return;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.loadFailed)),
      );
      return;
    }

    final variant = _pickVariant(data);
    // StudentSession only exposes a single `studentName` string (no
    // first/last split, no school field — see core/models/models.dart) —
    // best-effort split for EngineHostScreen's firstName/lastName params.
    final nameParts = widget.session.studentName.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    // Clear the session BEFORE launching the test, not only after it
    // returns: EngineHostScreen's result screen (unchanged, per plan) has
    // two exit buttons — "Keyingi o'quvchi" pops normally (resolving the
    // `await push(...)` below), but "Bosh sahifa" calls `context.go('/')`
    // directly, which — per that screen's own comment — replaces the whole
    // go_router stack WITHOUT resolving a pending push().then()/await
    // continuation. Code placed only after `await push(...)` would then
    // never run on that second path. Clearing here instead guarantees the
    // kiosk-security property (no leftover token/credentials for the next
    // student) regardless of which button is tapped. EngineHostScreen never
    // needs the token itself — the proctor flow already proves the entire
    // test-taking + result-submission path works fully unauthenticated.
    await _clearSession();

    if (!mounted) return;
    // Same '/engine_host' route + extra shape the proctor flow already uses
    // (see features/session/runner_dispatch.dart) — EngineHostScreen itself
    // stays unmodified.
    await GoRouter.of(context).push('/engine_host', extra: {
      'testData': data,
      'variant': variant,
      'firstName': firstName,
      'lastName': lastName,
      // StudentSession.schoolCode comes from MonitoringLoginView's
      // 'school_code' response field (School.number, e.g. '26') — see
      // core/models/models.dart. Falls back to '' if the backend omits it.
      'school': widget.session.schoolCode,
      'group': widget.session.groupName,
      'grade': widget.session.grade,
      'studentId': widget.session.studentId,
    });

    // Only reached via the "Keyingi o'quvchi" (pop) exit — the "Bosh
    // sahifa" exit already lands on LoginScreen directly via its own
    // context.go('/') and never returns here.
    _goToLoginReplacingStack();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      // A shared kiosk machine must never leave this screen "abandoned" via
      // hardware/gesture back — route every exit through the same
      // clear-session-and-return-to-login path as finishing a test.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _logoutNow();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              _header(l10n),
              Expanded(child: _body(l10n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.myTestsTitle,
                    style: AppTextStyles.titleLarge
                        .copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  widget.session.studentName,
                  style:
                      AppTextStyles.bodyMedium.copyWith(color: AppColors.ink2),
                ),
              ],
            ),
          ),
          HoverRegion(
            builder: (context, isHovered) => GestureDetector(
              onTap: _logoutNow,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isHovered ? AppColors.hoverBg : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout_rounded,
                        size: 16, color: AppColors.ink2),
                    const SizedBox(width: 6),
                    Text(l10n.logout,
                        style: AppTextStyles.labelMedium
                            .copyWith(color: AppColors.ink1)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_rounded,
                  color: AppColors.error, size: 28),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.error)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadCatalog,
                child: Text(l10n.retryCheck),
              ),
            ],
          ),
        ),
      );
    }
    if (_tests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.myTestsEmpty,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink3)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadCatalog,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          for (final test in _tests)
            _StudentTestCard(
              test: test,
              starting: _startingKeys.contains(test.testKey),
              onTap: () => _startTest(test),
            ),
        ],
      ),
    );
  }
}

/// Card visual adapted from group_select_screen.dart's `_HoverableTestCard`
/// / `_buildTestCard` (that class is private to that file, so it can't be
/// imported directly — this is a from-scratch equivalent, no group_select
/// code was modified).
class _StudentTestCard extends StatelessWidget {
  final _StudentTest test;
  final bool starting;
  final VoidCallback onTap;

  const _StudentTestCard({
    required this.test,
    required this.starting,
    required this.onTap,
  });

  String _timeWindowLabel() {
    final from = DateFormat('HH:mm').format(test.lockedUntil!.toLocal());
    final until = DateFormat('HH:mm').format(test.availableUntil!.toLocal());
    return '$from–$until';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locked = test.isLocked;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: locked ? 0.6 : 1,
        child: HoverRegion(
          builder: (context, isHovered) => Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: (locked || starting) ? null : onTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isHovered && !locked
                            ? AppColors.brand.withValues(alpha: 0.5)
                            : AppColors.border,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                test.title,
                                style: AppTextStyles.labelLarge.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    locked
                                        ? Icons.lock_rounded
                                        : Icons.check_circle_rounded,
                                    size: 14,
                                    color:
                                        locked ? AppColors.error : AppColors.ok,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    locked ? l10n.stillLocked : l10n.ready,
                                    style: AppTextStyles.caption.copyWith(
                                      color: locked
                                          ? AppColors.error
                                          : AppColors.ok,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (locked &&
                                  test.lockedUntil != null &&
                                  test.availableUntil != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _timeWindowLabel(),
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.ink3),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (starting)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (!locked)
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isHovered
                                  ? AppColors.brand
                                  : AppColors.brandLight,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              color: isHovered ? Colors.white : AppColors.brand,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (test.isNew && !locked)
                    const Positioned(top: -6, right: -6, child: _NewBadge()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimal "NEW"/"Yangi" pill — same visual recipe as
/// group_select_screen.dart's private `_NewBadge` (can't be imported, that
/// class is private to that file; recreated here rather than modifying it).
class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        AppLocalizations.of(context)!.newBadge,
        style: AppTextStyles.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 9.5,
        ),
      ),
    );
  }
}
