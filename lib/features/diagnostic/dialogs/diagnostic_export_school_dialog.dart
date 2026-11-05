// lib/features/diagnostic/dialogs/diagnostic_export_school_dialog.dart
//
// Chooser shown before the export PIN when the history holds several schools
// (or rows whose school could not be resolved). Unresolved rows are listed
// but disabled: they can never be exported.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_export_schools.dart';

Future<ExportSchool?> showDiagnosticExportSchoolDialog(
    BuildContext context, ExportSchools schools) {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<ExportSchool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(l10n.selectSchool,
          style: const TextStyle(color: AppColors.ink1)),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in schools.resolved)
              ListTile(
                title: Text(s.name,
                    style: const TextStyle(color: AppColors.ink1)),
                trailing: Text('${s.records.length}',
                    style: const TextStyle(color: AppColors.ink3)),
                onTap: () => Navigator.of(ctx).pop(s),
              ),
            if (schools.unresolvedCount > 0)
              ListTile(
                enabled: false,
                title: Text(
                    l10n.diagnosticExportUnresolvedTitle(
                        schools.unresolvedCount),
                    style: const TextStyle(color: AppColors.ink3)),
                subtitle: Text(l10n.diagnosticExportUnresolvedHint),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.cancel,
              style: const TextStyle(color: AppColors.ink3)),
        ),
      ],
    ),
  );
}
