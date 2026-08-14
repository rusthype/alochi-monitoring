// lib/features/session/student_results_screen.dart
//
// Full "Результаты" dashboard for the self-login student cabinet — replaces
// the minimal `results_screen.dart` list with KPI cards, a score-trend
// chart, a per-subject breakdown, filter/sort controls, a result card grid
// and a side panel, matching the design mockup.
//
// Every number on this screen traces back to `GET /my-profile/`
// (`api.fetchMyProfile`) — same endpoint/fields the old ResultsScreen and
// MyTestsScreen's `_ProfileSummary` already use:
//   - `stats.tests_completed` / `stats.average_score` / `stats.average_time_seconds`
//     → KPI tiles (server truth, never client-recomputed from the capped
//     result list below). `average_time_seconds` is `null` until the
//     elapsed-time capture work produces real values for new submissions
//     (ALL historical results have it null) — the 4th "Среднее время" tile
//     is omitted entirely (not a fake "0 мин") whenever it's null, same
//     null-guard convention every other tile here already follows.
//   - `recent_results` (server-capped, historically ≤10) → RecentResult
//     list, source for: highest-score KPI, trend chart, subject breakdown,
//     result cards, side-panel "recent reports". Any per-subject/point-in-
//     time chart is therefore also bounded to this same capped window —
//     same honest scope as the old screen, not a fabricated full history.
//     Each entry also carries `id` (MonitoringResult UUID) as of the
//     2026-08 backend pass — the key `_ResultCard`'s "Подробный разбор"
//     button uses to call `GET /results/<id>/breakdown/`.
//
// Deliberately NOT sourced (no such field exists anywhere in this app's
// API/model layer): per-subject correct/total counts (vocab_cor/tot etc.),
// and a bulk "download all as ZIP" quick action. Rather than fabricate
// either, they're omitted; see PR notes for the full scoping rationale.
//
// Per-question "Подробный разбор" breakdown (2026-08 pass): each
// `_ResultCard` now has a button calling `api.fetchResultBreakdown`
// (`GET /results/<id>/breakdown/`, ResultBreakdownView). A `null` response
// means EITHER the result predates per-question detail (legacy submission,
// no `raw_answers` ever stored) OR — indistinguishably, by server design —
// the id doesn't belong to this student; both render the same "no data"
// message, never an app error. A non-null response may still carry
// `has_question_detail: false` (bobs/topics/units/parts aggregate only,
// no per-question list) for the same legacy-data reason.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:fl_chart/fl_chart.dart';
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
import '../../shared/widgets/subject_badge.dart';

enum _SortMode { newest, oldest, highestScore }

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

Color _gradeColor(int score) {
  if (score >= 90) return AppColors.success;
  if (score >= 70) return AppColors.secondary;
  if (score >= 50) return AppColors.amber;
  return AppColors.error;
}

String _gradeLabel(AppLocalizations l10n, int score) {
  if (score >= 90) return l10n.gradeExcellent;
  if (score >= 70) return l10n.gradeGood;
  if (score >= 50) return l10n.gradeSatisfactory;
  return l10n.gradeWeak;
}

String _subjectLabel(AppLocalizations l10n, String subject) {
  final s = subject.toLowerCase();
  if (s == 'math') return l10n.mathSubjectFull;
  if (s == 'english') return l10n.englishSubjectFull;
  if (subject.isEmpty) return l10n.otherSubject;
  return subject[0].toUpperCase() + subject.substring(1);
}

class StudentResultsScreen extends StatefulWidget {
  final StudentSession session;

  const StudentResultsScreen({super.key, required this.session});

  @override
  State<StudentResultsScreen> createState() => _StudentResultsScreenState();
}

class _StudentResultsScreenState extends State<StudentResultsScreen> {
  bool _loading = true;
  int? _testsCompleted; // null = missing/malformed, NEVER shown as 0
  int? _averageScore; // null = no results yet, NEVER rendered as 0%
  int? _averageTimeSeconds; // null = no result has a stored duration yet
  List<RecentResult>? _results; // null = fetch failed/offline, never fabricated

