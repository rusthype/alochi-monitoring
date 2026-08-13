// lib/features/session/student_home_screen.dart
//
// "Главная" (home) branch for the self-login student cabinet — dark2.jpg.
// Bare content only (no Scaffold/StudentShell wrap): plugged into
// StatefulShellRoute as a branch child by a separate wiring step, same
// convention my_tests_screen.dart/student_results_screen.dart follow
// post-Bosqich-1 refactor (see student_shell.dart's file header).
//
// Every number traces back to real backend data — nothing here is
// fabricated:
//   - GET /home-summary/ (HomeSummaryView, apps/monitoring/views.py):
//     attendance_pct, streak_days, last_result, urgent_tests, next_lesson.
//     `next_lesson` is OMITTED from the response entirely (not sent as
//     null) when no real scheduled lesson exists — checked below via
//     `_home!.containsKey('next_lesson')`, not a null check.
//   - GET /messages/ (api.fetchMessages, added by the parallel Сообщения
//     agent): announcements = items with type 'system'/'teacher', latest 3.
//
// Simplifications vs dark2.jpg (documented per plan §Bosqich 6 — ponytail:
// no fabricated numbers, ever):
//   - Hero banner: the mockup's "4 из 5 задач / 80%" weekly progress bar
//     has NO backend source (home-summary carries no weekly task-count
//     field at all) — dropped entirely rather than invented. The banner
//     instead surfaces the two real per-student numbers home-summary
//     actually has (streak_days, attendance_pct) as small stat chips, plus
//     a static motivational line (not personalized data, so not a
//     fabrication concern).
//   - "Активность и серия" weekly grid: home-summary has no per-weekday
//     activity flags, only a scalar `streak_days` (consecutive calendar
//     days ending today with >=1 test submission — see HomeSummaryView).
//     The grid below visualizes that real scalar onto the current
//     Mon–Sun calendar week (days within the last `streak_days` days get a
//     checkmark, today gets a flame if streak_days >= 1, future days in
//     the week render as empty placeholders) — an honest rendering of one
//     real number, not a fabricated per-day dataset. The mockup's separate
//     "Выполнено задач на этой неделе 12/15" bar chart has no backing
//     field at all and is dropped.
//   - Urgent-test cards: HomeSummaryView's urgent_tests items carry only
//     {test_key, title, available_until} — a deliberately trimmed subset
//     of the full catalog-entry shape my_tests_screen.dart's _StudentTest
//     parses (no subject/duration/question_count/status). Cards show the
//     title plus a deadline-urgency label computed client-side from
//     available_until; tapping any card (or "Посмотреть все") navigates to
//     /my_tests — the full catalog screen already owns the
//     fetchTest+EngineHost start flow, so it isn't duplicated here for a
//     stripped-down entry that lacks the grade/variant data that flow
//     needs anyway.
//   - "Ближайший урок" — hidden entirely when `next_lesson` is absent
//     (never a fake "no lesson scheduled" placeholder that implies a
//     schedule exists). No "Посмотреть расписание" button — this app has
//     no schedule/timetable screen to link to.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/student_palette.dart';
import '../../shared/widgets/subject_badge.dart';

class StudentHomeScreen extends StatefulWidget {
  final StudentSession session;

