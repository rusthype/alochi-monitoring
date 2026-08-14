// lib/features/session/student_certificates_screen.dart
//
// "Сертификаты и достижения" — self-login student cabinet screen, mockup:
// /Users/max/.gemini/antigravity-cli/brain/d4e52b23-4089-4731-b0f9-b3d97e1e20f0/mock4.jpg
//
// Wired into app_router.dart as the live `/certificates` route.
//
// REAL-DATA-ONLY (project rule — never fabricate): this app has no backend
// certificate/achievement model, so every badge/certificate here is a
// client-side computation over the same `GET /my-profile/` payload
// my_tests_screen.dart's `_ProfileSummary` and results_screen.dart already
// use (`RecentResult` list + `stats`). Loading/data-source pattern (fetch,
// null=failed vs empty=no-data, session clear on logout) is copied from
// results_screen.dart, the closest sibling screen on the same data source.
//
// Known real-data limitation (inherited, not introduced here): the backend
// caps `recent_results` at 10 items (see results_screen.dart's file header)
// — a student with more than 10 historical results may have older
// certificates/badge-qualifying attempts not reflected here. Fixing that
// needs a new paginated endpoint, out of scope for this screen.
//
// Localized via AppLocalizations/ARB (app_uz.arb / app_ru.arb) — same
// pattern as results_screen.dart/settings_screen.dart, now that this screen
// is wired into a live sidebar route (/certificates).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/student_palette.dart';
import '../../shared/widgets/student_kpi_tile.dart';

/// Badge thresholds — documented here so they can be reviewed/adjusted in
/// one place. All computed from real `RecentResult`/`stats` data, never
/// invented per-badge numbers.
class _BadgeThresholds {
  /// Math/English "mastery" badges: symmetric 90% bar for both subjects.
  static const int mastery = 90;

  /// Streak badge unlocks once the student has a real 3+ day streak (same
  /// `streak_days` field `_ProfileSummary`/`fetchMyProfile` already expose).
  static const int streakDays = 3;

  /// "Будущий чемпион" (future champion) badge: 10 completed tests.
  static const int futureChampionTests = 10;

  /// "Супер серия" (super streak) badge: 30-day streak.
  static const int superStreakDays = 30;

  /// Certificate minimum score — reuses the SAME threshold the app already
  /// treats as "passed" (`TestResult.passed => totalPct >= 60` in
  /// core/models/models.dart), instead of picking a new arbitrary number.
  static const int certificateMinScore = 60;

  /// "Только новые" filter: certificates issued within the last N days.
  static const int newCertificateDays = 7;
}

class _Badge {
  final String title;
  final IconData icon;
  final Color color;
  final bool unlocked;
  final String? unlockedValueLabel; // shown only when unlocked
  final double progress; // 0..1, shown only when locked
  final String? progressLeftLabel; // e.g. "7/10 тестов", shown only when locked
  const _Badge({
    required this.title,
    required this.icon,
    required this.color,
    required this.unlocked,
    this.unlockedValueLabel,
    this.progress = 0,
    this.progressLeftLabel,
  });
}

class StudentCertificatesScreen extends StatefulWidget {
  final StudentSession session;

  const StudentCertificatesScreen({super.key, required this.session});

  @override
  State<StudentCertificatesScreen> createState() =>
      _StudentCertificatesScreenState();
}

