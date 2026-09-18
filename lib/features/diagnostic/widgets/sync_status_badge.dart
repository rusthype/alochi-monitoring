// lib/features/diagnostic/widgets/sync_status_badge.dart
//
// Compact corner badge showing the diagnostic offline-sync state: green
// "synced", amber spinner "syncing", or red pending-count when answers are
// still queued locally (see SyncService/OfflineQueue). Tapping it forces an
// immediate flush attempt. Visual language borrowed from
// DiagnosticOfflineBadge (diagnostic_widgets.dart) but circular/compact
// since this sits in a screen corner, not inline in content.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/db/offline_queue.dart';
import '../../../core/sync/sync_service.dart';
import '../../../shared/theme/app_theme.dart';

class SyncStatusBadge extends StatefulWidget {
  const SyncStatusBadge({
    super.key,
    this.pendingCountOverride,
    this.flushNowOverride,
  });

  /// Test-only overrides — default to the real OfflineQueue/SyncService
  /// calls, mirroring the *Override convention used in
  /// diagnostic_test_runner_screen.dart.
  final Future<int> Function()? pendingCountOverride;
  final Future<void> Function()? flushNowOverride;

  @override
  State<SyncStatusBadge> createState() => _SyncStatusBadgeState();
}

class _SyncStatusBadgeState extends State<SyncStatusBadge> {
  int _pending = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshPending();
    _timer =
        Timer.periodic(const Duration(seconds: 2), (_) => _refreshPending());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPending() async {
    try {
      final pending = widget.pendingCountOverride != null
          ? await widget.pendingCountOverride!()
          : await OfflineQueue.pendingCount() +
              await OfflineQueue.pendingLocalCount();
      if (mounted) setState(() => _pending = pending);
    } catch (e) {
      // Non-fatal: this is a UI indicator, not the sync path itself (see
      // SyncService, which does surface real flush failures). Keeps
      // whatever count was last known good instead of crashing the screen.
      debugPrint('SyncStatusBadge._refreshPending error: $e');
    }
  }

  Future<void> _onTap(String message) async {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    await (widget.flushNowOverride ?? SyncService.instance.flushNow)();
    await _refreshPending();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<bool>(
      valueListenable: SyncService.instance.flushing,
      builder: (context, flushing, _) {
        final Color color;
        final Widget icon;
        final String message;
        if (flushing) {
          color = Colors.amber;
          icon = const SizedBox(
            width: 14,
            height: 14,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
          );
          message = l10n.syncStatusSyncing;
        } else if (_pending > 0) {
          color = AppColors.error;
          icon = Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 20, color: AppColors.error),
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  constraints:
                      const BoxConstraints(minWidth: 14, minHeight: 14),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$_pending',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          );
          message = l10n.syncPendingCount(_pending);
        } else {
          color = AppColors.success;
          icon = const Icon(Icons.check_circle_rounded,
              size: 20, color: AppColors.success);
          message = l10n.syncStatusSynced;
        }
        return Tooltip(
          message: message,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _onTap(message),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: icon,
            ),
          ),
        );
      },
    );
  }
}
