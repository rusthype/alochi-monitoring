// lib/features/diagnostic/widgets/diagnostic_locale_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/diagnostic_locale_provider.dart';

/// Wraps the post-class-selection diagnostic screens (student select, test
/// runner, finished) so their UI locale follows the selected class's
/// language, without touching the app-wide `localeProvider` — which would
/// otherwise leak into unrelated screens (login, settings, teacher UI) that
/// the same device cycles through between diagnostic sessions.
class DiagnosticLocaleShell extends ConsumerWidget {
  final Widget child;

  const DiagnosticLocaleShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(diagnosticLocaleProvider);
    return Localizations.override(
      context: context,
      locale: locale,
      child: child,
    );
  }
}
