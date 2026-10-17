// lib/features/offline/offline_saved_screen.dart
//
// Shown instead of the score screen after a test in offline USB pack mode
// (decision 2: scoring happens only on the server, the pack carries no answer
// key). Deliberately has NO score, percentage or per-question verdict.
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

class OfflineSavedScreen extends StatelessWidget {
  final String firstName;
  final String lastName;

  /// "Keyingi o'quvchi" — hosts pop their route here.
  final VoidCallback onNext;

  /// Non-null = the answers could NOT be written to the pack's result chain.
  /// The screen then says so honestly and offers a retry instead of
  /// "saved" — a lost result must never look like a kept one.
  final VoidCallback? onRetry;

  const OfflineSavedScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.onNext,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final failed = onRetry != null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    failed
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_rounded,
                    size: 88,
                    color: failed ? AppColors.err : AppColors.brand),
                const SizedBox(height: 20),
                Text(failed ? l10n.resultNotSavedError : l10n.usbSavedTitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink1)),
                const SizedBox(height: 8),
                Text('$lastName $firstName'.trim(),
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 16, color: AppColors.ink2)),
                const SizedBox(height: 12),
                if (!failed)
                  Text(l10n.usbSavedBody,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: AppColors.ink3, height: 1.4)),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: failed ? onRetry : onNext,
                  child: Text(failed ? l10n.retry : l10n.nextStudent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
