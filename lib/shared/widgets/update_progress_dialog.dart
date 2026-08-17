// lib/shared/widgets/update_progress_dialog.dart
// Compact in-app "Update available" dialog: confirm -> downloading (live
// progress) -> error (retry / open-in-browser). Never opens the system
// browser on its own — only the explicit "Open in browser" button does,
// on direct user tap. Mirrors the app's existing AlertDialog convention
// (see exit_confirmation_scope.dart, package_screen.dart's _confirmLogout).
import 'package:flutter/material.dart';
import '../../core/services/update_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/app_localizations.dart';

enum _UpdateDialogStage { confirm, downloading, error }

/// Shows the in-app update dialog for [info]. Non-dismissible while a
/// download is in progress (no cancellation support — UpdateService offers
/// no cancellation hook, and the confirm/error stages already let the user
/// back out before/after an attempt).
Future<void> showUpdateProgressDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _UpdateProgressDialog(info: info),
  );
}

class _UpdateProgressDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateProgressDialog({required this.info});

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  _UpdateDialogStage _stage = _UpdateDialogStage.confirm;
  double _progress = 0;
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _stage = _UpdateDialogStage.downloading;
      _progress = 0;
      _error = null;
    });
    final result = await UpdateService.instance.downloadAndInstallUpdate(
      widget.info,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    if (result.success) {
      // Practically unreachable — the success path calls exit(0) before
      // returning. Kept for type-safety/completeness.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _stage = _UpdateDialogStage.error;
      _error = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: _stage != _UpdateDialogStage.downloading,
      child: AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: AppRadii.roundedXl),
        title: Text(
          '${l10n.newVersionAvailable} v${widget.info.latestVersion}',
          style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 340,
          child: switch (_stage) {
            _UpdateDialogStage.confirm => Text(l10n.updateConfirmBody),
            _UpdateDialogStage.downloading => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      minHeight: 6,
                      backgroundColor: AppColors.brand.withValues(alpha: .1),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.brand),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('${(_progress * 100).toInt()}%'),
                ],
              ),
            _UpdateDialogStage.error => Text(
                _error ?? l10n.updateDownloadFailedMsg,
                style: TextStyle(color: AppColors.err),
              ),
          },
        ),
        actions: switch (_stage) {
          _UpdateDialogStage.confirm => [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: _startDownload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                ),
                child: Text(l10n.updateNowBtn),
              ),
            ],
          _UpdateDialogStage.downloading => const [],
          _UpdateDialogStage.error => [
              TextButton(
                onPressed: () => UpdateService.instance.openReleasePage(),
                child: Text(l10n.openInBrowserBtn),
              ),
              ElevatedButton(
                onPressed: _startDownload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                ),
                child: Text(l10n.retry),
              ),
            ],
        },
      ),
    );
  }
}
