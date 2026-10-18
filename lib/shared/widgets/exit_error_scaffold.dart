import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Pops the current route, or goes to '/' when there is nothing to pop.
/// Never touches the open offline pack / LAN session.
void leaveToPreviousOrHome(BuildContext context) {
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return;
  }
  GoRouter.maybeOf(context)?.go('/');
}

/// Dead-end/error screen of the exam flow. Always has an AppBar back arrow, a
/// prominent back button and Esc, so a child can never get stuck on it.
class ExitErrorScaffold extends StatelessWidget {
  final String message;
  const ExitErrorScaffold({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            leaveToPreviousOrHome(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            leading: BackButton(
              color: AppColors.ink1,
              onPressed: () => leaveToPreviousOrHome(context),
            ),
            title: Text(l10n.testTitle),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 56, color: AppColors.err),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: AppColors.ink2),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => leaveToPreviousOrHome(context),
                    child: Text(l10n.backButton),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