class _StudentCertificatesScreenState
    extends State<StudentCertificatesScreen> {
  bool _loading = true;
  List<RecentResult>? _results; // null = fetch failed/offline, never faked
  int? _streakDays;
  int? _testsCompleted;

  String _searchQuery = '';
  int _sectionFilter = 0; // 0=all, 1=certificates only, 2=badges only
  bool _onlyNew = false; // real: submittedAt within _BadgeThresholds.newCertificateDays
  bool _sortNewestFirst = true;

  // Identity-keyed (not RecentResult.testKey, which defaults to '' and can
  // collide across multiple results missing that field — see finding #4).
  // RecentResult doesn't override ==/hashCode, so Set membership here is
  // already reference-identity, which is genuinely unique per card.
  RecentResult? _generatingCertFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile =
          await api.fetchMyProfile(authToken: widget.session.token);
      if (!mounted) return;
      if (profile == null) {
        setState(() {
          _results = null;
          _loading = false;
        });
        return;
      }
      final stats = (profile['stats'] is Map)
          ? Map<String, dynamic>.from(profile['stats'] as Map)
          : <String, dynamic>{};
      setState(() {
        _results = RecentResult.listFromJson(profile['recent_results']);
        _streakDays = (stats['streak_days'] as num?)?.toInt();
        _testsCompleted = (stats['tests_completed'] as num?)?.toInt();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _body(l10n);
  }

  Widget _body(AppLocalizations l10n) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, color: pal.ink3, size: 28),
              const SizedBox(height: 12),
              Text(l10n.loadFailed,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(color: pal.ink2)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: Text(l10n.retryCheck)),
            ],
          ),
        ),
      );
    }

    final results = _results!;
    final bestScore = results.isEmpty
        ? 0
        : results.map((r) => r.score ?? 0).reduce(math.max);
    final certificates = results
        .where((r) =>
            r.score != null && r.score! >= _BadgeThresholds.certificateMinScore)
        .toList()
      ..sort((a, b) => _sortNewestFirst
          ? (b.submittedAt ?? DateTime(0)).compareTo(a.submittedAt ?? DateTime(0))
          : (a.submittedAt ?? DateTime(0)).compareTo(b.submittedAt ?? DateTime(0)));

    final badges = _computeBadges(l10n, results, bestScore);
    final unlockedCount = badges.where((b) => b.unlocked).length;

    final now = DateTime.now();
    final filteredCertificates = certificates.where((c) {
      if (_searchQuery.isNotEmpty &&
          !c.title.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_onlyNew) {
        final d = c.submittedAt;
        if (d == null ||
            now.difference(d).inDays > _BadgeThresholds.newCertificateDays) {
          return false;
        }
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroBanner(
              l10n: l10n,
              certificatesCount: certificates.length,
              unlockedBadges: unlockedCount,
              totalBadges: badges.length,
              bestScore: bestScore,
            ),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, c) {
              final narrow = c.maxWidth < 900;
              final badgeSection = _BadgeGrid(l10n: l10n, badges: badges);
              final progressPanel = _ProgressPanel(
                l10n: l10n,
                results: results,
                badges: badges,
                testsCompleted: _testsCompleted ?? results.length,
              );
              // Symmetric with the certificates section's `!= 2` gate below:
              // filter==1 ("Сертификаты" only) must hide badges/progress,
              // exactly as filter==2 ("Бейджи" only) hides certificates.
              if (_sectionFilter == 1) return const SizedBox.shrink();
              if (narrow) {
                return Column(children: [
                  badgeSection,
                  const SizedBox(height: 16),
                  progressPanel,
                ]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: badgeSection),
                  const SizedBox(width: 16),
                  Expanded(child: progressPanel),
                ],
              );
            }),
            const SizedBox(height: 20),
            _SearchAndFilterRow(
              l10n: l10n,
              query: _searchQuery,
              filter: _sectionFilter,
              onlyNew: _onlyNew,
              sortNewestFirst: _sortNewestFirst,
              onQueryChanged: (v) => setState(() => _searchQuery = v),
              onFilterChanged: (v) => setState(() => _sectionFilter = v),
              onOnlyNewChanged: () => setState(() => _onlyNew = !_onlyNew),
              onSortChanged: (v) => setState(() => _sortNewestFirst = v),
            ),
            const SizedBox(height: 20),
            if (_sectionFilter != 2) ...[
              Text(l10n.sidebarCertificates,
                  style: AppTextStyles.titleMedium
                      .copyWith(fontWeight: FontWeight.w800, color: pal.ink1)),
              const SizedBox(height: 12),
              if (filteredCertificates.isEmpty)
                _EmptyCertificates(
                    l10n: l10n, hasQuery: _searchQuery.isNotEmpty)
              else
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: filteredCertificates
                      .map((c) => _CertificateCard(
                            l10n: l10n,
                            session: widget.session,
                            result: c,
                            generating: identical(_generatingCertFor, c),
                            onDownload: () => _downloadCertificate(c),
                          ))
                      .toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<_Badge> _computeBadges(
      AppLocalizations l10n, List<RecentResult> results, int bestScore) {
    double bestFor(bool Function(String subject) match) {
      final scores = results
          .where((r) => match(r.subject.toLowerCase()) && r.score != null)
          .map((r) => r.score!.toDouble());
      return scores.isEmpty ? 0 : scores.reduce(math.max);
    }

    final mathBest = bestFor((s) => s == 'math');
    final engBest = bestFor((s) => s == 'english');
    final streak = _streakDays ?? 0;
    final testsDone = _testsCompleted ?? results.length;

    return [
      _Badge(
        title: l10n.badgeMathMasterTitle,
        icon: Icons.calculate_rounded,
        color: AppColors.math,
        unlocked: mathBest >= _BadgeThresholds.mastery,
        unlockedValueLabel: l10n.badgeUnlockedLabel,
        progress: (mathBest / _BadgeThresholds.mastery).clamp(0, 1),
      ),
      _Badge(
        title: l10n.badgePerfectScoreTitle,
        icon: Icons.star_rounded,
        color: AppColors.gold,
        unlocked: bestScore >= 100,
        unlockedValueLabel: l10n.badgeUnlockedLabel,
        progress: (bestScore / 100).clamp(0, 1),
      ),
      _Badge(
        title: streak > 0
            ? l10n.badgeStreakCount(streak)
            : l10n.kpiStreakDays,
        icon: Icons.local_fire_department_rounded,
        color: AppColors.flame,
        unlocked: streak >= _BadgeThresholds.streakDays,
        unlockedValueLabel: l10n.badgeUnlockedLabel,
        progress: (streak / _BadgeThresholds.streakDays).clamp(0, 1),
      ),
      _Badge(
        title: l10n.badgeEnglishMasterTitle,
        icon: Icons.school_rounded,
        color: AppColors.eng,
        unlocked: engBest >= _BadgeThresholds.mastery,
        unlockedValueLabel: l10n.badgeUnlockedLabel,
        progress: (engBest / _BadgeThresholds.mastery).clamp(0, 1),
      ),
      _Badge(
        title: l10n.badgeFutureChampionTitle,
        icon: Icons.emoji_events_rounded,
        color: AppColors.violet,
        unlocked: testsDone >= _BadgeThresholds.futureChampionTests,
        unlockedValueLabel: l10n.badgeUnlockedLabel,
        progress: (testsDone / _BadgeThresholds.futureChampionTests).clamp(0, 1),
        progressLeftLabel: l10n.badgeTestsProgressLabel(
            testsDone.clamp(0, _BadgeThresholds.futureChampionTests),
            _BadgeThresholds.futureChampionTests),
      ),
      _Badge(
        title: l10n.badgeSuperStreakTitle(_BadgeThresholds.superStreakDays),
        icon: Icons.calendar_month_rounded,
        color: AppColors.blue,
        unlocked: streak >= _BadgeThresholds.superStreakDays,
        unlockedValueLabel: l10n.badgeUnlockedLabel,
        progress: (streak / _BadgeThresholds.superStreakDays).clamp(0, 1),
      ),
    ];
  }

  Future<void> _downloadCertificate(RecentResult result) async {
    if (identical(_generatingCertFor, result)) return;
    setState(() => _generatingCertFor = result);
    final l10n = AppLocalizations.of(context)!;
    try {
      final file = await _DiplomaPdf.generate(
        session: widget.session,
        result: result,
        l10n: l10n,
      );
      if (!mounted) return;
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.pdfError(e.toString())),
        backgroundColor: AppColors.err,
      ));
    } finally {
      if (mounted) setState(() => _generatingCertFor = null);
    }
  }
}

