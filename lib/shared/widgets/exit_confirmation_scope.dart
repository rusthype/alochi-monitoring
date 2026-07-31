import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

import 'package:go_router/go_router.dart';

class ExitConfirmationScope extends StatelessWidget {
  final Widget child;
  const ExitConfirmationScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(AppLocalizations.of(context)!.exitBtn),
                content:
                    Text(AppLocalizations.of(context)!.exitConfirmationMessage),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(AppLocalizations.of(context)!.noWord),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(AppLocalizations.of(context)!.yesBtn),
                  ),
                ],
              ),
            ) ??
            false;
        if (shouldPop && context.mounted) {
          context.pop();
        }
      },
      child: child,
    );
  }
}
