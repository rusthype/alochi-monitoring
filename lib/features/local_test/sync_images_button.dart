import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../core/cache/image_cache_manager.dart';
import '../../core/db/offline_queue.dart';
import '../../core/sync/sync_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/button_shape.dart';
import '../../shared/widgets/pending_results_chip.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

class SyncImagesButton extends StatefulWidget {
  const SyncImagesButton({super.key, this.requeueOverride, this.flushOverride});

  /// Test seams for the held/pending results resend (see
  /// [resendHeldResults]); when [flushOverride] is set the queue refresh is
  /// skipped, like PendingResultsChip's overrides.
  final Future<int> Function()? requeueOverride;
  final Future<SyncFlushOutcome> Function()? flushOverride;
  @override
  State<SyncImagesButton> createState() => _SyncImagesButtonState();
}

class _SyncImagesButtonState extends State<SyncImagesButton> {
  bool _syncing = false;
  double _progress = 0;
  int _total = 0;
  int _done = 0;

  /// Same as the pending-results chip's "send now": held/rejected results get
  /// another try along with the pending ones. No-op when both counts are 0.
  Future<void> _resendResults() async {
    final before = OfflineQueue.pending.value.count;
    if (before <= 0 && OfflineQueue.rejected.value <= 0) return;
    final outcome = await resendHeldResults(
        requeue: widget.requeueOverride, flush: widget.flushOverride);
    if (widget.flushOverride == null) await OfflineQueue.refreshPending();
    if (!mounted) return;
    showResendOutcome(context, outcome,
        before: before, left: OfflineQueue.pending.value.count);
  }

  Future<void> _startSync() async {
    unawaited(_resendResults());
    setState(() {
      _syncing = true;
      _progress = 0;
      _total = 0;
      _done = 0;
    });

    try {
      final dataStr = await rootBundle.loadString('assets/questions.json');
      final data = jsonDecode(dataStr) as Map;

      final Set<String> urls = {};

      for (final grade in data.keys) {
        final variants = data[grade] as Map;
        for (final v in variants.keys) {
          final qList = variants[v] as List;
          for (final q in qList) {
            if (q['i'] != null && q['i'].toString().isNotEmpty) {
              final u = MonitoringApi.fixImageUrl(q['i'].toString());
              if (u.isNotEmpty) urls.add(u);
            }
            if (q['oi'] != null) {
              for (final oi in (q['oi'] as List)) {
                if (oi != null && oi.toString().isNotEmpty) {
                  final u = MonitoringApi.fixImageUrl(oi.toString());
                  if (u.isNotEmpty) urls.add(u);
                }
              }
            }
          }
        }
      }

      setState(() => _total = urls.length);
      final cacheMgr = AlochiImageCacheManager();

      for (final url in urls) {
        if (!mounted) return;
        try {
          // Bu buyruq rasmni serverdan olib doimiy xotiraga yozadi
          await cacheMgr.downloadFile(url);
        } catch (_) {}
        setState(() {
          _done++;
          _progress = _done / _total;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.syncCompleteMsg('$_done')),
              backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.errorOccurred + e.toString()),
              backgroundColor: AppColors.err),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_syncing) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(AppLocalizations.of(context)!.offlineImagesLoading,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.ink2,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.brand),
            ),
          ),
          const SizedBox(height: 6),
          Text(
              AppLocalizations.of(context)!
                  .savedOutOfTotal('$_done', '$_total'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.ink3, fontSize: 11)),
        ],
      );
    }

    return TextButton.icon(
      onPressed: _startSync,
      icon: const Icon(Icons.cloud_download_rounded, size: 16),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(AppLocalizations.of(context)!.syncImagesOfflineButton),
      ),
      style: bottomChipButtonStyle(
        foreground: AppColors.brand,
        fontSize: 13,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}
