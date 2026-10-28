// lib/shared/widgets/pending_results_chip.dart
//
// Teacher-visible "N natija yuborilmagan" chip for the login, group-select and
// student-roster screens. Hidden while the offline queue is empty; otherwise
// it says how many results (and how old the oldest) are still only on this PC
// and offers "Hozir yuborish" (SyncService.flushNowWithResult) with progress
// and a toast with the outcome. Same pill language as SyncStatusBadge, but a
// teacher-facing message instead of a student-facing badge.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/db/offline_queue.dart';
import '../../core/services/toast_service.dart';
import '../../core/sync/sync_service.dart';
import '../theme/app_theme.dart';

class PendingResultsChip extends StatefulWidget {
  const PendingResultsChip({
    super.key,
    this.pendingCountOverride,
    this.oldestAgeOverride,
    this.flushNowOverride,
  });

  /// Test-only overrides (same convention as SyncStatusBadge).
  final Future<int> Function()? pendingCountOverride;
  final Future<Duration?> Function()? oldestAgeOverride;
  final Future<SyncFlushOutcome> Function()? flushNowOverride;

  @override
  State<PendingResultsChip> createState() => _PendingResultsChipState();
}

class _PendingResultsChipState extends State<PendingResultsChip> {
  int _pending = 0;
  Duration? _oldest;
  bool _sending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<int> _refresh() async {
    try {
      final pending = widget.pendingCountOverride != null
          ? await widget.pendingCountOverride!()
          : await OfflineQueue.totalPendingCount();
      final oldest = pending <= 0
          ? null
          : widget.oldestAgeOverride != null
              ? await widget.oldestAgeOverride!()
              : await OfflineQueue.oldestPendingAge();
      if (mounted) {
        setState(() {
          _pending = pending;
          _oldest = oldest;
        });
      }
      return pending;
    } catch (e) {
      // A UI indicator, not the sync path: keep the last known state.
      debugPrint('PendingResultsChip._refresh: $e');
      return _pending;
    } finally {
      // A corrupt queue file was replaced at open: tell the teacher once.
      if (mounted && OfflineQueue.takeRecoveryNotice()) {
        ToastService.showError(
            context, AppLocalizations.of(context)!.queueDbRecoveredToast);
      }
    }
  }

  Future<void> _sendNow() async {
    if (_sending) return;
    final before = _pending;
    setState(() => _sending = true);
    SyncFlushOutcome? outcome;
    try {
      outcome = await (widget.flushNowOverride ??
          SyncService.instance.flushNowWithResult)();
    } catch (e) {
      debugPrint('PendingResultsChip: flush failed: $e');
    }
    final left = await _refresh();
    if (!mounted) return;
    setState(() => _sending = false);
    final l10n = AppLocalizations.of(context)!;
    final sent = before - left;
    if (outcome == SyncFlushOutcome.noNetwork) {
      ToastService.showError(context, l10n.pendingResultsNoNetworkToast);
    } else if (outcome == SyncFlushOutcome.busy) {
      ToastService.showInfo(context, l10n.syncStatusSyncing);
    } else if (sent > 0) {
      ToastService.showSuccess(context, l10n.pendingResultsSentToast(sent));
    } else if (left > 0) {
      // Nothing left the queue (server error / 429): results are safe, retry.
      ToastService.showError(context, l10n.pendingResultsFailedToast);
    }
  }

  String? _ageText(AppLocalizations l10n) {
    final d = _oldest;
    if (d == null) return null;
    if (d.inDays >= 1) return l10n.pendingResultsOldestDays(d.inDays);
    if (d.inHours >= 1) return l10n.pendingResultsOldestHours(d.inHours);
    return l10n.pendingResultsOldestMinutes(d.inMinutes);
  }

  @override
  Widget build(BuildContext context) {
    if (_pending <= 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final age = _ageText(l10n);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.amberBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_upload_outlined,
                size: 18, color: AppColors.amberDark),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pendingResultsChip(_pending),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.amberInk),
                  ),
                  if (age != null)
                    Text(
                      age,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.amberDark),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_sending)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.amberDark),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.syncStatusSyncing,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.amberDark),
                    ),
                  ],
                ),
              )
            else
              TextButton(
                onPressed: _sendNow,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.amberInk,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(l10n.pendingResultsSendNow),
              ),
          ],
        ),
      ),
    );
  }
}