  String _query = '';
  String? _subjectFilter; // null = all subjects
  _SortMode _sort = _SortMode.newest;
  // Identity-keyed (not RecentResult.testKey, which defaults to '' and can
  // collide across multiple results missing that field). RecentResult
  // doesn't override ==/hashCode, so Set membership here is already
  // reference-identity, which is genuinely unique per card.
  final Set<RecentResult> _pdfKeys = {}; // results currently generating a PDF
  final Set<RecentResult> _breakdownKeys = {}; // results currently fetching a breakdown

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
          _testsCompleted = null;
          _averageScore = null;
          _averageTimeSeconds = null;
          _loading = false;
        });
        return;
      }
      final stats = (profile['stats'] is Map)
          ? Map<String, dynamic>.from(profile['stats'] as Map)
          : <String, dynamic>{};
      setState(() {
        _results = RecentResult.listFromJson(profile['recent_results']);
        _testsCompleted = (stats['tests_completed'] as num?)?.toInt();
        _averageScore = (stats['average_score'] as num?)?.toInt();
        _averageTimeSeconds = (stats['average_time_seconds'] as num?)?.toInt();
        _loading = false;
      });
    } catch (e) {
      // Malformed payload — same treatment as fetch failure.
      if (!mounted) return;
      setState(() {
        _results = null;
        _testsCompleted = null;
        _averageScore = null;
        _averageTimeSeconds = null;
        _loading = false;
      });
    }
  }

  List<String> get _subjects {
    final set = <String>{};
    for (final r in _results ?? const <RecentResult>[]) {
      if (r.subject.isNotEmpty) set.add(r.subject.toLowerCase());
    }
    return set.toList()..sort();
  }

  List<RecentResult> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = (_results ?? const <RecentResult>[]).where((r) {
      if (_subjectFilter != null && r.subject.toLowerCase() != _subjectFilter) {
        return false;
      }
      if (q.isNotEmpty && !r.title.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    switch (_sort) {
      case _SortMode.newest:
        list.sort((a, b) =>
            (b.submittedAt ?? DateTime(0)).compareTo(a.submittedAt ?? DateTime(0)));
        break;
      case _SortMode.oldest:
        list.sort((a, b) =>
            (a.submittedAt ?? DateTime(0)).compareTo(b.submittedAt ?? DateTime(0)));
        break;
      case _SortMode.highestScore:
        list.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
        break;
    }
    return list;
  }

  int? get _bestScore {
    final scores =
        (_results ?? const <RecentResult>[]).map((r) => r.score).whereType<int>();
    if (scores.isEmpty) return null;
    return scores.reduce((a, b) => a > b ? a : b);
  }

  Future<void> _downloadPdf(RecentResult r) async {
    if (_pdfKeys.contains(r)) return;
    setState(() => _pdfKeys.add(r));
    final l10n = AppLocalizations.of(context)!;
    try {
      final file = await _ResultPdf.generate(
        session: widget.session,
        result: r,
        l10n: l10n,
      );
      if (!mounted) return;
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.pdfError(e.toString())),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _pdfKeys.remove(r));
    }
  }

  Future<void> _viewBreakdown(RecentResult r) async {
    if (_breakdownKeys.contains(r)) return;
    setState(() => _breakdownKeys.add(r));
    final l10n = AppLocalizations.of(context)!;
    try {
      final breakdown =
          await api.fetchResultBreakdown(r.id, authToken: widget.session.token);
      if (!mounted) return;
      if (breakdown == null) {
        // 404 — either legacy result with no breakdown data at all, or (by
        // server design, indistinguishable) not this student's — an
        // expected outcome for old results, never an app error.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.breakdownNoDataMessage)),
        );
        return;
      }
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _BreakdownSheet(result: r, breakdown: breakdown),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.loadFailed),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _breakdownKeys.remove(r));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSmall = MediaQuery.of(context).size.width < 900;
    return _body(l10n, isSmall);
  }

  Widget _body(AppLocalizations l10n, bool isSmall) {
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
    final filtered = _filtered;
    final chartCard = _TrendChartCard(results: results);
    final subjectsCard = _SubjectBreakdownCard(results: results);
    final grid = _ResultsGrid(
      results: filtered,
      hasAnyResults: results.isNotEmpty,
      pdfKeys: _pdfKeys,
      onDownloadPdf: _downloadPdf,
      breakdownKeys: _breakdownKeys,
      onViewBreakdown: _viewBreakdown,
    );
    final sidePanel = _SidePanel(
      results: results,
      pdfKeys: _pdfKeys,
      onDownloadPdf: _downloadPdf,
      onRefresh: _load,
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _KpiRow(
              testsCompleted: _testsCompleted,
              averageScore: _averageScore,
              bestScore: _bestScore,
              averageTimeSeconds: _averageTimeSeconds,
            ),
            const SizedBox(height: 16),
            if (isSmall)
              Column(children: [
                chartCard,
                const SizedBox(height: 16),
                subjectsCard,
              ])
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: chartCard),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: subjectsCard),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _FilterBar(
              subjects: _subjects,
              subjectFilter: _subjectFilter,
              sort: _sort,
              onQueryChanged: (v) => setState(() => _query = v),
              onSubjectChanged: (v) => setState(() => _subjectFilter = v),
              onSortChanged: (v) => setState(() => _sort = v),
            ),
            const SizedBox(height: 16),
            if (isSmall) ...[
              grid,
              const SizedBox(height: 20),
              sidePanel,
            ] else
              // No IntrinsicHeight here: `grid` (_ResultsGrid) builds itself
              // via LayoutBuilder, and LayoutBuilder cannot report an
              // intrinsic height — wrapping this Row in IntrinsicHeight threw
              // a cascading "RenderBox was not laid out: 'hasSize'" on every
              // frame, leaving the whole screen blank (reproduced via
              // computer-use: opening this screen renders nothing at all).
              // Top-aligned via CrossAxisAlignment.start instead of
              // stretching both columns to match heights.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: grid),
                  const SizedBox(width: 20),
                  Expanded(flex: 1, child: sidePanel),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Formats `stats.average_time_seconds` for the KPI tile — plain minutes