  const StudentHomeScreen({super.key, required this.session});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  bool _loading = true;
  Map<String, dynamic>? _home; // raw /home-summary/ payload, null = failed
  List<Map<String, dynamic>> _announcements = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.fetchHomeSummary(authToken: widget.session.token),
        api.fetchMessages(authToken: widget.session.token),
      ]);
      if (!mounted) return;
      final home = results[0] as Map<String, dynamic>?;
      final messages = results[1] as List<Map<String, dynamic>>;
      setState(() {
        _home = home;
        _announcements = messages
            .where((m) => m['type'] == 'system' || m['type'] == 'teacher')
            .take(3)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_home == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_rounded, color: AppColors.error, size: 28),
              const SizedBox(height: 12),
              Text(l10n.loadFailed, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: Text(l10n.retryCheck)),
            ],
          ),
        ),
      );
    }

    final home = _home!;
    final isSmall = MediaQuery.of(context).size.width < 900;
    final urgentTests = (home['urgent_tests'] is List)
        ? List<Map<String, dynamic>>.from(
            (home['urgent_tests'] as List).whereType<Map>().map(Map<String, dynamic>.from))
        : <Map<String, dynamic>>[];
    final lastResult = home['last_result'] is Map
        ? Map<String, dynamic>.from(home['last_result'] as Map)
        : null;
    final nextLesson = home.containsKey('next_lesson') && home['next_lesson'] is Map
        ? Map<String, dynamic>.from(home['next_lesson'] as Map)
        : null;

    final activityAndActions = isSmall
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ActivityStreakCard(home: home),
              const SizedBox(height: 16),
              _QuickActionsCard(),
            ],
          )
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _ActivityStreakCard(home: home)),
                const SizedBox(width: 16),
                Expanded(child: _QuickActionsCard()),
              ],
            ),
          );

    final sideColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (nextLesson != null) ...[
          _NextLessonCard(lesson: nextLesson),
          const SizedBox(height: 16),
        ],
        if (lastResult != null) _LastResultCard(result: lastResult),
      ],
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroBanner(studentName: widget.session.studentName, home: home),
            const SizedBox(height: 20),
            _UrgentTestsSection(tests: urgentTests),
            const SizedBox(height: 20),
            if (isSmall)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AnnouncementsSection(items: _announcements),
                  const SizedBox(height: 20),
                  activityAndActions,
                  const SizedBox(height: 20),
                  sideColumn,
                ],
              )
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _AnnouncementsSection(items: _announcements),
                          const SizedBox(height: 16),
                          activityAndActions,
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(flex: 1, child: sideColumn),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration(StudentPalette pal) => BoxDecoration(
      color: pal.surface,
      borderRadius: AppRadii.roundedXl,
      border: Border.all(color: pal.border),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3)),
      ],
    );

/// First name for the "Добро пожаловать, {name}!" greeting. This app's
/// student names are stored "Familiya Ism" (surname first — matches the
/// avatar-initials convention used elsewhere, e.g. "VA" for "Valiyev
/// Alixon"), so the LAST word is the given name. Falls back to the full
/// string when it's a single word (no assumption broken either way).
String _firstName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  return parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : fullName;
}

class _HeroBanner extends StatelessWidget {
  final String studentName;
  final Map<String, dynamic> home;

  const _HeroBanner({required this.studentName, required this.home});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final streakDays = (home['streak_days'] as num?)?.toInt() ?? 0;
    final attendancePct = (home['attendance_pct'] as num?)?.toInt();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.brand, AppColors.amberDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadii.roundedXl2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.homeHeroWelcome(_firstName(studentName)),
                  style: AppTextStyles.titleLarge.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.homeHeroSubtitle,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: Colors.white.withValues(alpha: 0.9)),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _heroChip(Icons.local_fire_department_rounded,
                        '$streakDays ${l10n.kpiStreakDays}'),
                    _heroChip(Icons.event_available_rounded,
                        '${l10n.homeAttendanceLabel}: ${attendancePct != null ? '$attendancePct%' : l10n.noDataAvailable}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 56),
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: AppRadii.roundedFull,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(text,
                style: AppTextStyles.labelMedium
                    .copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

/// Deadline urgency label/color for an urgent-test card, computed
/// client-side from `available_until` (the only timing field
/// HomeSummaryView's trimmed urgent_tests shape carries).
(String, Color) _urgentDeadlineVisual(AppLocalizations l10n, DateTime deadline) {
  final diff = deadline.difference(DateTime.now());
  if (diff.inHours < 3) {
    final hours = diff.inHours < 1 ? 1 : diff.inHours;
    return (l10n.homeDeadlineHours(hours), AppColors.error);
  }
  if (diff.inHours < 24) {
    return (l10n.homeDeadlineHours(diff.inHours), AppColors.amberDark);
  }
  if (diff.inHours < 48) return (l10n.homeDeadlineTomorrow, AppColors.amberDark);
  return (l10n.homeDeadlineDaysLeft(diff.inDays), AppColors.ink2);
}

class _UrgentTestsSection extends StatelessWidget {
  final List<Map<String, dynamic>> tests;

  const _UrgentTestsSection({required this.tests});

  @override
  Widget build(BuildContext context) {
    if (tests.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.homeUrgentTestsTitle,
                style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w800)),
            TextButton(
              onPressed: () => context.go('/my_tests'),
              child: Text(l10n.homeViewAllTests),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // dark2.jpg shows a scroll-arrow carousel; a Wrap flows to a 2nd
        // line on narrow widths instead — same information, no bespoke
        // carousel widget needed for an MVP row of at most 4 cards.
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final t in tests)
              SizedBox(width: 240, child: _UrgentTestCard(test: t)),
          ],
        ),
      ],
    );
  }
}

