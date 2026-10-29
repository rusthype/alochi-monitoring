// Security review F1: a restored attempt record is untrusted. Editing
// `deadline_epoch_ms` / `paused_remaining_ms` in the attempt file must never
// grant more than the test's duration (plus the bounded recorded extra time).

import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/services/heartbeat_service.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testKey = 'clamp_restore_v1';
const _student = 'S-CLAMP';
const _duration = Duration(minutes: 10);

Map<String, dynamic> _specJson() => {
      'test_key': _testKey,
      'title': 'Clamp',
      'grade': 5,
      'version': 1,
      'parts': ['SecA'],
      'variants': {
        '1': {
          'SecA': [
            {
              'type': 'text_choice',
              'q': 'Q',
              'opts': ['Alpha', 'Beta'],
              'ans': 0,
            },
          ],
        },
      },
    };

Map<String, dynamic> _record({
  required int deadlineInSecs,
  int? pausedRemainingMs,
  int? extraApplied,
}) =>
    {
      'variant': 1,
      'answers': <String, dynamic>{},
      'started_at': DateTime.now().millisecondsSinceEpoch,
      'attempt_id': 'nonce-clamp',
      'deadline_epoch_ms': DateTime.now()
          .add(Duration(seconds: deadlineInSecs))
          .millisecondsSinceEpoch,
      if (pausedRemainingMs != null) 'paused_remaining_ms': pausedRemainingMs,
      if (extraApplied != null) 'extra_applied_s': extraApplied,
      'student_name': 'Familiya Ism',
      'student_id': _student,
      'group_name': '',
    };

Widget _engine({VoidCallback? onExpired}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TestEngine(
        spec: TestSpec.fromJson(_specJson()),
        variant: 1,
        firstName: 'Ism',
        lastName: 'Familiya',
        school: '56',
        group: '5-A',
        groupId: 'g-77',
        grade: 5,
        studentId: _student,
        duration: _duration,
        onExpiredAutoSubmit: onExpired,
        onComplete: (r, s) {},
      ),
    );

Future<void> _io(WidgetTester tester, {int ms = 200}) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hb = HeartbeatService.instance;

  setUpAll(() async {
    await QueueCrypto.encryptPayload('{}');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    hb.cancelTest();
  });

  tearDown(() {
    hb
      ..onExtendSeconds = null
      ..cancelTest();
  });

  Future<void> restore(
    WidgetTester tester,
    Map<String, dynamic> record, {
    VoidCallback? onExpired,
  }) async {
    await tester.runAsync(() => AttemptStore.save(_testKey, record));
    await tester.pumpWidget(_engine(onExpired: onExpired));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);
  }

  testWidgets('honest record is untouched (control)', (tester) async {
    await restore(tester, _record(deadlineInSecs: 300));
    expect(hb.remainingSeconds, inInclusiveRange(295, 301));
  });

  testWidgets('far-future deadline_epoch_ms is clamped to the test duration',
      (tester) async {
    await restore(tester, _record(deadlineInSecs: 10 * 365 * 24 * 3600));
    expect(hb.remainingSeconds, lessThanOrEqualTo(_duration.inSeconds + 1));
    expect(hb.remainingSeconds, greaterThan(_duration.inSeconds - 10));
  });

  testWidgets('huge paused_remaining_ms is clamped to the test duration',
      (tester) async {
    await restore(
      tester,
      _record(deadlineInSecs: 60, pausedRemainingMs: 9999999999),
    );
    expect(hb.remainingSeconds, lessThanOrEqualTo(_duration.inSeconds + 1));
  });

  testWidgets('negative paused_remaining_ms means expired, not extra time',
      (tester) async {
    var expired = false;
    await restore(
      tester,
      _record(deadlineInSecs: 300, pausedRemainingMs: -5000000),
      onExpired: () => expired = true,
    );
    expect(expired, isTrue);
  });

  testWidgets('tampered extra_applied_s cannot lift the cap past 2x duration',
      (tester) async {
    await restore(
      tester,
      _record(deadlineInSecs: 10 * 365 * 24 * 3600, extraApplied: 1 << 40),
    );
    expect(hb.remainingSeconds, lessThanOrEqualTo(_duration.inSeconds * 2 + 1));
  });

  testWidgets('a real recorded extension (within duration) is preserved',
      (tester) async {
    await restore(tester, _record(deadlineInSecs: 800, extraApplied: 300));
    expect(hb.remainingSeconds, inInclusiveRange(795, 801));
  });
}
