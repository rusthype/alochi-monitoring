// lib/shared/widgets/pending_results_chip.dart
//
// Teacher-visible "N natija yuborilmagan" chip for the login, group-select and
// student-roster screens. Hidden while the offline queue is empty; otherwise
// it says how many results (and how old the oldest) are still only on this PC
// and offers "Hozir yuborish" (SyncService.flushNowWithResult) with progress
// and a toast with the outcome. Same pill language as SyncStatusBadge, but a
// teacher-facing message instead of a student-facing badge.
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
    this.rejectedCountOverride,
  });

  /// Test-only overrides (same convention as SyncStatusBadge).
  final Future<int> Function()? pendingCountOverride;
  final Future<Duration?> Function()? oldestAgeOverride;
  final Future<SyncFlushOutcome> Function()? flushNowOverride;
  final Future<int> Function()? rejectedCountOverride;

  @override
  State<PendingResultsChip> createState() => _PendingResultsChipState();
}

class _PendingResultsChipState extends State<PendingResultsChip> {
  int _pending = 0;
  int _rejected = 0; // server refused them (attempt limit): kept, never retried
  Duration? _oldest;
  bool _sending = false;

  bool get _overridden => widget.pendingCountOverride != null;

  @override
  void initState() {
    super.initState();
    // Event-driven, no timer and no queue access of its own: the queue
    // publishes its size (OfflineQueue.pending) whenever rows are added /
    // sent / dropped, and SyncService keeps it in step every few seconds.
    OfflineQueue.pending.addListener(_onChanged);
    OfflineQueue.rejected.addListener(_onChanged);
    OfflineQueue.changes.addListener(_onChanged);
    SyncService.instance.flushing.addListener(_onChanged);
    if (_overridden) {
      _refresh();
    } else {
      final v = OfflineQueue.pending.value;
      _pending = v.count;
      _oldest = v.oldest;
      _rejected = OfflineQueue.rejected.value;
    }
    // The overlay for the toast exists after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _noticeIfAny());
  }

  @override
  void dispose() {
    OfflineQueue.pending.removeListener(_onChanged);
    OfflineQueue.rejected.removeListener(_onChanged);
    OfflineQueue.changes.removeListener(_onChanged);
    SyncService.instance.flushing.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    _refresh();
    _noticeIfAny();
  }

  /// A corrupt queue file was replaced at open: tell the teacher once.
  void _noticeIfAny() {
    if (mounted && OfflineQueue.takeRecoveryNotice()) {
      ToastService.showError(
          context, AppLocalizations.of(context)!.queueDbRecoveredToast);
    }
  }

  /// Returns the pending count after the refresh.
  Future<int> _refresh() async {
    try {
      final int pending;
      final Duration? oldest;
      var rejected = 0;
      if (_overridden) {
        rejected = await widget.rejectedCountOverride?.call() ?? 0;
        pending = await widget.pendingCountOverride!();
        oldest = pending <= 0 || widget.oldestAgeOverride == null
            ? null
            : await widget.oldestAgeOverride!();
      } else {
        final v = OfflineQueue.pending.value;
        pending = v.count;
        oldest = v.oldest;
        rejected = OfflineQueue.rejected.value;
      }
      if (mounted) {
        setState(() {
          _rejected = rejected;
          _pending = pending;
          _oldest = oldest;
        });
      }
      return pending;
    } catch (e) {
      // A UI indicator, not the sync path: keep the last known state.
      debugPrint('PendingResultsChip._refresh: $e');
      return _pending;
    }
  }

  Future<void> _sendNow() async {
    if (_sending) return;
    final before = _pending;
    setState(() => _sending = true);
    SyncFlushOutcome? outcome;
    try {
      // The teacher acts (e.g. granted another attempt): rejected results get
      // one more chance; a result the server still refuses is held again.
      if (!_overridden) await OfflineQueue.requeueRejected();
      outcome = await (widget.flushNowOverride ??
          SyncService.instance.flushNowWithResult)();
    } catch (e) {
      debugPrint('PendingResultsChip: flush failed: $e');
    }
    if (!_overridden) await OfflineQueue.refreshPending();
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
    if (_pending <= 0 && _rejected <= 0) return const SizedBox.shrink();
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
                  if (_pending > 0)
                    Text(
                      l10n.pendingResultsChip(_pending),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.amberInk),
                    ),
                  if (_rejected > 0)
                    Text(
                      l10n.pendingResultsRejected(_rejected),
                      style: TextStyle(
                          fontSize: _pending > 0 ? 11 : 13,
                          fontWeight:
                              _pending > 0 ? FontWeight.w400 : FontWeight.w700,
                          color: _pending > 0
                              ? AppColors.amberDark
                              : AppColors.amberInk),
                    ),
                  if (age != null && _pending > 0)
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
