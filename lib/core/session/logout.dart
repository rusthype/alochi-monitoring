// lib/core/session/logout.dart
//
// Single shared kiosk-security logout sequence. Every self-login student
// screen (student_results_screen.dart, student_certificates_screen.dart,
// student_help_screen.dart, student_settings_screen.dart, my_tests_screen.dart)
// used to hand-reimplement the same three steps (clear token -> clear cached
// credentials -> hard-reset Navigator to LoginScreen) — centralized here so
// the sequence can't drift or be half-applied in any one screen.
import 'package:flutter/material.dart';

import '../../features/auth/login_screen.dart';
import '../api/api_client.dart';
import '../db/credential_cache.dart';

/// Clears the local auth token + cached credentials — the mandatory
/// kiosk-security step so a shared self-login session never survives past
/// its own use. Does not navigate; call [logoutStudentSession] for the full
/// logout, or use this alone when navigation is handled separately (e.g.
/// my_tests_screen.dart clears the session before launching a test, not
/// only after it returns).
Future<void> clearStudentSession() async {
  api.clearToken();
  await CredentialCache.clear();
}

/// Hard-resets to a fresh LoginScreen so back-navigation can never reach a
/// stale authenticated screen again.
void goToLoginReplacingStack(BuildContext context) {
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}

/// Full logout: clear the session, then hard-reset navigation to
/// LoginScreen. The one entry point every student-cabinet screen's
/// `onLogout` should call.
Future<void> logoutStudentSession(BuildContext context) async {
  await clearStudentSession();
  if (!context.mounted) return;
  goToLoginReplacingStack(context);
}
