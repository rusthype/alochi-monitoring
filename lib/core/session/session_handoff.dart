// lib/core/session/session_handoff.dart
//
// One idempotent cleanup for the end of a student's session on a shared
// kiosk, so the next student never inherits anything. Safe to call twice.
// NEVER deletes unsynced diagnostic answers — SyncService still has to
// upload them (they are the only copy until then).
import 'package:flutter/foundation.dart';

import '../../features/diagnostic/data/diagnostic_prefetch_cache.dart';
import '../db/attempt_store.dart';
import '../db/credential_cache.dart';
import '../db/diagnostic_answer_store.dart';

/// [attemptKey] is the AttemptStore key of the finished attempt (e.g.
/// `diag_<id>`); [attemptId] the diagnostic attempt id whose prefetched
/// packages are dropped. Each step is best-effort and isolated.
Future<void> cleanSessionHandoff(
    {String? attemptKey, String? attemptId}) async {
  Future<void> step(String name, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('cleanSessionHandoff[$name] failed (non-fatal): $e');
    }
  }

  if (attemptKey != null) {
    await step('attempt', () => AttemptStore.clear(attemptKey));
  }
  await step('answers', DiagnosticAnswerStore.clearSynced);
  await step('credentials', CredentialCache.clear);
  if (attemptId != null) {
    DiagnosticPrefetchCache.instance.clearAttempt(attemptId);
  }
}
