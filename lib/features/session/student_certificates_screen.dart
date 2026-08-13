// lib/features/session/student_certificates_screen.dart
//
// "Сертификаты и достижения" — self-login student cabinet screen, mockup:
// /Users/max/.gemini/antigravity-cli/brain/d4e52b23-4089-4731-b0f9-b3d97e1e20f0/mock4.jpg
//
// NOT wired into routing yet (done centrally afterward, per task).
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
// ponytail: hardcoded Russian strings (matches the mockup, which is
// Russian-only) instead of new AppLocalizations/ARB keys — this screen
// isn't wired in yet, so no route currently needs it localized. Add uz/ru
// ARB keys when centrally wired, same as every other student-cabinet screen.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/api/api_client.dart';
import '../../core/db/credential_cache.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/student_kpi_tile.dart';
import '../../shared/widgets/student_shell.dart';
import '../auth/login_screen.dart';

/// Badge thresholds — documented here so they can be reviewed/adjusted in
/// one place. All computed from real `RecentResult`/`stats` data, never
/// invented per-badge numbers.
class _BadgeThresholds {
  /// Math/English "mastery" badges: symmetric 90% bar for both subjects.
  static const int mastery = 90;

  /// Streak badge unlocks once the student has a real 3+ day streak (same
  /// `streak_days` field `_ProfileSummary`/`fetchMyProfile` already expose).
  static const int streakDays = 3;

  /// "Faol o'quvchi" (active student) badge: 5 completed tests.
  static const int activeTests = 5;

  /// Certificate minimum score — reuses the SAME threshold the app already
  /// treats as "passed" (`TestResult.passed => totalPct >= 60` in
  /// core/models/models.dart), instead of picking a new arbitrary number.
  static const int certificateMinScore = 60;
}

