import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart' show newIdempotencyToken;
import '../../core/db/attempt_store.dart';
import '../../core/db/test_cache.dart';
import '../../core/engine/test_models.dart' show pickVariantNumber;
import '../../core/offline/lan_client_session.dart' show isOfflineModeOpen;
import '../../core/services/heartbeat_service.dart';
import '../../core/services/server_clock.dart';
import '../../core/services/test_catalog_service.dart';
import '../../core/services/toast_service.dart';

import 'test_session.dart';

Future<void> launchRunner(
  BuildContext context, {
  required TestSession session,
  required String firstName,
  required String lastName,
  required int studentGrade,
  String groupName = '',
  String groupId = '',
  String studentId = '',

  /// Variant the student-entry screen already prepared (images downloaded).
  /// Used only when the student has no saved attempt to resume.
  int? preparedVariant,
}) async {
  // Time-lock safety net: the catalog UI (login_screen.dart) already blocks
  // navigation into locked tests, this is a second layer in case launchRunner
  // is ever reached through another path.
  // Server time, not the PC clock: a PC reset to 2000 must not lock every
  // scheduled test, a clock running ahead must not open one early.
  await ServerClock.ensureLoaded();
  final lockedUntil = TestCatalogService.lockedUntilFor(session.testKey);
  if (ServerClock.isFuture(lockedUntil)) {
    if (context.mounted) {
      ToastService.showError(context, AppLocalizations.of(context)!.testLocked);
    }
    return;
  }

  // 3) Make sure package is fully downloaded
  var cached = await TestCache.get(session.testKey);
  if (cached == null && isOfflineModeOpen) {
    // USB pack / LAN client: load it from the open pack instead of failing.
    await testCatalogService.download(session.testKey,
        groupId: groupId.isEmpty ? null : groupId,
        schoolCode: session.schoolCode);
    cached = await TestCache.get(session.testKey);
  }
  if (cached == null) {
    if (context.mounted) {
      ToastService.showError(
          context, AppLocalizations.of(context)!.testNotInCache);
    }
    return;
  }

  // Safety net only: the variant's images are downloaded when the STUDENT is
  // selected (student_entry_screen), never here. If anything is missing
  // (evicted/deleted), say so and go back instead of silently downloading.
  final intended = await previewAttemptVariant(cached,
      testKey: session.testKey, studentId: studentId, drawn: preparedVariant);
  if (!await testCatalogService.variantImagesComplete(cached, intended)) {
    if (context.mounted) {
      ToastService.showError(
          context, AppLocalizations.of(context)!.testNotInCache);
    }
    return;
  }
  if (!context.mounted) return;

  final variant = await resolveAttemptVariant(
    cached,
    testKey: session.testKey,
    firstName: firstName,
    lastName: lastName,
    studentId: studentId,
    groupName: groupName,
    preferredVariant: intended,
  );

  if (!context.mounted) return;

  // The attempt id doubles as the hub session id: re-entering the same
  // attempt re-claims the same hub session (pause + extra time kept), a new
  // attempt is a new session.
  final attemptId = (await AttemptStore.loadForStudent(
          session.testKey, studentId))?['attempt_id']
      ?.toString();
  if (!context.mounted) return;

  // Best-effort concurrent-session check: block only if the backend
  // explicitly confirms another device already holds an active session for
  // this student+test within a short window. A slow/no connection must
  // never block offline test-taking, so any timeout or failure here is
  // treated as "safe to proceed" (see HeartbeatService.startTest).
  var canProceed = true;
  try {
    canProceed = await HeartbeatService.instance
        .startTest(
          schoolCode: session.schoolCode,
          name: '$firstName $lastName'.trim(),
          variant: variant.toString(),
          testKey: session.testKey,
          studentCode: studentId,
          sessionId: attemptId,
        )
        .timeout(const Duration(seconds: 3));
  } catch (_) {
    canProceed = true;
  }

  if (!canProceed) {
    // No session row was created server-side for this attempt — drop the
    // ghost session id locally so idle-presence heartbeats fall back to the
    // device-level id instead of pinging a session that doesn't exist.
    HeartbeatService.instance.cancelTest();
    if (context.mounted) {
      ToastService.showError(
          context, AppLocalizations.of(context)!.sessionConflictOtherDevice);
    }
    return;
  }

  if (!context.mounted) return;

  await GoRouter.of(context).push('/engine_host', extra: {
    'testData': cached,
    'variant': variant,
    'firstName': firstName,
    'lastName': lastName,
    'school': session.schoolCode,
    'group': groupName.isEmpty ? null : groupName,
    'groupId': groupId.isEmpty ? null : groupId,
    'grade': studentGrade,
    'studentId': studentId,
  });

  HeartbeatService.instance.finishTest();
}

