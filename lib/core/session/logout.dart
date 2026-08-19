// lib/core/session/logout.dart
//
// Single shared kiosk-security logout sequence. Every self-login student
// screen (student_results_screen.dart, student_certificates_screen.dart,
// student_help_screen.dart, student_settings_screen.dart, my_tests_screen.dart)
// used to hand-reimplement the same three steps (clear token -> clear cached
// credentials -> hard-reset Navigator to LoginScreen) — centralized here so
// the sequence can't drift or be half-applied in any one screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../db/credential_cache.dart';
import '../services/heartbeat_service.dart';

/// Clears the local auth token + cached credentials — the mandatory
/// kiosk-security step so a shared self-login session never survives past
/// its own use. Does not navigate; call [logoutStudentSession] for the full
/// logout, or use this alone when navigation is handled separately (e.g.
/// my_tests_screen.dart clears the session before launching a test, not
/// only after it returns).
Future<void> clearStudentSession() async {
  api.clearToken();
  HeartbeatService.instance.clearStudentContext();
  await CredentialCache.clear();
}

/// Hard-resets to a fresh LoginScreen so back-navigation can never reach a
/// stale authenticated screen again.
///
/// Uses go_router's own `context.go('/')` (app_router.dart maps '/' to
/// LoginScreen) instead of a raw Navigator.pushAndRemoveUntil. Callers like
/// my_tests_screen.dart's post-test flow call this from a context nested
/// inside a StatefulShellRoute branch's own Navigator — a raw
/// `Navigator.of(context)` there would only reset that branch's inner
/// stack, leaving the StudentShell chrome stuck on screen; using
/// `rootNavigator: true` to reach past it instead corrupted the tree
/// (go_router's StatefulShellRoute keeps a persistent GlobalKey for its
/// navigationShell, and manually pushing into go_router's own root
/// Navigator behind its back caused a "Duplicate GlobalKey" crash once
/// go_router reconciled its expected page stack against it — reproduced via
/// computer-use on the "Keyingi o'quvchi" flow). `context.go()` finds the
/// router via InheritedWidget lookup (works from any nesting depth, same as
/// engine_host_screen.dart's own "Bosh sahifa" exit) and replaces the whole
/// location stack through go_router's normal state machine, so there's
/// nothing left for it to reconcile against.
void goToLoginReplacingStack(BuildContext context) {
  if (!context.mounted) return;
  context.go('/');
}

/// Full logout: clear the session, then hard-reset navigation to
/// LoginScreen. The one entry point every student-cabinet screen's
/// `onLogout` should call.
Future<void> logoutStudentSession(BuildContext context) async {
  await clearStudentSession();
  if (!context.mounted) return;
  goToLoginReplacingStack(context);
}
