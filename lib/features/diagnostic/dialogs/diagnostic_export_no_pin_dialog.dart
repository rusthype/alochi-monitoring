// lib/features/diagnostic/dialogs/diagnostic_export_no_pin_dialog.dart
//
// Shown instead of the PIN dialog when the chosen school has no PIN: the
// export is then unprotected, so the operator must confirm explicitly.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

Future<bool?> showDiagnosticExportNoPinConfirm(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(l10n.diagnosticExportZipButton,
          style: const TextStyle(color: AppColors.ink1)),
      content: Text(l10n.diagnosticExportNoPinConfirm,
          style: const TextStyle(color: AppColors.ink1)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.cancel,
              style: const TextStyle(color: AppColors.ink3)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.confirmBtn,
              style: const TextStyle(color: AppColors.brand)),
        ),
      ],
    ),
  );
}