/// under an hour, "Xч Yмин"/localized-equivalent otherwise. Caller only
/// invokes this when the value is non-null (see [_KpiRow]'s own guard).
String _formatAverageTime(AppLocalizations l10n, int seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return l10n.durationMinutesLabel(minutes);
  return l10n.kpiAverageTimeHoursMinutes(minutes ~/ 60, minutes % 60);
}

/// Total tests / average score / average time (server truth from `stats`)
/// + highest score (client-computed max of the capped `recent_results`
/// window — honest, bounded to what's visible, not a fabricated all-time
/// max). The "Среднее время" tile only renders when [averageTimeSeconds] is
/// non-null — `null` means no result has a stored duration yet (true for
/// every historical result until the elapsed-time capture work starts
/// producing values), never rendered as a fake "0 мин" tile.
class _KpiRow extends StatelessWidget {
  final int? testsCompleted;
  final int? averageScore;
  final int? bestScore;
  final int? averageTimeSeconds;

  const _KpiRow(
      {required this.testsCompleted,
      required this.averageScore,
      required this.bestScore,
      required this.averageTimeSeconds});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tiles = [
      KpiTile(
        icon: Icons.assignment_turned_in_rounded,
        iconColor: const Color(0xFF2E7D32),
        iconBg: const Color(0xFFE8F5E9),
        label: l10n.kpiTestsCompleted,
        value: testsCompleted != null ? '$testsCompleted' : '—',
      ),
      KpiTile(
        icon: Icons.star_rounded,
        iconColor: const Color(0xFFF57F17),
        iconBg: const Color(0xFFFFF8E1),
        label: l10n.kpiAverageScore,
        value: averageScore != null ? '$averageScore%' : '—',
      ),
      KpiTile(
        icon: Icons.emoji_events_rounded,
        iconColor: AppColors.violet,
        iconBg: AppColors.violetMuted,
        label: l10n.kpiBestScore,
        value: bestScore != null ? '$bestScore%' : '—',
      ),
      if (averageTimeSeconds != null)
        KpiTile(
          icon: Icons.timer_outlined,
          iconColor: AppColors.secondary,
          iconBg: AppColors.primaryMuted,
          label: l10n.kpiAverageTime,
          value: _formatAverageTime(l10n, averageTimeSeconds!),
        ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 480) {
        return Column(
          children: [
            for (final t in tiles)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: t),
          ],
        );
      }
      return Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: tiles[i]),
          ],
        ],
      );
    });
  }
}

