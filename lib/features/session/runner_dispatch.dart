import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/db/test_cache.dart';
import '../../core/services/heartbeat_service.dart';
import '../../shared/theme/app_theme.dart';
import '../test/engine_host_screen.dart';
import 'test_session.dart';

Future<void> launchRunner(
  BuildContext context, {
  required TestSession session,
  required String firstName,
  required String lastName,
  required int studentGrade,
  String groupName = '',
  String studentId = '',
}) async {
  final cached = await TestCache.get(session.testKey);
  if (cached == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test keshda topilmadi. Qayta yuklab oling.'),
          backgroundColor: AppColors.err,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }

  final variant = _pickRandomVariant(cached);

  if (!context.mounted) return;

  HeartbeatService.instance.startTest(
    schoolCode: session.schoolCode,
    name: '$firstName $lastName'.trim(),
    variant: variant.toString(),
    testKey: session.testKey,
  );

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EngineHostScreen(
        testData: cached,
        variant: variant,
        firstName: firstName,
        lastName: lastName,
        school: session.schoolCode,
        group: groupName.isEmpty ? null : groupName,
        grade: studentGrade,
        studentId: studentId,
      ),
    ),
  );

  HeartbeatService.instance.finishTest();
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
