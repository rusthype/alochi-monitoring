import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/db/attempt_store.dart';
import '../../core/db/test_cache.dart';
import '../../core/services/heartbeat_service.dart';
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
}) async {
  // Time-lock safety net: the catalog UI (login_screen.dart) already blocks
  // navigation into locked tests, this is a second layer in case launchRunner
  // is ever reached through another path.
  final lockedUntil = TestCatalogService.lockedUntilFor(session.testKey);
  if (lockedUntil != null && lockedUntil.isAfter(DateTime.now())) {
    if (context.mounted) {
      ToastService.showError(context, AppLocalizations.of(context)!.testLocked);
    }
    return;
  }

  // 3) Make sure package is fully downloaded
  final cached = await TestCache.get(session.testKey);
  if (cached == null) {
    if (context.mounted) {
      ToastService.showError(context, AppLocalizations.of(context)!.testNotInCache);
    }
    return;
  }

  final variant = await _resolveVariant(
    cached,
    testKey: session.testKey,
    firstName: firstName,
    lastName: lastName,
    studentId: studentId,
    groupName: groupName,
  );

  if (!context.mounted) return;

  HeartbeatService.instance.startTest(
    schoolCode: session.schoolCode,
    name: '$firstName $lastName'.trim(),
    variant: variant.toString(),
    testKey: session.testKey,
    studentCode: studentId,
  );

  await GoRouter.of(context).push('/engine_host',
      extra: {
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
Future<int> _resolveVariant(
  Map<String, dynamic> cached, {
  required String testKey,
  required String firstName,
  required String lastName,
  required String studentId,
  required String groupName,
}) async {
  final saved = await AttemptStore.loadForStudent(testKey, studentId);
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  if (saved != null) {
    final savedVariant = int.tryParse(saved['variant']?.toString() ?? '');
    final deadlineRaw = saved['deadline_epoch_ms'];
    final deadlineMs = deadlineRaw is num ? deadlineRaw.toInt() : null;
    final notExpired = deadlineMs == null || deadlineMs > nowMs;
    if (savedVariant != null && notExpired) {
      return savedVariant;
    }
  }

  final variant = _pickRandomVariant(cached);
  await AttemptStore.save(testKey, {
    'variant': variant,
    'answers': <String, dynamic>{},
    'started_at': nowMs,
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
  final variants = blob['variants'];
  if (variants is Map && variants.isNotEmpty) {
    final keys = variants.keys.map((k) => k.toString()).toList();
    final pick = keys[Random().nextInt(keys.length)];
    return int.tryParse(pick) ?? 1;
  }
  return 1;
}