/// Score-by-date line chart — built entirely from `recent_results` entries
/// that have both a real `score` and `submitted_at` (skips anything else,
/// never interpolates/fabricates a point). Same server-capped window the
/// rest of this screen uses, so the subtitle says exactly how many points
/// are plotted instead of implying a fixed "last 8".
class _TrendChartCard extends StatelessWidget {
  final List<RecentResult> results;

  const _TrendChartCard({required this.results});

  List<({DateTime date, int score})> get _points {
    final pts = results
        .where((r) => r.score != null && r.submittedAt != null)
        .map((r) => (date: r.submittedAt!, score: r.score!))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return pts;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final points = _points;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(pal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.resultsTrendTitle,
              style: AppTextStyles.labelLarge
                  .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
          const SizedBox(height: 2),
          Text(l10n.resultsTrendSubtitle(points.length),
              style: AppTextStyles.caption.copyWith(color: pal.ink3)),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: points.length < 2
                ? Center(
                    child: Text(l10n.noResultsYet,
                        style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3)))
                : LineChart(_chartData(points, pal)),
          ),
        ],
      ),
    );
  }

  LineChartData _chartData(List<({DateTime date, int score})> points, StudentPalette pal) {
    final spots = [
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].score.toDouble()),
    ];
    return LineChartData(
      minY: 0,
      maxY: 100,
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (_) => FlLine(color: pal.border, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            interval: 25,
            getTitlesWidget: (v, meta) => Text('${v.toInt()}%',
                style: AppTextStyles.caption.copyWith(color: pal.ink3)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= points.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(DateFormat('dd.MM').format(points[i].date.toLocal()),
                    style: AppTextStyles.caption.copyWith(color: pal.ink3)),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots
              .map((s) => LineTooltipItem(
                  '${s.y.toInt()}%',
                  AppTextStyles.labelMedium.copyWith(color: Colors.white)))
              .toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppColors.secondary,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.secondary.withValues(alpha: 0.25),
                AppColors.secondary.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Per-subject average score, computed client-side from `recent_results`'
/// `subject` + `score` fields — the only per-subject signal this app's
/// model exposes (no vocab_cor/vocab_tot-style breakdown exists anywhere
/// in RecentResult/the /my-profile/ response, so nothing is fabricated to
/// fill that gap).
class _SubjectBreakdownCard extends StatelessWidget {
  final List<RecentResult> results;

  const _SubjectBreakdownCard({required this.results});

  Map<String, List<int>> get _bySubject {
    final map = <String, List<int>>{};
    for (final r in results) {
      if (r.score == null || r.subject.isEmpty) continue;
      map.putIfAbsent(r.subject.toLowerCase(), () => []).add(r.score!);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final bySubject = _bySubject;
    final subjects = bySubject.keys.toList()..sort();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(pal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.subjectPerformanceTitle,
              style: AppTextStyles.labelLarge
                  .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
          const SizedBox(height: 16),
          if (subjects.isEmpty)
            Text(l10n.noResultsYet,
                style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3))
          else
            for (final s in subjects) ...[
              _SubjectRow(
                subject: s,
                label: _subjectLabel(l10n, s),
                avgScore:
                    (bySubject[s]!.reduce((a, b) => a + b) / bySubject[s]!.length)
                        .round(),
              ),
              if (s != subjects.last) const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  final String subject;
  final String label;
  final int avgScore;

  const _SubjectRow(
      {required this.subject, required this.label, required this.avgScore});

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final color = _gradeColor(avgScore);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        subjectBadge(subject),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text(label,
                          style: AppTextStyles.bodyMedium.copyWith(
                              color: pal.ink1, fontWeight: FontWeight.w600))),
                  Text('$avgScore%',
                      style: AppTextStyles.labelLarge
                          .copyWith(fontWeight: FontWeight.w800, color: pal.ink1)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: AppRadii.roundedFull,
                child: LinearProgressIndicator(
                  value: avgScore / 100,
                  minHeight: 6,
                  backgroundColor: pal.border,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _ScoreRing(pct: avgScore / 100, color: color, size: 32),
      ],
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final double pct;
  final Color color;
  final double size;

  const _ScoreRing({required this.pct, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: pct.clamp(0, 1),
        strokeWidth: size * 0.12,
        backgroundColor: pal.border,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// Search box + subject chips (chips are built from the *actual* distinct
/// subjects present in `results` — never a hardcoded list) + a single sort
/// dropdown. The mockup shows two separate sort dropdowns (date / score);
/// merged into one 3-option dropdown here — same filtering power, smaller
/// diff. Add a second control back if product wants both visible at once.
class _FilterBar extends StatelessWidget {
  final List<String> subjects;
  final String? subjectFilter;
  final _SortMode sort;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onSubjectChanged;
  final ValueChanged<_SortMode> onSortChanged;

  const _FilterBar({
    required this.subjects,
    required this.subjectFilter,
    required this.sort,
    required this.onQueryChanged,
    required this.onSubjectChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          height: 42,
          child: TextField(
            onChanged: onQueryChanged,
            style: AppTextStyles.bodyMedium.copyWith(color: pal.ink1),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: pal.ink3),
              hintText: l10n.searchResultsHint,
              hintStyle: AppTextStyles.bodyMedium.copyWith(color: pal.ink3),
              filled: true,
              fillColor: pal.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: pal.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: pal.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.secondary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
        _subjectChip(context, pal, null, l10n.allSubjects),
        for (final s in subjects) _subjectChip(context, pal, s, _subjectLabel(l10n, s)),
        _sortDropdown(l10n, pal),
      ],
    );
  }

  Widget _subjectChip(
      BuildContext context, StudentPalette pal, String? value, String label) {
    final active = subjectFilter == value;
    return GestureDetector(
      onTap: () => onSubjectChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.secondaryMuted : pal.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? AppColors.secondary : pal.border),
        ),
        child: Text(label,
            style: AppTextStyles.labelMedium.copyWith(
                color: active ? AppColors.secondary : pal.ink2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  Widget _sortDropdown(AppLocalizations l10n, StudentPalette pal) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.border),
      ),
      alignment: Alignment.center,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_SortMode>(
          value: sort,
          isDense: true,
          icon: Icon(Icons.unfold_more_rounded, size: 16, color: pal.ink3),
          style: AppTextStyles.labelMedium.copyWith(color: pal.ink1),
          dropdownColor: pal.surface,
          items: [
            DropdownMenuItem(value: _SortMode.newest, child: Text(l10n.sortNewestFirst)),
            DropdownMenuItem(value: _SortMode.oldest, child: Text(l10n.sortOldestFirst)),
            DropdownMenuItem(
                value: _SortMode.highestScore, child: Text(l10n.sortHighestScore)),
          ],
          onChanged: (v) {
            if (v != null) onSortChanged(v);
          },
        ),
      ),
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  final List<RecentResult> results;
  // Whether the student has any results at all, before search/subject
  // filtering — distinguishes a brand-new student (genuine empty state)
  // from a filter/search that simply matched nothing (see finding #5).
  final bool hasAnyResults;
  final Set<RecentResult> pdfKeys;
  final ValueChanged<RecentResult> onDownloadPdf;
  final Set<RecentResult> breakdownKeys;
  final ValueChanged<RecentResult> onViewBreakdown;

  const _ResultsGrid(
      {required this.results,
      required this.hasAnyResults,
      required this.pdfKeys,
      required this.onDownloadPdf,
      required this.breakdownKeys,
      required this.onViewBreakdown});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (results.isEmpty) {
      final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: _cardDecoration(pal),
        child: Text(hasAnyResults ? l10n.noFilterMatches : l10n.noResultsYet,
            style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3)),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 14.0;
      final twoCol = constraints.maxWidth >= 640;
      final cardWidth = twoCol ? (constraints.maxWidth - gap) / 2 : constraints.maxWidth;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final r in results)
            SizedBox(
              width: cardWidth,
              child: _ResultCard(
                result: r,
                generatingPdf: pdfKeys.contains(r),
                onDownloadPdf: () => onDownloadPdf(r),
                loadingBreakdown: breakdownKeys.contains(r),
                onViewBreakdown: () => onViewBreakdown(r),
              ),
            ),
        ],
      );
    });
  }
}

/// A single result card — real score/date/subject from [result], plus a
/// "Подробный разбор" button that fetches `GET /results/<id>/breakdown/`
/// on tap (see `_StudentResultsScreenState._viewBreakdown`). A 404 (legacy
/// result with no breakdown data, or not this student's) shows a small
/// snackbar rather than opening anything — never an app error.
class _ResultCard extends StatelessWidget {
  final RecentResult result;
  final bool generatingPdf;
  final VoidCallback onDownloadPdf;
  final bool loadingBreakdown;
  final VoidCallback onViewBreakdown;

  const _ResultCard(
      {required this.result,
      required this.generatingPdf,
      required this.onDownloadPdf,
      required this.loadingBreakdown,
      required this.onViewBreakdown});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final score = result.score;
    final dateStr = result.submittedAt != null
        ? DateFormat('dd.MM.yyyy').format(result.submittedAt!.toLocal())
        : '';
    final metaLine =
        [_subjectLabel(l10n, result.subject), dateStr].where((s) => s.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(pal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              subjectBadge(result.subject),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyLarge
                            .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
                    if (metaLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(metaLine,
                          style: AppTextStyles.caption.copyWith(color: pal.ink3)),
                    ],
                  ],
                ),
              ),
              if (score != null) ...[
                const SizedBox(width: 8),
                Text('$score%',
                    style: AppTextStyles.titleMedium
                        .copyWith(fontWeight: FontWeight.w800, color: pal.ink1)),
                const SizedBox(width: 8),
                _ScoreRing(pct: score / 100, color: _gradeColor(score), size: 36),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (score != null)
            ClipRRect(
              borderRadius: AppRadii.roundedFull,
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 6,
                backgroundColor: pal.border,
                valueColor: AlwaysStoppedAnimation(_gradeColor(score)),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (score != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _gradeColor(score).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_gradeLabel(l10n, score),
                      style: AppTextStyles.caption
                          .copyWith(color: _gradeColor(score), fontWeight: FontWeight.w700)),
                ),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: loadingBreakdown ? null : onViewBreakdown,
                    icon: loadingBreakdown
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.visibility_outlined, size: 16),
                    label: Text(l10n.viewBreakdownButton,
                        style: AppTextStyles.labelMedium.copyWith(color: pal.ink1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: pal.ink1,
                      side: BorderSide(color: pal.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: generatingPdf ? null : onDownloadPdf,
                    icon: generatingPdf
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_download_outlined, size: 16),
                    label: Text(l10n.downloadPdfButton,
                        style: AppTextStyles.labelMedium.copyWith(color: pal.ink1)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: pal.ink1,
                      side: BorderSide(color: pal.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for `_ResultCard`'s "Подробный разбор" button — a
/// scrollable aggregate breakdown (bobs/topics/units/parts, whichever are
/// non-empty per [ResultBreakdown]) plus, when [ResultBreakdown.hasQuestionDetail]
/// is true, a per-question list (text + selected vs correct answer,
/// correct/incorrect color-coded via the same [AppColors.success]/[AppColors.error]
/// pair `_gradeColor` above already uses for score coloring). Deliberately a
/// single scrollable sheet, not a new route — this is a read-only detail
/// view, not a flow.
class _BreakdownSheet extends StatelessWidget {
  final RecentResult result;
  final ResultBreakdown breakdown;

  const _BreakdownSheet({required this.result, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: pal.border, borderRadius: AppRadii.roundedFull),
              ),
            ),
            Text(result.title,
                style: AppTextStyles.titleMedium
                    .copyWith(fontWeight: FontWeight.w800, color: pal.ink1)),
            const SizedBox(height: 4),
            Text(l10n.viewBreakdownButton,
                style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3)),
            const SizedBox(height: 16),
            if (breakdown.bobs.isNotEmpty)
              _breakdownSection(pal, l10n.breakdownBobsTitle, breakdown.bobs,
                  (m) => '${m['bob']}-BOB — ${m['name'] ?? ''}'),
            if (breakdown.topics.isNotEmpty)
              _breakdownSection(pal, l10n.breakdownTopicsTitle, breakdown.topics,
                  (m) => (m['name'] ?? '').toString()),
            if (breakdown.units.isNotEmpty)
              _breakdownSection(pal, l10n.breakdownUnitsTitle, breakdown.units,
                  (m) => 'Unit ${m['unit']}'),
            if (breakdown.parts.isNotEmpty)
              _breakdownSection(pal, l10n.breakdownPartsTitle, breakdown.parts,
                  (m) => (m['part'] ?? '').toString()),
            const SizedBox(height: 8),
            Text(l10n.breakdownQuestionsTitle,
                style: AppTextStyles.labelLarge
                    .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
            const SizedBox(height: 8),
            if (!breakdown.hasQuestionDetail || breakdown.questions.isEmpty)
              Text(l10n.breakdownNoQuestionDetailNote,
                  style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3))
            else
              for (final q in breakdown.questions) _questionTile(l10n, pal, q),
          ],
        ),
      ),
    );
  }

  Widget _breakdownSection(StudentPalette pal, String title,
      List<Map<String, dynamic>> items, String Function(Map<String, dynamic>) label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTextStyles.labelLarge
                  .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
          const SizedBox(height: 8),
          for (final m in items) _breakdownRow(pal, label(m), m),
        ],
      ),
    );
  }

  Widget _breakdownRow(StudentPalette pal, String label, Map<String, dynamic> m) {
    final correct = (m['correct'] as num?)?.toInt() ?? 0;
    final total = (m['total'] as num?)?.toInt() ?? 0;
    final pct = (m['pct'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: AppTextStyles.bodyMedium.copyWith(color: pal.ink2))),
          Text('$correct/$total ($pct%)',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: pal.ink1, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _questionTile(AppLocalizations l10n, StudentPalette pal, QuestionBreakdownItem q) {
    final color = q.isCorrect ? AppColors.success : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppRadii.roundedMd,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(q.isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(q.questionText,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: pal.ink1, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${l10n.breakdownYourAnswer}: ${q.selectedLabel(l10n.breakdownNoAnswer)}',
              style: AppTextStyles.caption.copyWith(color: pal.ink2)),
          if (!q.isCorrect) ...[
            const SizedBox(height: 2),
            Text('${l10n.breakdownCorrectAnswer}: ${q.correctLabel()}',
                style: AppTextStyles.caption.copyWith(color: pal.ink2)),
          ],
        ],
      ),
    );
  }
}