class _HeroBanner extends StatelessWidget {
  final AppLocalizations l10n;
  final int certificatesCount;
  final int unlockedBadges;
  final int totalBadges;
  final int bestScore;

  const _HeroBanner({
    required this.l10n,
    required this.certificatesCount,
    required this.unlockedBadges,
    required this.totalBadges,
    required this.bestScore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.secondary, AppColors.amberDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadii.roundedXl,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.certificatesHeroTitle,
                    style: AppTextStyles.titleLarge.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(l10n.certificatesHeroSubtitle,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: Colors.white.withValues(alpha: 0.9))),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 200,
                      child: KpiTile(
                        icon: Icons.workspace_premium_rounded,
                        iconColor: AppColors.secondary,
                        iconBg: AppColors.secondaryMuted,
                        label: l10n.certificatesKpiCountLabel,
                        value: '$certificatesCount',
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: KpiTile(
                        icon: Icons.military_tech_rounded,
                        iconColor: AppColors.violet,
                        iconBg: AppColors.violetMuted,
                        label: l10n.certificatesKpiBadgesLabel,
                        value: '$unlockedBadges/$totalBadges',
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: KpiTile(
                        icon: Icons.trending_up_rounded,
                        iconColor: AppColors.success,
                        iconBg: AppColors.successMuted,
                        label: l10n.kpiBestScore,
                        value: '$bestScore%',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.emoji_events_rounded,
              size: 72, color: Colors.white70),
        ],
      ),
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  final AppLocalizations l10n;
  final List<_Badge> badges;
  const _BadgeGrid({required this.l10n, required this.badges});

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.badgesAndAchievementsTitle,
              style: AppTextStyles.titleMedium
                  .copyWith(fontWeight: FontWeight.w800, color: pal.ink1)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: badges.map((b) => _BadgeTile(badge: b)).toList(),
          ),
        ],
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final _Badge badge;
  const _BadgeTile({required this.badge});

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final color = badge.unlocked ? badge.color : pal.ink3;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.chipBg,
        borderRadius: AppRadii.roundedLg,
        border: Border.all(color: pal.border),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: badge.unlocked ? color.withValues(alpha: 0.14) : pal.chipBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(badge.icon, color: color, size: 26),
          ),
          const SizedBox(height: 10),
          Text(badge.title,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelMedium
                  .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
          const SizedBox(height: 8),
          if (badge.unlocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: const BoxDecoration(
                color: AppColors.successMuted,
                borderRadius: AppRadii.roundedFull,
              ),
              child: Text(badge.unlockedValueLabel!,
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.success, fontWeight: FontWeight.w700)),
            )
          else ...[
            ClipRRect(
              borderRadius: AppRadii.roundedFull,
              child: LinearProgressIndicator(
                value: badge.progress,
                minHeight: 6,
                backgroundColor: pal.chipBg,
                valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (badge.progressLeftLabel != null)
                  Text(badge.progressLeftLabel!,
                      style: AppTextStyles.caption.copyWith(color: pal.ink3)),
                Text('${(badge.progress * 100).round()}%',
                    style: AppTextStyles.caption.copyWith(color: pal.ink3)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Real per-subject average (only subjects that actually have results —
/// never an invented "Активность" bar with no backing data) + a pointer to
/// the locked badge closest to unlocking (real progress fraction, not a
/// guessed "N tests left" count).
class _ProgressPanel extends StatelessWidget {
  final AppLocalizations l10n;
  final List<RecentResult> results;
  final List<_Badge> badges;
  final int testsCompleted;
  const _ProgressPanel({
    required this.l10n,
    required this.results,
    required this.badges,
    required this.testsCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final bySubject = <String, List<int>>{};
    for (final r in results) {
      if (r.score == null) continue;
      final key = r.subject.toLowerCase();
      if (key.isEmpty) continue;
      bySubject.putIfAbsent(key, () => []).add(r.score!);
    }
    final subjectAverages = bySubject.entries
        .map((e) => MapEntry(
            e.key, e.value.reduce((a, b) => a + b) / e.value.length))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final locked = badges.where((b) => !b.unlocked).toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));

    // Real derived metric (not fabricated): same testsCompleted/threshold
    // ratio the "Будущий чемпион" badge uses, surfaced here as an overall
    // "Активность" bar.
    final activityPct =
        (testsCompleted / _BadgeThresholds.futureChampionTests * 100)
            .clamp(0, 100)
            .round();

    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.progressPanelTitle,
              style: AppTextStyles.titleMedium
                  .copyWith(fontWeight: FontWeight.w800, color: pal.ink1)),
          const SizedBox(height: 14),
          if (subjectAverages.isEmpty)
            Text(l10n.progressNoSubjectData,
                style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3))
          else
            ...subjectAverages.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SubjectProgressRow(
                      l10n: l10n, subject: e.key, avgPct: e.value.round()),
                )),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _SubjectProgressRow(
                l10n: l10n, subject: 'activity', avgPct: activityPct),
          ),
          if (locked.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.warnMuted,
                borderRadius: AppRadii.roundedMd,
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded,
                      color: AppColors.amberDark, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        l10n.progressClosestBadge(locked.first.title,
                            (locked.first.progress * 100).round()),
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.amberInk)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubjectProgressRow extends StatelessWidget {
  final AppLocalizations l10n;
  final String subject;
  final int avgPct;
  const _SubjectProgressRow(
      {required this.l10n, required this.subject, required this.avgPct});

  String get _label {
    if (subject == 'math') return l10n.mathSubjectFull;
    if (subject == 'english') return l10n.englishSubjectFull;
    if (subject == 'activity') return l10n.progressActivityLabel;
    if (subject.isEmpty) return l10n.otherSubject;
    return subject;
  }

  Color get _color {
    if (subject == 'math') return AppColors.math;
    if (subject == 'english') return AppColors.eng;
    if (subject == 'activity') return AppColors.blue;
    return AppColors.violet;
  }

  IconData get _icon {
    if (subject == 'math') return Icons.calculate_rounded;
    if (subject == 'english') return Icons.school_rounded;
    if (subject == 'activity') return Icons.bolt_rounded;
    return Icons.book_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.14),
                borderRadius: AppRadii.roundedSm,
              ),
              alignment: Alignment.center,
              child: Icon(_icon, color: _color, size: 13),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_label,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: pal.ink1))),
            Text('$avgPct%',
                style: AppTextStyles.labelMedium
                    .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: AppRadii.roundedFull,
          child: LinearProgressIndicator(
            value: (avgPct / 100).clamp(0, 1),
            minHeight: 6,
            backgroundColor: pal.chipBg,
            valueColor: AlwaysStoppedAnimation(_color),
          ),
        ),
      ],
    );
  }
}

