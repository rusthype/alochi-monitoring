// lib/features/diagnostic/screens/diagnostic_finished_screen.dart
//
// Trivial thank-you screen — the results endpoint is staff-only, so no
// scores are shown here.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

class DiagnosticFinishedScreen extends StatelessWidget {
  const DiagnosticFinishedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    color: AppColors.successMuted,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.diagnosticFinishedTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.diagnosticFinishedSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: AppColors.ink2),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => context.go('/'),
                    child: Text(l10n.backBtn),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