class _UrgentTestCard extends StatelessWidget {
  final Map<String, dynamic> test;

  const _UrgentTestCard({required this.test});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final title = test['title']?.toString() ?? '';
    final deadline = DateTime.tryParse(test['available_until']?.toString() ?? '');
    final visual = deadline != null ? _urgentDeadlineVisual(l10n, deadline.toLocal()) : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.roundedXl,
        onTap: () => context.go('/my_tests'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(pal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  subjectBadge(''),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelLarge
                            .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
                  ),
                ],
              ),
              if (visual != null) ...[
                const SizedBox(height: 10),
                Text(visual.$1,
                    style: AppTextStyles.caption
                        .copyWith(color: visual.$2, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/my_tests'),
                  child: Text(l10n.startTest),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementsSection extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const _AnnouncementsSection({required this.items});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.homeAnnouncementsTitle,
            style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: _cardDecoration(pal),
            child: Text(l10n.homeAnnouncementsEmpty,
                style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3)),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final m in items) SizedBox(width: 260, child: _AnnouncementCard(item: m)),
            ],
          ),
      ],
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _AnnouncementCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final title = item['title']?.toString() ?? '';
    final body = item['body']?.toString() ?? '';
    final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '');
    final isSystem = item['type'] == 'system';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(pal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isSystem ? Icons.campaign_rounded : Icons.person_rounded,
              color: AppColors.brand, size: 22),
          const SizedBox(height: 10),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelLarge
                  .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
          const SizedBox(height: 4),
          Text(body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: pal.ink2)),
          const SizedBox(height: 8),
          Text(
            createdAt != null ? DateFormat('dd.MM.yyyy').format(createdAt.toLocal()) : '',
            style: AppTextStyles.caption.copyWith(color: pal.ink3),
          ),
        ],
      ),
    );
  }
}

DateTime _mondayOfWeek(DateTime d) {
  final date = DateTime(d.year, d.month, d.day);
  return date.subtract(Duration(days: date.weekday - 1)); // weekday: Mon=1..Sun=7
}

class _ActivityStreakCard extends StatelessWidget {
  final Map<String, dynamic> home;