/// "Быстрые действия" + "Последние отчеты" side panel. Only one real quick
/// action exists (refresh) — the mockup's "Скачать все отчеты" (ZIP) and
/// "Средние баллы" duplicate-of-the-subjects-card items were dropped rather
/// than wired to a fabricated bulk-export/duplicate view; see file header.
class _SidePanel extends StatelessWidget {
  final List<RecentResult> results;
  final Set<RecentResult> pdfKeys;
  final ValueChanged<RecentResult> onDownloadPdf;
  final VoidCallback onRefresh;

  const _SidePanel({
    required this.results,
    required this.pdfKeys,
    required this.onDownloadPdf,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(pal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.quickActionsTitle,
                  style: AppTextStyles.labelLarge
                      .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: AppRadii.roundedMd,
                onTap: onRefresh,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                            color: AppColors.primaryMuted, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child:
                            const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.refreshResultsAction,
                                style: AppTextStyles.labelLarge.copyWith(color: pal.ink1)),
                            Text(l10n.refreshResultsActionDesc,
                                style: AppTextStyles.caption.copyWith(color: pal.ink3)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDecoration(pal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.recentResultsTitle,
                  style: AppTextStyles.labelLarge
                      .copyWith(fontWeight: FontWeight.w700, color: pal.ink1)),
              const SizedBox(height: 12),
              if (results.isEmpty)
                Text(l10n.noResultsYet,
                    style: AppTextStyles.bodyMedium.copyWith(color: pal.ink3))
              else
                for (final r in results.take(5)) _reportRow(r, pal),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reportRow(RecentResult r, StudentPalette pal) {
    final dateStr =
        r.submittedAt != null ? DateFormat('dd.MM.yyyy').format(r.submittedAt!.toLocal()) : '';
    final generating = pdfKeys.contains(r);
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
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: pal.ink1, fontWeight: FontWeight.w600)),
                if (dateStr.isNotEmpty)
                  Text(dateStr, style: AppTextStyles.caption.copyWith(color: pal.ink3)),
              ],
            ),
          ),
          IconButton(
            icon: generating
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.file_download_outlined, size: 18, color: pal.ink2),
            onPressed: generating ? null : () => onDownloadPdf(r),
          ),
        ],
      ),
    );
  }
}

