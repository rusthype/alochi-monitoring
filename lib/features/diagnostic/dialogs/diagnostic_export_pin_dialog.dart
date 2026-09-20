// lib/features/diagnostic/dialogs/diagnostic_export_pin_dialog.dart
//
// PIN gate for DiagnosticHistoryScreen's "Yuklab olish (ZIP)" export button.
// No school/session context is available at that screen (it's reached from
// a global login-screen button via OfflineHistoryHubScreen with no route
// args — see diagnostic_history_screen.dart), so this uses a NEW, dedicated
// hardcoded PIN rather than the per-school `kiosk_pin` field or the OTHER
// hardcoded '1234' admin-gate literal already used 4x elsewhere in this app
// (local_grade_screen.dart and 3 siblings) — deliberately kept separate.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

const String kDiagnosticExportPin = '0555';

/// Shows the PIN dialog. Resolves to `true` when the correct PIN was
/// entered and confirmed, `null` if the operator cancelled/dismissed it.
Future<bool?> showDiagnosticExportPinDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const DiagnosticExportPinDialog(),
  );
}

class DiagnosticExportPinDialog extends StatefulWidget {
  const DiagnosticExportPinDialog({super.key});

  @override
  State<DiagnosticExportPinDialog> createState() =>
      _DiagnosticExportPinDialogState();
}

class _DiagnosticExportPinDialogState
    extends State<DiagnosticExportPinDialog> {
  final _pinCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final l10n = AppLocalizations.of(context)!;
    if (_pinCtrl.text.trim() != kDiagnosticExportPin) {
      setState(() => _error = l10n.incorrectPin);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(l10n.diagnosticPinDialogTitle,
          style: const TextStyle(color: AppColors.ink1)),
      content: TextField(
        controller: _pinCtrl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, letterSpacing: 8),
        decoration: InputDecoration(
          counterText: '',
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel,
              style: const TextStyle(color: AppColors.ink3)),
        ),
        TextButton(
          onPressed: _confirm,
          child: Text(l10n.confirmBtn,
              style: const TextStyle(color: AppColors.brand)),
        ),
      ],
    );
  }
}