  const _ActivityStreakCard({required this.home});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final streakDays = (home['streak_days'] as num?)?.toInt() ?? 0;
    final attendancePct = (home['attendance_pct'] as num?)?.toInt();

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final monday = _mondayOfWeek(todayDate);
    final weekdayLabels = [
      l10n.weekdayMonShort,
      l10n.weekdayTueShort,
      l10n.weekdayWedShort,
      l10n.weekdayThuShort,
      l10n.weekdayFriShort,
      l10n.weekdaySatShort,
      l10n.weekdaySunShort,
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(pal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.homeActivityStreakTitle,
              style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statTile(pal, Icons.local_fire_department_rounded, AppColors.flame,
                    '$streakDays', l10n.kpiStreakDays),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                    pal,
                    Icons.event_available_rounded,
                    AppColors.success,
                    attendancePct != null ? '$attendancePct%' : '—',
                    l10n.homeAttendanceLabel),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(child: _dayDot(pal, monday.add(Duration(days: i)), todayDate,
                    streakDays, weekdayLabels[i])),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statTile(
          StudentPalette pal, IconData icon, Color color, String value, String label) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(color: pal.chipBg, borderRadius: AppRadii.roundedMd),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: AppTextStyles.titleMedium
                          .copyWith(fontWeight: FontWeight.w800, color: pal.ink1)),
                  Text(label, style: AppTextStyles.caption.copyWith(color: pal.ink3)),
                ],
              ),
            ),
          ],
        ),
      );

  /// One weekday dot in the current Mon–Sun week: checked if it falls
  /// within the most recent `streakDays` days (streak counts backward
  /// from today, per HomeSummaryView), flame if it's today with an active
  /// streak, muted/empty otherwise (including future days in the week).
  Widget _dayDot(
      StudentPalette pal, DateTime day, DateTime today, int streakDays, String label) {
    final isFuture = day.isAfter(today);
    final isToday = day.isAtSameMomentAs(today);
    final daysAgo = today.difference(day).inDays;
    final isInStreak = !isFuture && daysAgo < streakDays;

    Widget dot;
    if (isToday && streakDays > 0) {
      dot = const Icon(Icons.local_fire_department_rounded, color: AppColors.flame, size: 20);
    } else if (isInStreak) {
      dot = const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20);
    } else {
      dot = Icon(Icons.circle_outlined, color: pal.ink3, size: 18);
    }

    return Column(
      children: [
        dot,
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.caption.copyWith(color: pal.ink3, fontSize: 11)),
        Text(DateFormat('dd.MM').format(day),
            style: AppTextStyles.caption.copyWith(color: pal.ink3, fontSize: 10)),
      ],
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(pal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.quickActionsTitle,
              style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _tile(context, pal, Icons.assignment_rounded, l10n.myTestsTitle,
                  l10n.homeQuickActionTestsDesc, () => context.go('/my_tests')),
              _tile(context, pal, Icons.bar_chart_rounded, l10n.resultsScreenTitle,
                  l10n.homeQuickActionResultsDesc, () => context.go('/results')),
              _tile(context, pal, Icons.chat_bubble_rounded, l10n.homeQuickActionContactTeacher,
                  l10n.homeQuickActionContactTeacherDesc, () => context.go('/messages')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, StudentPalette pal, IconData icon, String title,
      String desc, VoidCallback onTap) {
    return SizedBox(
      width: 150,
      child: Material(
        color: pal.chipBg,
        borderRadius: AppRadii.roundedMd,
        child: InkWell(
          borderRadius: AppRadii.roundedMd,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.brand, size: 22),
                const SizedBox(height: 8),
                Text(title,
                    style: AppTextStyles.labelMedium
                        .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
                const SizedBox(height: 2),
                Text(desc, style: AppTextStyles.caption.copyWith(color: pal.ink3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextLessonCard extends StatelessWidget {
  final Map<String, dynamic> lesson;

  const _NextLessonCard({required this.lesson});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final subject = lesson['subject']?.toString() ?? '';
    final date = DateTime.tryParse(lesson['date']?.toString() ?? '');
    final timeRaw = lesson['time']?.toString();
    final time = (timeRaw != null && timeRaw.length >= 5) ? timeRaw.substring(0, 5) : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(pal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.homeNextLessonTitle,
              style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(
            children: [
              subjectBadge(subject),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject,
                        style: AppTextStyles.labelLarge
                            .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
                    if (date != null || time != null)
                      Text(
                        [
                          if (date != null) DateFormat('dd.MM.yyyy').format(date),
                          if (time != null) time,
                        ].join(' · '),
                        style: AppTextStyles.caption.copyWith(color: pal.ink3),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _homeGradeColor(int score) {
  if (score >= 90) return AppColors.success;
  if (score >= 70) return AppColors.secondary;
  if (score >= 50) return AppColors.amber;
  return AppColors.error;
}

String _homeGradeLabel(AppLocalizations l10n, int score) {
  if (score >= 90) return l10n.gradeExcellent;
  if (score >= 70) return l10n.gradeGood;
  if (score >= 50) return l10n.gradeSatisfactory;
  return l10n.gradeWeak;
}

class _LastResultCard extends StatelessWidget {
  final Map<String, dynamic> result;

  const _LastResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final title = result['title']?.toString() ?? '';
    final score = (result['score'] as num?)?.toInt();
    final submittedAt = DateTime.tryParse(result['submitted_at']?.toString() ?? '');
    final color = score != null ? _homeGradeColor(score) : pal.ink3;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(pal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.homeLastResultTitle,
              style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(
            children: [
              subjectBadge(''),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge
                        .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
              ),
            ],
          ),
          if (score != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text('$score%',
                    style: AppTextStyles.displayLarge
                        .copyWith(color: color, fontWeight: FontWeight.w800, fontSize: 28)),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12), borderRadius: AppRadii.roundedFull),
                  child: Text(_homeGradeLabel(l10n, score),
                      style: AppTextStyles.caption
                          .copyWith(color: color, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                submittedAt != null ? DateFormat('dd.MM.yyyy').format(submittedAt.toLocal()) : '',
                style: AppTextStyles.caption.copyWith(color: pal.ink3),
              ),
              TextButton(
                onPressed: () => context.go('/results'),
                child: Text(l10n.homeToResultsLink),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
