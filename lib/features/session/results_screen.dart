// lib/features/session/results_screen.dart
//
// Minimal "all results" screen for the self-login flow (F4 of the
// MyTestsScreen redesign) — resolves the two mockup dead-ends (sidebar
// "Результаты" item + "Посмотреть все результаты" panel button) without
// building a full history/detail feature. Sourced from the same
// `GET /my-profile/` endpoint MyTestsScreen already uses (`recent_results`,
// capped at 10 server-side) — deliberately NOT paginated, per plan: "start
// simple, unpaginated".
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';

class ResultsScreen extends StatefulWidget {
  final StudentSession session;

  const ResultsScreen({super.key, required this.session});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _loading = true;
  List<RecentResult>? _results; // null = fetch failed/offline, never fabricated

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await api.fetchMyProfile(authToken: widget.session.token);
      if (!mounted) return;
      final results = profile != null
          ? RecentResult.listFromJson(profile['recent_results'])
          : null;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (e) {
      // Malformed payload (e.g. a non-Map list element) — same treatment as
      // fetch failure: show retry UI, never hang on a spinner forever.
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.ink1),
                    onPressed: () => context.pop(),
                  ),
                  Text(l10n.resultsScreenTitle,
                      style: AppTextStyles.titleLarge
                          .copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Expanded(child: _body(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Fetch failed/offline — hide, never show fabricated/zeroed results.
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
              Text(l10n.loadFailed,
                  textAlign: TextAlign.center,
                  style:
                      AppTextStyles.bodyMedium.copyWith(color: AppColors.ink2)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: Text(l10n.retryCheck)),
            ],
          ),
        ),
      );
    }
    if (_results!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.noResultsYet,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.ink3)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        itemCount: _results!.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _ResultRow(result: _results![i]),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final RecentResult result;

  const _ResultRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final dateStr = result.submittedAt != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(result.submittedAt!.toLocal())
        : '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.roundedLg,
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
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.title,
                    style: AppTextStyles.labelLarge
                        .copyWith(fontWeight: FontWeight.w700)),
                if (dateStr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(dateStr,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.ink3)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: AppColors.successMuted,
              borderRadius: AppRadii.roundedMd,
            ),
            child: Text(result.score != null ? '${result.score}%' : '—',
                style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.success, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