class _Badge {
  final String title;
  final IconData icon;
  final Color color;
  final bool unlocked;
  final String? unlockedValueLabel; // shown only when unlocked
  final double progress; // 0..1, shown only when locked
  const _Badge({
    required this.title,
    required this.icon,
    required this.color,
    required this.unlocked,
    this.unlockedValueLabel,
    this.progress = 0,
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

  String? _generatingCertKey;

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

  /// Same kiosk-security step as results_screen.dart's `_clearSession`.
  Future<void> _clearSession() async {
    api.clearToken();
    await CredentialCache.clear();
  }

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

  @override
  Widget build(BuildContext context) {
    return StudentShell(
      currentRoute: '/certificates',
      session: widget.session,
      title: 'Сертификаты и достижения',
      onLogout: _logoutNow,
      child: _body(),
    );
  }

  Widget _body() {
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
              const Icon(Icons.cloud_off_rounded,
                  color: AppColors.ink3, size: 28),
              const SizedBox(height: 12),
              Text('Не удалось загрузить данные',
                  textAlign: TextAlign.center,
                  style:
                      AppTextStyles.bodyMedium.copyWith(color: AppColors.ink2)),
              const SizedBox(height: 16),
              OutlinedButton(
                  onPressed: _load, child: const Text('Повторить')),
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
      ..sort((a, b) => (b.submittedAt ?? DateTime(0))
          .compareTo(a.submittedAt ?? DateTime(0)));

    final badges = _computeBadges(results, bestScore);
    final unlockedCount = badges.where((b) => b.unlocked).length;

    final filteredCertificates = _searchQuery.isEmpty
        ? certificates
        : certificates
            .where((c) =>
                c.title.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroBanner(
              certificatesCount: certificates.length,
              unlockedBadges: unlockedCount,
              totalBadges: badges.length,
              bestScore: bestScore,
            ),
            const SizedBox(height: 20),
            LayoutBuilder(builder: (context, c) {
              final narrow = c.maxWidth < 900;
              final badgeSection = _BadgeGrid(badges: badges);
              final progressPanel = _ProgressPanel(
                results: results,
                badges: badges,
              );
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
              query: _searchQuery,
              filter: _sectionFilter,
              onQueryChanged: (v) => setState(() => _searchQuery = v),
              onFilterChanged: (v) => setState(() => _sectionFilter = v),
            ),
            const SizedBox(height: 20),
            if (_sectionFilter != 2) ...[
              Text('Сертификаты',
                  style: AppTextStyles.titleMedium
                      .copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (filteredCertificates.isEmpty)
                _EmptyCertificates(hasQuery: _searchQuery.isNotEmpty)
              else
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: filteredCertificates
                      .map((c) => _CertificateCard(
                            session: widget.session,
                            result: c,
                            generating: _generatingCertKey == c.testKey,
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

  List<_Badge> _computeBadges(List<RecentResult> results, int bestScore) {
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
        title: 'Математика ustasi',
        icon: Icons.calculate_rounded,
        color: AppColors.math,
        unlocked: mathBest >= _BadgeThresholds.mastery,
        unlockedValueLabel: 'Открыт',
        progress: (mathBest / _BadgeThresholds.mastery).clamp(0, 1),
      ),
      _Badge(
        title: '100% Результат',
        icon: Icons.star_rounded,
        color: AppColors.gold,
        unlocked: bestScore >= 100,
        unlockedValueLabel: 'Открыт',
        progress: (bestScore / 100).clamp(0, 1),
      ),
      _Badge(
        title: streak > 0 ? '$streak дней подряд' : 'Дней подряд',
        icon: Icons.local_fire_department_rounded,
        color: AppColors.flame,
        unlocked: streak >= _BadgeThresholds.streakDays,
        unlockedValueLabel: 'Открыт',
        progress: (streak / _BadgeThresholds.streakDays).clamp(0, 1),
      ),
      _Badge(
        title: 'Знаток English',
        icon: Icons.school_rounded,
        color: AppColors.eng,
        unlocked: engBest >= _BadgeThresholds.mastery,
        unlockedValueLabel: 'Открыт',
        progress: (engBest / _BadgeThresholds.mastery).clamp(0, 1),
      ),
      _Badge(
        title: 'Активный ученик',
        icon: Icons.military_tech_rounded,
        color: AppColors.violet,
        unlocked: testsDone >= _BadgeThresholds.activeTests,
        unlockedValueLabel: 'Открыт',
        progress: (testsDone / _BadgeThresholds.activeTests).clamp(0, 1),
      ),
    ];
  }

  Future<void> _downloadCertificate(RecentResult result) async {
    setState(() => _generatingCertKey = result.testKey);
    try {
      final file = await _DiplomaPdf.generate(
        session: widget.session,
        result: result,
      );
      if (!mounted) return;
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PDF yaratishda xatolik: $e'),
        backgroundColor: AppColors.err,
      ));
    } finally {
      if (mounted) setState(() => _generatingCertKey = null);
    }
  }
}

class _HeroBanner extends StatelessWidget {
  final int certificatesCount;
  final int unlockedBadges;
  final int totalBadges;
  final int bestScore;

  const _HeroBanner({
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
                Text('Ваши успехи заслуживают награды!',
                    style: AppTextStyles.titleLarge.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                    'Продолжайте учиться, собирайте бейджи и получайте '
                    'сертификаты за отличные результаты.',
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
                        label: 'Получено сертификатов',
                        value: '$certificatesCount',
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: KpiTile(
                        icon: Icons.military_tech_rounded,
                        iconColor: AppColors.violet,
                        iconBg: AppColors.violetMuted,
                        label: 'Открыто бейджей',
                        value: '$unlockedBadges/$totalBadges',
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: KpiTile(
                        icon: Icons.trending_up_rounded,
                        iconColor: AppColors.success,
                        iconBg: AppColors.successMuted,
                        label: 'Лучший результат',
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
  final List<_Badge> badges;
  const _BadgeGrid({required this.badges});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Бейджи и достижения',
              style: AppTextStyles.titleMedium
                  .copyWith(fontWeight: FontWeight.w800)),
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
    final color = badge.unlocked ? badge.color : AppColors.ink3;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: AppRadii.roundedLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: badge.unlocked ? color.withValues(alpha: 0.14) : AppColors.chipBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(badge.icon, color: color, size: 26),
          ),
          const SizedBox(height: 10),
          Text(badge.title,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelMedium
                  .copyWith(fontWeight: FontWeight.w700, color: AppColors.ink1)),
          const SizedBox(height: 8),
          if (badge.unlocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: const BoxDecoration(
                color: AppColors.successMuted,
                borderRadius: AppRadii.roundedFull,
              ),
              child: Text('Открыт',
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.success, fontWeight: FontWeight.w700)),
            )
          else ...[
            ClipRRect(
              borderRadius: AppRadii.roundedFull,
              child: LinearProgressIndicator(
                value: badge.progress,
                minHeight: 6,
                backgroundColor: AppColors.chipBg,
                valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
              ),
            ),
            const SizedBox(height: 6),
            Text('${(badge.progress * 100).round()}%',
                style: AppTextStyles.caption.copyWith(color: AppColors.ink3)),
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
  final List<RecentResult> results;
  final List<_Badge> badges;
  const _ProgressPanel({required this.results, required this.badges});

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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Прогресс достижений',
              style: AppTextStyles.titleMedium
                  .copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (subjectAverages.isEmpty)
            Text('Пока нет данных по предметам',
                style:
                    AppTextStyles.bodyMedium.copyWith(color: AppColors.ink3))
          else
            ...subjectAverages.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SubjectProgressRow(
                      subject: e.key, avgPct: e.value.round()),
                )),
          if (locked.isNotEmpty) ...[
            const SizedBox(height: 4),
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
                        'Ближе всего: «${locked.first.title}» — '
                        '${(locked.first.progress * 100).round()}%',
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
  final String subject;
  final int avgPct;
  const _SubjectProgressRow({required this.subject, required this.avgPct});

  String get _label {
    if (subject == 'math') return 'Математика';
    if (subject == 'english') return 'English';
    return subject;
  }

  Color get _color {
    if (subject == 'math') return AppColors.math;
    if (subject == 'english') return AppColors.eng;
    return AppColors.violet;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(_label,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.ink1))),
            Text('$avgPct%',
                style: AppTextStyles.labelMedium
                    .copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: AppRadii.roundedFull,
          child: LinearProgressIndicator(
            value: (avgPct / 100).clamp(0, 1),
            minHeight: 6,
            backgroundColor: AppColors.chipBg,
            valueColor: AlwaysStoppedAnimation(_color),
          ),
        ),
      ],
    );
  }
}

/// ponytail: "Только новые"/"Сначала новые" sort chips from the mockup are
/// decorative in the reference — skipped (search + all/certs/badges filter
/// already cover the functional need); add if product wants real sorting.
class _SearchAndFilterRow extends StatelessWidget {
  final String query;
  final int filter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<int> onFilterChanged;

  const _SearchAndFilterRow({
    required this.query,
    required this.filter,
    required this.onQueryChanged,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            onChanged: onQueryChanged,
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              hintText: 'Поиск по сертификатам...',
            ),
          ),
        ),
        _FilterChip(
            label: 'Все', selected: filter == 0, onTap: () => onFilterChanged(0)),
        _FilterChip(
            label: 'Сертификаты',
            selected: filter == 1,
            onTap: () => onFilterChanged(1)),
        _FilterChip(
            label: 'Бейджи', selected: filter == 2, onTap: () => onFilterChanged(2)),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.secondary : AppColors.surface,
          borderRadius: AppRadii.roundedMd,
          border: Border.all(
              color: selected ? AppColors.secondary : AppColors.border),
        ),
        child: Text(label,
            style: AppTextStyles.labelMedium.copyWith(
              color: selected ? Colors.white : AppColors.ink2,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}

class _EmptyCertificates extends StatelessWidget {
  final bool hasQuery;
  const _EmptyCertificates({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.workspace_premium_outlined,
              color: AppColors.ink3, size: 32),
          const SizedBox(height: 12),
          Text(
              hasQuery
                  ? 'Ничего не найдено'
                  : 'Пройдите тест на ${_BadgeThresholds.certificateMinScore}%+, '
                      'чтобы получить свой первый сертификат',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink3)),
        ],
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  final StudentSession session;
  final RecentResult result;
  final bool generating;
  final VoidCallback onDownload;

  const _CertificateCard({
    required this.session,
    required this.result,
    required this.generating,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = result.submittedAt != null
        ? DateFormat('dd.MM.yyyy').format(result.submittedAt!.toLocal())
        : '';
    return Container(
      width: 320,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: AppColors.border),
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
          _DiplomaThumbnail(subject: result.subject),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge
                        .copyWith(fontWeight: FontWeight.w700)),
                if (dateStr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Выдан $dateStr',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.ink3)),
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
                    label: Text(generating ? 'Готовим...' : 'Скачать PDF',
                        style: AppTextStyles.labelMedium),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      side: const BorderSide(color: AppColors.border),
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
  final String subject;
  const _DiplomaThumbnail({required this.subject});

  Color get _color {
    final s = subject.toLowerCase();
    if (s == 'math') return AppColors.math;
    if (s == 'english') return AppColors.eng;
    return AppColors.secondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 84,
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: AppRadii.roundedSm,
        border: Border.all(color: _color, width: 2),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.workspace_premium_rounded, color: _color, size: 22),
          const SizedBox(height: 4),
          Text('СЕРТИФИКАТ',
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
              pw.Text('СЕРТИФИКАТ',
                  style: pw.TextStyle(
                      fontSize: 32,
                      color: _ink1,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 4)),
              pw.SizedBox(height: 24),
              pw.Text('выдан', style: const pw.TextStyle(color: _ink2, fontSize: 12)),
              pw.SizedBox(height: 6),
              pw.Text(session.studentName,
                  style: pw.TextStyle(
                      fontSize: 24,
                      color: _ink1,
                      fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 18),
              pw.Text('за результат по тесту "${result.title}"',
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