/// Resumes a saved attempt (same variant, deadline not yet passed) or picks
/// a new random variant and records a fresh attempt in [AttemptStore].
///
/// Answer restoration itself happens in test_engine.dart (it reloads the
/// same attempt by test_key + variant at initState) — this function only
/// decides which variant to run and seeds a fresh attempt record when
/// starting over.
const _staleAttemptMs = 12 * 60 * 60 * 1000;

/// The variant of a saved attempt that [resolveAttemptVariant] would resume
/// (same rules), or null when a fresh variant has to be picked. Read-only.
Future<int?> _savedVariantToResume(String testKey, String studentId) async {
  final saved = await AttemptStore.loadForStudent(testKey, studentId);
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  if (saved == null) return null;
  final savedVariant = int.tryParse(saved['variant']?.toString() ?? '');
  final deadlineRaw = saved['deadline_epoch_ms'];
  final deadlineMs = deadlineRaw is num ? deadlineRaw.toInt() : null;
  final notExpired = deadlineMs == null || deadlineMs > nowMs;
  // A record already marked completed was (or is about to be) submitted:
  // it must be resumed even past its deadline so the engine can replay the
  // identical submission instead of silently dropping it.
  final completed = saved['completed'] == true;
  // An unfinished attempt is resumed even when its deadline has passed: the
  // engine then auto-submits what the student had. Starting a fresh attempt
  // here would hand out a full timer again. Only a record from another
  // day (long abandoned) is dropped.
  final stale = deadlineMs != null && nowMs - deadlineMs > _staleAttemptMs;
  if (savedVariant != null && (notExpired || completed || !stale)) {
    return savedVariant;
  }
  return null;
}

/// The variant this student will get, WITHOUT persisting anything: the saved
/// attempt's variant if one would be resumed, else [drawn] (a variant the
/// caller already drew and prepared), else a fresh random draw. The caller
/// must remember a fresh draw and pass it back as [drawn] / `preferredVariant`
/// so the variant prepared (images downloaded) is the variant launched.
///
/// A FRESH draw whose images are not all on disk is swapped for another
/// variant that is complete (variants are interchangeable forms of the same
/// test): offline that is the difference between starting and being blocked
/// by one missing picture. A resumed attempt keeps its variant, and when no
/// variant is complete the draw stays (the caller downloads it).
Future<int> previewAttemptVariant(
  Map<String, dynamic> cached, {
  required String testKey,
  required String studentId,
  int? drawn,
  TestCatalogService? catalog,
}) async {
  final saved = await _savedVariantToResume(testKey, studentId);
  if (saved != null) return saved;
  final first = drawn ?? _pickRandomVariant(cached);
  final svc = catalog ?? testCatalogService;
  try {
    if (await svc.variantImagesComplete(cached, first)) return first;
    final others = _variantNumbers(cached)..remove(first);
    others.shuffle();
    for (final v in others) {
      if (await svc.variantImagesComplete(cached, v)) return v;
    }
  } catch (e) {
    debugPrint('previewAttemptVariant: completeness check failed: $e');
  }
  return first;
}

List<int> _variantNumbers(Map<String, dynamic> cached) {
  final blob = (cached['test_data'] is Map)
      ? Map<String, dynamic>.from(cached['test_data'] as Map)
      : cached;
  final variants = blob['variants'];
  if (variants is! Map) return [];
  return variants.keys
      .map((k) => int.tryParse(k.toString()))
      .whereType<int>()
      .toList();
}

@visibleForTesting
Future<int> resolveAttemptVariant(
  Map<String, dynamic> cached, {
  required String testKey,
  required String firstName,
  required String lastName,
  required String studentId,
  required String groupName,
  int? preferredVariant,
}) async {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final resumed = await _savedVariantToResume(testKey, studentId);
  if (resumed != null) return resumed;

  final variant = preferredVariant ?? _pickRandomVariant(cached);
  await AttemptStore.save(testKey, {
    'variant': variant,
    'answers': <String, dynamic>{},
    'started_at': nowMs,
    // One-time nonce identifying THIS attempt; never rewritten on resume.
    // The completion idempotency token is derived from it (see
    // buildResultToken), so a crash-replay dedupes but a retake does not.
    'attempt_id': newIdempotencyToken(),
    'deadline_epoch_ms': null,
    'student_name': '$firstName $lastName'.trim(),
    'student_id': studentId,
    'group_name': groupName,
  });
  return variant;
}

int _pickRandomVariant(Map<String, dynamic> cached) {
  final blob = (cached['test_data'] is Map)
      ? Map<String, dynamic>.from(cached['test_data'] as Map)
      : cached;
  return pickVariantNumber(blob['variants']);
}