/// Simple standalone score-summary PDF (score, subject, date, grade label)
/// for a single historical [RecentResult].
///
/// SCOPING NOTE: `features/result/pdf_report.dart`'s `PdfReport.generate`
/// (the app's existing "per-topic breakdown + AI summary" generator) was
/// evaluated for reuse but requires a `TestPackage` (subject question
/// counts) and a `TestResult` (raw math/eng sub-scores) plus a live
/// `wrongAnswers` list — all in-memory objects that only exist right after
/// submitting a test. `RecentResult` (what `/my-profile/` returns for
/// historical results) carries none of that, so reusing it would mean
/// fabricating fake package/result/wrong-answer data or a disproportionate
/// backend+model rewrite to fetch it. This standalone generator covers the
/// "Скачать PDF отчет" button with only what's genuinely known.
class _ResultPdf {
  static Future<File> generate({
    required StudentSession session,
    required RecentResult result,
    required AppLocalizations l10n,
  }) async {
    final doc = pw.Document(title: 'Natija - ${result.title}');
    final baseFontData = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/Inter-Bold.ttf');
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(baseFontData),
      bold: pw.Font.ttf(boldFontData),
    );
    final score = result.score;
    final dateStr = result.submittedAt != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(result.submittedAt!.toLocal())
        : '—';
    final gradeColor = score != null
        ? PdfColor.fromInt(_gradeColor(score).toARGB32())
        : const PdfColor.fromInt(0xFF9CA3AF);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 36),
      theme: theme,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(result.title,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text(session.studentName,
              style: const pw.TextStyle(fontSize: 13, color: PdfColor.fromInt(0xFF52525B))),
          pw.SizedBox(height: 24),
          pw.Row(children: [
            pw.Text('${l10n.subjectLabel}: ', style: const pw.TextStyle(fontSize: 13)),
            pw.Text(_subjectLabel(l10n, result.subject),
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ]),
          pw.SizedBox(height: 8),
          pw.Text(dateStr,
              style: const pw.TextStyle(fontSize: 13, color: PdfColor.fromInt(0xFF52525B))),
          pw.SizedBox(height: 24),
          pw.Container(
            padding: const pw.EdgeInsets.all(20),
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFAFAFA),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(children: [
              pw.Text(score != null ? '$score%' : '—',
                  style: pw.TextStyle(
                      fontSize: 36, fontWeight: pw.FontWeight.bold, color: gradeColor)),
              if (score != null) ...[
                pw.SizedBox(height: 4),
                pw.Text(_gradeLabel(l10n, score), style: const pw.TextStyle(fontSize: 14)),
              ],
            ]),
          ),
        ],
      ),
    ));

    final dir = await getApplicationDocumentsDirectory();
    final safeName = result.title.toLowerCase().replaceAll(RegExp(r'[^\w]+'), '_');
    final tag = (result.submittedAt ?? DateTime.now()).toIso8601String().substring(0, 10);
    final file = File('${dir.path}/Natija_${safeName}_$tag.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }
}
