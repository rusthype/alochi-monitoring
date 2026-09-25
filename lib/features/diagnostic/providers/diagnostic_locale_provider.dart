// lib/features/diagnostic/providers/diagnostic_locale_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Scoped UI locale for the diagnostic test flow (student select, test
/// runner, finished screens), set from the selected class's language in
/// [DiagnosticClassSelectScreen._selectClass]. Deliberately NOT persisted
/// (unlike the app-wide `localeProvider` in core/locale/locale_provider.dart)
/// — it only needs to live for the current kiosk session, and persisting it
/// would leak the last-tested class's language into the operator's own next
/// login on this device.
final diagnosticLocaleProvider =
    NotifierProvider<DiagnosticLocaleNotifier, Locale>(() {
  return DiagnosticLocaleNotifier();
});

class DiagnosticLocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('uz');

  void setLocale(Locale locale) {
    state = locale;
  }
}
