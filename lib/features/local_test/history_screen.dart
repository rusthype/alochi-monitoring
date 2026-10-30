import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/db/history_db.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/history_card.dart';
import '../../shared/widgets/pill_chip.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

class HistoryScreen extends StatefulWidget {
  /// True when hosted as a tab body inside OfflineHistoryHubScreen
  /// (Task 4) — skips this screen's own Scaffold+AppBar (the hub provides
  /// one shared AppBar+TabBar for both tabs) while keeping every other
  /// internal behavior identical. Defaults to false so both existing
  /// callers (app_router.dart's old direct '/history' route usage,
  /// command_palette.dart's quick preview) keep compiling/behaving
  /// unchanged if ever reused standalone.
  final bool embedded;

  /// Test-only overrides — default to the real HistoryDb calls.
  final Future<List<Map<String, dynamic>>> Function()? getHistoryOverride;
  final Future<void> Function()? clearOverride;

  const HistoryScreen({
    super.key,
    this.embedded = false,
    this.getHistoryOverride,
    this.clearOverride,
  });
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await (widget.getHistoryOverride ?? HistoryDb.getHistory)();
    if (mounted) {
      setState(() {
        _records = res;
        _loading = false;
      });
    }
  }

  Future<void> _clear() async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(AppLocalizations.of(context)!.clearHistoryTitle,
            style: const TextStyle(color: AppColors.ink1)),
        content: Text(AppLocalizations.of(context)!.clearHistoryConfirm,
            style: const TextStyle(color: AppColors.ink2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(AppLocalizations.of(context)!.noWord,
                  style: const TextStyle(color: AppColors.ink3))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(AppLocalizations.of(context)!.yesDelete,
                  style: const TextStyle(color: AppColors.err))),
        ],
      ),
    );
    if (conf == true) {
      setState(() => _loading = true);
      await (widget.clearOverride ?? HistoryDb.clearHistory)();
      await _load();
    }
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.brand));
    }
    if (_records.isEmpty) return HistoryEmpty(l10n.noHistoryYet);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final r = _records[i];
        final date =
            DateTime.fromMillisecondsSinceEpoch(r['date_taken'] as int);
        final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(date);
        final pct = r['total_pct'] as double;
        final tone = pct >= 60.0 ? AppColors.ok : AppColors.err;

        return HistoryCard(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: .1),
                  shape: BoxShape.circle,
                  border: Border.all(color: tone.withValues(alpha: .25)),
                ),
                child: Center(
                  child: Text(
                    '${pct.toInt()}%',
                    style: TextStyle(
                      color: tone,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r['first_name']} ${r['last_name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.ink1,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        HistoryTag('${l10n.schoolLabel}: ${r['school']}',
                            icon: Icons.school_outlined),
                        HistoryTag(
                            '${l10n.groupGradeLabel}: ${r['grade_group']}',
                            icon: Icons.groups_outlined),
                        HistoryTag('${l10n.dateLabel}: $dateStr',
                            icon: Icons.event_outlined),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  HistoryTag('${l10n.mathShort}: ${r['math_score']}',
                      color: AppColors.brand),
                  const SizedBox(height: 6),
                  HistoryTag('${l10n.engShort}: ${r['eng_score']}',
                      color: AppColors.ok),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Quiet rounded "clear all" action (grey; red only on hover/press).
  Widget _clearChip(BuildContext context) => PillChip(
        label: AppLocalizations.of(context)!.clearHistoryTitle,
        tooltip: AppLocalizations.of(context)!.clearHistoryTitle,
        icon: Icons.delete_outline_rounded,
        hoverColor: AppColors.err,
        onPressed: _clear,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.bg,
        child: Column(
          children: [
            if (_records.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                    alignment: Alignment.centerRight,
                    child: _clearChip(context)),
              ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        title: Text(AppLocalizations.of(context)!.offlineHistoryTitle,
            style: const TextStyle(
                color: AppColors.ink1,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.ink1),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.err),
              tooltip: AppLocalizations.of(context)!.clearHistoryTitle,
              onPressed: _clear,
            )
        ],
      ),
      body: _buildBody(context),
    );
  }
}
