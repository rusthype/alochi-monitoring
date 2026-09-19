// lib/features/diagnostic/screens/diagnostic_history_screen.dart
//
// Task 4: per-ATTEMPT diagnostic history tab, hosted inside
// OfflineHistoryHubScreen alongside the existing (unmodified) HistoryScreen.
// No own AppBar/Scaffold — it's a TabBarView body, the hub provides the
// shared chrome.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/db/diagnostic_history_db.dart';
import '../../../core/sync/sync_service.dart';
import '../../../shared/theme/app_theme.dart';

enum DiagnosticHistoryFilter { all, sent, pending }

class DiagnosticHistoryScreen extends StatefulWidget {
  /// Test-only overrides — default to the real DB/sync calls, same
  /// convention as SyncStatusBadge's `pendingCountOverride`/
  /// `flushNowOverride`.
  final Future<List<Map<String, dynamic>>> Function()? getAllOverride;
  final Future<void> Function()? flushNowOverride;

  const DiagnosticHistoryScreen({
    super.key,
    this.getAllOverride,
    this.flushNowOverride,
  });

  @override
  State<DiagnosticHistoryScreen> createState() =>
      _DiagnosticHistoryScreenState();
}

class _DiagnosticHistoryScreenState extends State<DiagnosticHistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  bool _sending = false;
  DiagnosticHistoryFilter _filter = DiagnosticHistoryFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final getAll = widget.getAllOverride ?? DiagnosticHistoryDb.getAll;
    final res = await getAll();
    if (mounted) {
      setState(() {
        _records = res;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    switch (_filter) {
      case DiagnosticHistoryFilter.sent:
        return _records.where((r) => r['status'] == 'sent').toList();
      case DiagnosticHistoryFilter.pending:
        return _records.where((r) => r['status'] == 'pending').toList();
      case DiagnosticHistoryFilter.all:
        return _records;
    }
  }

  /// Per-row "Qayta yuborish" and the top "Barchasini yuborish" both reuse
  /// the app's existing generic full flush (SyncService.flushNow, already
  /// used by SyncStatusBadge) — a per-row-scoped retry isn't available
  /// anywhere in this codebase, and a full flush is fast/cheap enough that
  /// this acceptable simplification (per the feature brief) beats building
  /// new per-item retry plumbing.
  Future<void> _flushThenReload() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await (widget.flushNowOverride ?? SyncService.instance.flushNow)();
    } finally {
      await _load();
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filtered = _filtered;
    final hasPending = _records.any((r) => r['status'] == 'pending');
    return ColoredBox(
      color: AppColors.bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip(l10n.diagnosticHistoryFilterAll,
                            DiagnosticHistoryFilter.all),
                        const SizedBox(width: 8),
                        _chip(l10n.diagnosticHistoryFilterSent,
                            DiagnosticHistoryFilter.sent),
                        const SizedBox(width: 8),
                        _chip(l10n.diagnosticHistoryFilterPending,
                            DiagnosticHistoryFilter.pending),
                      ],
                    ),
                  ),
                ),
                if (hasPending) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _sending ? null : _flushThenReload,
                    icon: _sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: Text(l10n.diagnosticHistorySendAll),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.brand))
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          l10n.diagnosticHistoryNoRecords,
                          style: const TextStyle(
                              color: AppColors.ink2, fontSize: 16),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) =>
                            _row(context, l10n, filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, DiagnosticHistoryFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.brand.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        color: selected ? AppColors.brand : AppColors.ink2,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _row(
      BuildContext context, AppLocalizations l10n, Map<String, dynamic> r) {
    final date = DateTime.fromMillisecondsSinceEpoch(r['date_taken'] as int);
    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(date);
    final isSent = r['status'] == 'sent';
    final mathScore = r['math_score'];
    final engScore = r['english_score'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(Icons.circle,
                size: 12, color: isSent ? AppColors.ok : AppColors.err),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['student_name'] ?? ''}',
                    style: const TextStyle(
                        color: AppColors.ink1,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  '${l10n.schoolLabel}: ${r['school'] ?? ''} | ${l10n.groupGradeLabel}: ${r['class_label'] ?? ''}',
                  style: const TextStyle(color: AppColors.ink2, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text('${l10n.dateLabel}: $dateStr',
                    style:
                        const TextStyle(color: AppColors.ink3, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${l10n.mathShort}: ${mathScore ?? '-'}',
                  style: const TextStyle(
                      color: AppColors.brand,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              Text('${l10n.engShort}: ${engScore ?? '-'}',
                  style: const TextStyle(
                      color: AppColors.ok,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              if (!isSent)
                TextButton(
                  onPressed: _sending ? null : _flushThenReload,
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                  child: Text(l10n.diagnosticHistoryResendRow,
                      style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