class _SearchAndFilterRow extends StatelessWidget {
  final AppLocalizations l10n;
  final String query;
  final int filter;
  final bool onlyNew;
  final bool sortNewestFirst;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<int> onFilterChanged;
  final VoidCallback onOnlyNewChanged;
  final ValueChanged<bool> onSortChanged;

  const _SearchAndFilterRow({
    required this.l10n,
    required this.query,
    required this.filter,
    required this.onlyNew,
    required this.sortNewestFirst,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onOnlyNewChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: l10n.certificatesSearchHint,
            ),
          ),
        ),
        _FilterChip(
            icon: Icons.grid_view_rounded,
            label: l10n.filterAll,
            selected: filter == 0,
            onTap: () => onFilterChanged(0)),
        _FilterChip(
            icon: Icons.workspace_premium_rounded,
            label: l10n.sidebarCertificates,
            selected: filter == 1,
            onTap: () => onFilterChanged(1)),
        _FilterChip(
            icon: Icons.military_tech_rounded,
            label: l10n.filterBadgesLabel,
            selected: filter == 2,
            onTap: () => onFilterChanged(2)),
        _FilterChip(
            icon: Icons.fiber_new_rounded,
            label: l10n.filterOnlyNewLabel,
            selected: onlyNew,
            onTap: onOnlyNewChanged),
        GestureDetector(
          onTap: () => onSortChanged(!sortNewestFirst),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: AppRadii.roundedMd,
              border: Border.all(color: pal.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_vert_rounded, size: 16, color: pal.ink2),
                const SizedBox(width: 6),
                Text(
                    sortNewestFirst
                        ? l10n.sortNewestFirstLabel
                        : l10n.sortOldestFirstLabel,
                    style: AppTextStyles.labelMedium.copyWith(
                        color: pal.ink2, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.secondary : pal.surface,
          borderRadius: AppRadii.roundedMd,
          border: Border.all(
              color: selected ? AppColors.secondary : pal.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16, color: selected ? Colors.white : pal.ink2),
            const SizedBox(width: 6),
            Text(label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: selected ? Colors.white : pal.ink2,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }
}

class _EmptyCertificates extends StatelessWidget {
  final AppLocalizations l10n;
  final bool hasQuery;
  const _EmptyCertificates({required this.l10n, required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: pal.border),
      ),
      child: Column(
        children: [
          Icon(Icons.workspace_premium_outlined, color: pal.ink3, size: 32),
          const SizedBox(height: 12),
          Text(
              hasQuery
                  ? l10n.helpFaqNoResults
                  : l10n.certificatesEmptyPrompt(
                      _BadgeThresholds.certificateMinScore),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3)),
        ],
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  final AppLocalizations l10n;
  final StudentSession session;
  final RecentResult result;
  final bool generating;
  final VoidCallback onDownload;

  const _CertificateCard({
    required this.l10n,
    required this.session,
    required this.result,
    required this.generating,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final dateStr = result.submittedAt != null
        ? DateFormat('dd.MM.yyyy').format(result.submittedAt!.toLocal())
        : '';
    return Container(
      width: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: pal.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DiplomaThumbnail(l10n: l10n, subject: result.subject),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge
                        .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
                if (dateStr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(l10n.certificateIssuedOn(dateStr),
                      style: AppTextStyles.caption
                          .copyWith(color: pal.ink3)),
                ],
                const SizedBox(height: 6),
                Text('${result.score}/100',
                    style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.success, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: generating ? null : onDownload,
                    icon: generating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_rounded, size: 16),
                    label: Text(
                        generating
                            ? l10n.certificateGeneratingLabel
                            : l10n.downloadPdfButton,
                        style: AppTextStyles.labelMedium
                            .copyWith(color: pal.ink2)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: BorderSide(color: pal.border),
                    ),
                  ),
                ),
                // ponytail: "Поделиться" omitted — share_plus isn't a
                // pubspec dependency and adding one for a nice-to-have
                // share button isn't justified here; add if/when the app
                // takes on share_plus for another feature.
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiplomaThumbnail extends StatelessWidget {
  final AppLocalizations l10n;
  final String subject;
  const _DiplomaThumbnail({required this.l10n, required this.subject});

  Color get _color {
    final s = subject.toLowerCase();
    if (s == 'math') return AppColors.math;
    if (s == 'english') return AppColors.eng;
    return AppColors.secondary;
  }

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Container(
      width: 64,
      height: 84,
      decoration: BoxDecoration(
        color: pal.chipBg,
        borderRadius: AppRadii.roundedSm,
        border: Border.all(color: _color, width: 2),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.workspace_premium_rounded, color: _color, size: 22),
          const SizedBox(height: 4),
          Text(l10n.certificateThumbnailLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 6.5,
                  fontWeight: FontWeight.w800,
                  color: _color,
                  letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

/// Standalone diploma-style PDF builder. Reusing `PdfReport.generate()`
/// (features/result/pdf_report.dart) directly was impractical here without
/// a large rewrite — it's built around `TestPackage`/`TestResult`/
/// `wrongAnswers` (a live multi-page per-topic report), while a historical
/// certificate only ever has `RecentResult`'s title/subject/score/date. So
/// this builds a small standalone one-pager instead, reusing the same font
/// loading + color-token approach as pdf_report.dart for a consistent look.
class _DiplomaPdf {
  static const _ink1 = PdfColor.fromInt(0xFF18181B);
  static const _ink2 = PdfColor.fromInt(0xFF52525B);
  static const _border = PdfColor.fromInt(0xFFE4E4E7);
  static const _gold = PdfColor.fromInt(0xFFDE8E52);

  static Future<File> generate({
    required StudentSession session,
    required RecentResult result,
    required AppLocalizations l10n,
  }) async {
    final doc = pw.Document(title: 'Sertifikat - ${session.studentName}');

    final baseFontData =
        await rootBundle.load('assets/fonts/Inter-Regular.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/Inter-Bold.ttf');
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(baseFontData),
      bold: pw.Font.ttf(boldFontData),
    );

    final dateStr = result.submittedAt != null
        ? DateFormat('dd.MM.yyyy').format(result.submittedAt!.toLocal())
        : DateFormat('dd.MM.yyyy').format(DateTime.now());

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      theme: theme,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _gold, width: 3),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        padding: const pw.EdgeInsets.all(36),
        child: pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _border, width: 1),
          ),
          padding: const pw.EdgeInsets.all(28),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('A\'LOCHI',
                  style: pw.TextStyle(
                      fontSize: 14,
                      color: _gold,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 3)),
              pw.SizedBox(height: 16),
              pw.Text(l10n.certificateThumbnailLabel,
                  style: pw.TextStyle(
                      fontSize: 32,
                      color: _ink1,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 4)),
              pw.SizedBox(height: 24),
              pw.Text(l10n.diplomaIssuedToLabel,
                  style: const pw.TextStyle(color: _ink2, fontSize: 12)),
              pw.SizedBox(height: 6),
              pw.Text(session.studentName,
                  style: pw.TextStyle(
                      fontSize: 24,
                      color: _ink1,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 18),
              pw.Text(l10n.diplomaForTestResultLabel(result.title),
                  style: const pw.TextStyle(color: _ink2, fontSize: 13)),
              pw.SizedBox(height: 10),
              pw.Text('${result.score}/100',
                  style: pw.TextStyle(
                      fontSize: 40,
                      color: _gold,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 24),
              pw.Text(dateStr,
                  style: const pw.TextStyle(color: _ink2, fontSize: 11)),
            ],
          ),
        ),
      ),
    ));

    final dir = await getApplicationDocumentsDirectory();
    final safeName = session.studentName
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r"[^\w]"), '');
    final safeKey = result.testKey.replaceAll(RegExp(r'[^\w]'), '');
    final file = File('${dir.path}/Sertifikat_${safeName}_$safeKey.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }
}
