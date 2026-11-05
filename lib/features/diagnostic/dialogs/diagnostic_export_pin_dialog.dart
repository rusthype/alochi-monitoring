// lib/features/diagnostic/dialogs/diagnostic_export_pin_dialog.dart
//
// PIN gate for DiagnosticHistoryScreen's "Yuklab olish (ZIP)" export button.
// The PIN belongs to the school being exported: the caller passes [verify]
// (server check / cached hash via `verifyDiagnosticPin` for that school id),
// and this dialog only maps the result to the same messages the kiosk PIN
// screen shows. No PIN is stored or logged here.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_pin_verifier.dart';

/// Shows the PIN dialog. Resolves to `true` when [verify] accepted the PIN,
/// `null` if the operator cancelled/dismissed it.
Future<bool?> showDiagnosticExportPinDialog(
  BuildContext context, {
  required Future<DiagnosticPinResult> Function(String pin) verify,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => DiagnosticExportPinDialog(verify: verify),
  );
}

class DiagnosticExportPinDialog extends StatefulWidget {
  final Future<DiagnosticPinResult> Function(String pin) verify;

  const DiagnosticExportPinDialog({super.key, required this.verify});

  @override
  State<DiagnosticExportPinDialog> createState() =>
      _DiagnosticExportPinDialogState();
}

class _DiagnosticExportPinDialogState
    extends State<DiagnosticExportPinDialog> {
  final _pinCtrl = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_checking) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _checking = true;
      _error = null;
    });
    DiagnosticPinResult result;
    try {
      result = await widget.verify(_pinCtrl.text.trim());
    } catch (_) {
      // Never leave the button disabled if the verifier throws unexpectedly.
      result = DiagnosticPinResult.error;
    }
    if (!mounted) return;
    if (result == DiagnosticPinResult.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _error = switch (result) {
        DiagnosticPinResult.throttled => l10n.tooManyAttempts,
        DiagnosticPinResult.noInternet => l10n.connectionError,
        DiagnosticPinResult.error => l10n.serverErrorRetry,
        _ => l10n.incorrectPin,
      };
    });
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
          onPressed: _checking ? null : _confirm,
          child: Text(l10n.confirmBtn,
              style: const TextStyle(color: AppColors.brand)),
        ),
      ],
    );
  }
}
