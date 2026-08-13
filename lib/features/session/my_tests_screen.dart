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
//
// Dashboard redesign (2026-08): sidebar + profile/KPI card + filter/search
// + status-aware test cards + "recent results" panel. All of the extra data
// (status/score/progress, school name, stats, recent results) comes from
// real backend fields — GET /tests/catalog/ additive keys and the new
// GET /my-profile/ endpoint — never fabricated. If /my-profile/ fails or
// the app is offline, the whole KPI/profile-extras/recent-results UI is
// hidden rather than showing zeros (see _profile == null checks below).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/models/models.dart';
import '../../core/session/logout.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/hover_region.dart';
import '../../shared/widgets/new_badge.dart';
import '../../shared/widgets/student_kpi_tile.dart';
import '../../shared/widgets/student_shell.dart';
import '../../shared/widgets/subject_badge.dart';

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
  final String subject;
  final int? durationMinutes;
  final int? questionCount;
  // Backend-resolved (JWT student.code match) — 'completed'/'in_progress',
  // or null when the backend didn't resolve one (e.g. an older cached
  // catalog payload from before this field existed).
  final String? status;
  final int? score; // only set when status == 'completed'
  final int? progressPct; // only set when status == 'in_progress'

  const _StudentTest({
    required this.testKey,
    required this.title,
    required this.grade,
    this.lockedUntil,
    this.availableUntil,
    this.createdAt,
    this.subject = '',
    this.durationMinutes,
    this.questionCount,
    this.status,
    this.score,
    this.progressPct,
  });

  bool get isLocked =>
      lockedUntil != null && lockedUntil!.isAfter(DateTime.now());

  static const _newThreshold = Duration(days: 3);
  bool get isNew =>
      createdAt != null &&
      DateTime.now().difference(createdAt!) < _newThreshold;

  /// Effective display status: `isLocked` wins first — a teacher can
  /// re-lock a schedule (push `lockedUntil` into the future) after a
  /// student already started/completed the test, and a locked test must
  /// render as locked regardless of prior student activity. Otherwise the
  /// backend-resolved `status` takes priority (real, computed from
  /// MonitoringResult/MonitoringSession); falls back to the existing
  /// date-based "available" default when the backend didn't send one —
  /// keeps offline/cached-catalog behavior unchanged.
  String get displayStatus {
    if (isLocked) return 'locked';
    if (status == 'completed' || status == 'in_progress') return status!;
    return 'available';
  }

  factory _StudentTest.fromJson(Map<String, dynamic> j) => _StudentTest(
        testKey: j['test_key']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        grade: int.tryParse(j['grade']?.toString() ?? '') ?? 0,
        lockedUntil: _tryParse(j['locked_until']),
        availableUntil: _tryParse(j['available_until']),
        createdAt: _tryParse(j['created_at']),
        subject: j['subject']?.toString() ?? '',
        durationMinutes: (j['duration_minutes'] as num?)?.toInt(),
        questionCount: (j['question_count'] as num?)?.toInt(),
        status: (j['status'] is String && (j['status'] as String).isNotEmpty)
            ? j['status'] as String
            : null,
        score: (j['score'] as num?)?.toInt(),
        progressPct: (j['progress_pct'] as num?)?.toInt(),
      );

  static DateTime? _tryParse(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

/// Parsed `GET /my-profile/` response — school name, real stats, recent
/// results. Kept private to this screen (unlike [RecentResult], which is
/// shared with results_screen.dart via core/models/models.dart).
class _ProfileSummary {
  final String schoolName;
  final int? testsCompleted; // null = missing/malformed, NEVER shown as 0
  final int? averageScore; // null = no results yet, NEVER rendered as 0%
  final int? streakDays; // null = missing/malformed, NEVER shown as 0
  final List<RecentResult> recentResults;

  const _ProfileSummary({
    required this.schoolName,
    required this.testsCompleted,
    required this.averageScore,
    required this.streakDays,
    required this.recentResults,
  });

  factory _ProfileSummary.fromJson(Map<String, dynamic> j) {
    final stats = (j['stats'] is Map)
        ? Map<String, dynamic>.from(j['stats'] as Map)
        : <String, dynamic>{};
    return _ProfileSummary(
      schoolName: j['school_name']?.toString() ?? '',
      testsCompleted: (stats['tests_completed'] as num?)?.toInt(),
      averageScore: (stats['average_score'] as num?)?.toInt(),
      streakDays: (stats['streak_days'] as num?)?.toInt(),
      recentResults: RecentResult.listFromJson(j['recent_results']),
    );
  }
}

class MyTestsScreen extends StatefulWidget {
  final StudentSession session;
  final bool offline;

  const MyTestsScreen({super.key, required this.session, this.offline = false});

  @override
  State<MyTestsScreen> createState() => _MyTestsScreenState();
}

/// Status-tab filter values for _FilterAndSearchRow.
enum _StatusFilter { all, inProgress, completed, locked }

class _MyTestsScreenState extends State<MyTestsScreen> {
  bool _loading = true;
  String? _error;
  List<_StudentTest> _tests = [];
  List<String> _subjects =
      []; // distinct, sorted — recomputed only in _loadCatalog
  _ProfileSummary? _profile; // null = fetch failed/offline — UI hides KPIs
  final Set<String> _startingKeys = {};

  String _searchQuery = '';
  String? _subjectFilter; // null = all subjects
  _StatusFilter _statusFilter = _StatusFilter.all;

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
      // fetchTestCatalog/fetchMyProfile both swallow their own errors
      // (return [] / null) — run them in parallel, neither blocks the other.
      final results = await Future.wait([
        api.fetchTestCatalog(authToken: widget.session.token),
        api.fetchMyProfile(authToken: widget.session.token),
      ]);
      if (!mounted) return;
      final raw = results[0] as List<Map<String, dynamic>>;
      final profileRaw = results[1] as Map<String, dynamic>?;
      final entries = raw
          .map(_StudentTest.fromJson)
          .where((t) => t.testKey.isNotEmpty)
          .toList()
        ..sort((a, b) =>
            (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      if (!mounted) return;
      setState(() {
        _tests = entries;
        _subjects = entries.map((t) => t.subject).toSet().toList()..sort();
        // profileRaw == null (offline/401/network fail) → _profile stays
        // null → KPI row, school-name-from-profile, recent-results panel
        // all hide themselves rather than showing 0/blank as if real.
        _profile =
            profileRaw != null ? _ProfileSummary.fromJson(profileRaw) : null;
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
  /// so a self-login session must never survive past its own use. Thin
  /// wrapper over the shared `clearStudentSession()`
  /// (core/session/logout.dart) — kept as a local name since `_startTest`
  /// below needs to clear the session WITHOUT navigating (see its comment).
  Future<void> _clearSession() => clearStudentSession();

  /// Hard-resets to a fresh LoginScreen so back-navigation can never reach
  /// this (now stale) authenticated screen again.
  void _goToLoginReplacingStack() {
    if (!mounted) return;
    goToLoginReplacingStack(context);
  }

  Future<void> _logoutNow() => logoutStudentSession(context);

  /// Starts (or "continues") a test. NOTE — known limitation, documented
  /// honestly per plan: MonitoringSession is a live-proctoring heartbeat
  /// model, not a resumable-answers store. Tapping "Continue" on an
  /// in_progress card re-enters the test from question 1 server-side; any
  /// in-progress answers only survive if the local on-device AttemptStore
  /// (SQLite, engine-side) still has them from the same session on the same
  /// machine. True cross-device/server-side resume is out of scope here.
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

  void _viewResults() {
    context.push('/results', extra: {'session': widget.session});
  }

  List<_StudentTest> get _filteredTests {
    final query = _searchQuery.toLowerCase();
    return _tests.where((t) {
      if (query.isNotEmpty && !t.title.toLowerCase().contains(query)) {
        return false;
      }
      if (_subjectFilter != null && t.subject != _subjectFilter) return false;
      switch (_statusFilter) {
        case _StatusFilter.all:
          return true;
        case _StatusFilter.inProgress:
          return t.displayStatus == 'in_progress';
        case _StatusFilter.completed:
          return t.displayStatus == 'completed';
        case _StatusFilter.locked:
          return t.displayStatus == 'locked';
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSmall = MediaQuery.of(context).size.width < 800;
    return PopScope(
      // A shared kiosk machine must never leave this screen "abandoned" via
      // hardware/gesture back — route every exit through the same
      // clear-session-and-return-to-login path as finishing a test.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _logoutNow();
      },
      child: StudentShell(
        currentRoute: '/my_tests',
        session: widget.session,
        title: l10n.myTestsTitle,
        onLogout: _logoutNow,
        child: _body(l10n, isSmall),
      ),
    );
  }

  Widget _body(AppLocalizations l10n, bool isSmall) {
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

    final filtered = _filteredTests;
    return RefreshIndicator(
      onRefresh: _loadCatalog,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StudentProfileCard(session: widget.session, profile: _profile),
            const SizedBox(height: 20),
            _FilterAndSearchRow(
              subjects: _subjects,
              statusFilter: _statusFilter,
              subjectFilter: _subjectFilter,
              onSearchChanged: (v) => setState(() => _searchQuery = v),
              onStatusChanged: (v) => setState(() => _statusFilter = v),
              onSubjectChanged: (v) => setState(() => _subjectFilter = v),
            ),
            const SizedBox(height: 16),
            if (isSmall) ...[
              _TestCardsGrid(
                tests: filtered,
                totalCount: _tests.length,
                startingKeys: _startingKeys,
                onStart: _startTest,
                onViewResult: (_) => _viewResults(),
              ),
              const SizedBox(height: 20),
              _RecentResultsPanel(profile: _profile, onViewAll: _viewResults),
            ] else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _TestCardsGrid(
                        tests: filtered,
                        totalCount: _tests.length,
                        startingKeys: _startingKeys,
                        onStart: _startTest,
                        onViewResult: (_) => _viewResults(),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 1,
                      child: _RecentResultsPanel(
                          profile: _profile, onViewAll: _viewResults),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Student avatar/name/grade/group + school name (real, from /my-profile/
/// or the login-time `schoolCode` fallback — never a fabricated string) and
/// the 3-stat KPI row. The KPI row is entirely omitted (not zeroed) when
/// [profile] is null — offline or fetch failure, per the "never fabricate
/// data" rule.
class _StudentProfileCard extends StatelessWidget {
  final StudentSession session;
  final _ProfileSummary? profile;

  const _StudentProfileCard({required this.session, required this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final letter = session.studentName.trim().isNotEmpty
        ? session.studentName.trim()[0].toUpperCase()
        : '?';
    final schoolName = (profile != null && profile!.schoolName.isNotEmpty)
        ? profile!.schoolName
        : session.schoolCode;
    final gradeGroup = [
      if (session.grade != null) '${session.grade}-${l10n.gradeShort}',
      if ((session.groupName ?? '').isNotEmpty) session.groupName!,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                    color: AppColors.brand, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text(letter,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.studentName,
                        style: AppTextStyles.titleMedium
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    if (gradeGroup.isNotEmpty || schoolName.isNotEmpty)
                      Text(
                        [gradeGroup, schoolName]
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.ink2),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (profile != null) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: KpiTile(
                    icon: Icons.assignment_turned_in_rounded,
                    iconColor: const Color(0xFF2E7D32),
                    iconBg: const Color(0xFFE8F5E9),
                    label: l10n.kpiTestsCompleted,
                    value: profile!.testsCompleted != null
                        ? '${profile!.testsCompleted}'
                        : '—',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: KpiTile(
                    icon: Icons.star_rounded,
                    iconColor: const Color(0xFFF57F17),
                    iconBg: const Color(0xFFFFF8E1),
                    label: l10n.kpiAverageScore,
                    value: profile!.averageScore != null
                        ? '${profile!.averageScore}%'
                        : '—',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: KpiTile(
                    icon: Icons.local_fire_department_rounded,
                    iconColor: const Color(0xFFE65100),
                    iconBg: const Color(0xFFFBE9E7),
                    label: l10n.kpiStreakDays,
                    value: profile!.streakDays != null
                        ? '${profile!.streakDays}'
                        : '—',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Status tabs + search + subject chips — pure client-side filtering over
/// the already-fetched catalog, no extra endpoint. Subject chips are built
/// dynamically from whatever real `subject` values are present in [tests]
/// (empty subject groups under [AppLocalizations.otherSubject], never
/// hidden).
class _FilterAndSearchRow extends StatelessWidget {
  final List<String> subjects;
  final _StatusFilter statusFilter;
  final String? subjectFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_StatusFilter> onStatusChanged;
  final ValueChanged<String?> onSubjectChanged;

  const _FilterAndSearchRow({
    required this.subjects,
    required this.statusFilter,
    required this.subjectFilter,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onSubjectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: l10n.searchTestsHint,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(context, l10n.filterAll, statusFilter == _StatusFilter.all,
                () => onStatusChanged(_StatusFilter.all)),
            _chip(
                context,
                l10n.filterInProgress,
                statusFilter == _StatusFilter.inProgress,
                () => onStatusChanged(_StatusFilter.inProgress)),
            _chip(
                context,
                l10n.filterCompleted,
                statusFilter == _StatusFilter.completed,
                () => onStatusChanged(_StatusFilter.completed)),
            _chip(
                context,
                l10n.filterLocked,
                statusFilter == _StatusFilter.locked,
                () => onStatusChanged(_StatusFilter.locked)),
          ],
        ),
        if (subjects.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, l10n.allSubjects, subjectFilter == null,
                  () => onSubjectChanged(null)),
              for (final s in subjects)
                _chip(
                  context,
                  s.isEmpty ? l10n.otherSubject : _capitalize(s),
                  subjectFilter == s,
                  () => onSubjectChanged(s),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _chip(
      BuildContext context, String label, bool selected, VoidCallback onTap) {
    return HoverRegion(
      builder: (context, isHovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brand
                : (isHovered ? AppColors.hoverBg : AppColors.chipBg),
            borderRadius: AppRadii.roundedFull,
            border: Border.all(
                color: selected ? AppColors.brand : AppColors.chipBorder),
          ),
          child: Text(label,
              style: AppTextStyles.labelMedium.copyWith(
                  color: selected ? Colors.white : AppColors.ink2,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Responsive card grid — a `Wrap` of fixed-width cards reflows into columns
/// on its own as the available width changes, no manual crossAxisCount math
/// needed.
class _TestCardsGrid extends StatelessWidget {
  final List<_StudentTest> tests;
  final int totalCount;
  final Set<String> startingKeys;
  final ValueChanged<_StudentTest> onStart;
  final ValueChanged<_StudentTest> onViewResult;

  const _TestCardsGrid({
    required this.tests,
    required this.totalCount,
    required this.startingKeys,
    required this.onStart,
    required this.onViewResult,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (tests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            totalCount == 0 ? l10n.myTestsEmpty : l10n.noFilterMatches,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink3),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        for (final test in tests)
          SizedBox(
            width: 320,
            child: _StudentTestCard(
              test: test,
              starting: startingKeys.contains(test.testKey),
              onTap: () => test.displayStatus == 'completed'
                  ? onViewResult(test)
                  : onStart(test),
            ),
          ),
      ],
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

  /// Single switch on `displayStatus` for icon/color/label — adding a 5th
  /// status later only needs one edit site instead of three.
  (IconData, Color, String) _statusVisuals(AppLocalizations l10n) {
    switch (test.displayStatus) {
      case 'locked':
        return (Icons.lock_rounded, AppColors.error, l10n.stillLocked);
      case 'in_progress':
        return (
          Icons.timelapse_rounded,
          AppColors.amber,
          l10n.filterInProgress
        );
      case 'completed':
        return (Icons.check_circle_rounded, AppColors.ok, l10n.filterCompleted);
      default:
        return (Icons.check_circle_rounded, AppColors.ok, l10n.ready);
    }
  }

  Widget? _metaRow(AppLocalizations l10n) {
    final chips = <Widget>[];
    if ((test.questionCount ?? 0) > 0) {
      chips.add(
          _metaChip(Icons.article_outlined, l10n.questionCountLabel(test.questionCount!)));
    }
    if ((test.durationMinutes ?? 0) > 0) {
      chips.add(_metaChip(
          Icons.access_time_rounded, l10n.durationMinutesLabel(test.durationMinutes!)));
    }
    if (test.availableUntil != null) {
      chips.add(_metaChip(Icons.calendar_today_rounded,
          DateFormat('dd.MM.yyyy').format(test.availableUntil!.toLocal())));
    }
    if (chips.isEmpty) return null;
    return Wrap(spacing: 10, runSpacing: 2, children: chips);
  }

  Widget _metaChip(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.ink3),
          const SizedBox(width: 3),
          Text(text, style: AppTextStyles.caption.copyWith(color: AppColors.ink3)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locked = test.displayStatus == 'locked';
    final metaWidget = _metaRow(l10n);
    final (statusIcon, statusColor, statusLabel) = _statusVisuals(l10n);

    return Opacity(
      opacity: locked ? 0.6 : 1,
      child: HoverRegion(
        builder: (context, isHovered) => Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadii.roundedXl,
            onTap: (locked || starting) ? null : onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadii.roundedXl,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      subjectBadge(test.subject),
                      const SizedBox(width: 12),
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
                                Icon(statusIcon, size: 14, color: statusColor),
                                const SizedBox(width: 5),
                                Text(
                                  statusLabel,
                                  style: AppTextStyles.caption.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (test.displayStatus == 'completed' &&
                                    test.score != null) ...[
                                  const SizedBox(width: 6),
                                  Text('· ${test.score}%',
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.ink2,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ],
                            ),
                            if (test.displayStatus == 'in_progress' &&
                                test.progressPct != null) ...[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value:
                                      (test.progressPct!.clamp(0, 100)) / 100,
                                  minHeight: 5,
                                  backgroundColor: AppColors.gray100,
                                  valueColor: const AlwaysStoppedAnimation(
                                      AppColors.amber),
                                ),
                              ),
                            ],
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
                            if (metaWidget != null) ...[
                              const SizedBox(height: 4),
                              metaWidget,
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
                            test.displayStatus == 'completed'
                                ? Icons.bar_chart_rounded
                                : Icons.arrow_forward_rounded,
                            color: isHovered ? Colors.white : AppColors.brand,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
                if (test.isNew && test.displayStatus == 'available')
                  const Positioned(top: -6, right: -6, child: NewBadge()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "So'nggi natijalar" side panel — sourced entirely from
/// `profile.recentResults` (real `GET /my-profile/` data). Hidden entirely
/// when [profile] is null (fetch failed/offline) rather than showing an
/// empty/fake panel.
class _RecentResultsPanel extends StatelessWidget {
  final _ProfileSummary? profile;
  final VoidCallback onViewAll;

  const _RecentResultsPanel({required this.profile, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    if (profile == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final results = profile!.recentResults;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.recentResultsTitle,
              style: AppTextStyles.labelLarge
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(l10n.noResultsYet,
                  style:
                      AppTextStyles.bodyMedium.copyWith(color: AppColors.ink3)),
            )
          else
            for (final r in results.take(5)) _resultRow(r),
          if (results.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onViewAll, child: Text(l10n.viewAllResults)),
          ],
        ],
      ),
    );
  }

  Widget _resultRow(RecentResult r) {
    final dateStr = r.submittedAt != null
        ? DateFormat('dd.MM.yyyy').format(r.submittedAt!.toLocal())
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.ink1, fontWeight: FontWeight.w600)),
                if (dateStr.isNotEmpty)
                  Text(dateStr,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.ink3)),
              ],
            ),
          ),
          Text(r.score != null ? '${r.score}%' : '—',
              style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.success, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
