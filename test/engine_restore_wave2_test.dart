// Audit wave 2:
//  #5 extra time granted while the PC was down is applied on restore (and is
//     not double-counted); the cumulative amount applied is persisted
//  #6 restore never waits on session/resume without a token, and caps it at 2 s
//  #4 the attempt record carries everything crash recovery needs to rebuild
//     the result payload (test_key, school, grade, group_id, ...)

import 'dart:async';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/services/heartbeat_service.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testKey = 'wave2_restore_v1';
const _student = 'S-W2';

Map<String, dynamic> _specJson() => {
      'test_key': _testKey,
      'title': 'Wave2',
      'grade': 5,
      'version': 1,
      'parts': ['SecA'],
      'variants': {
        '1': {
          'SecA': [
            {
              'type': 'text_choice',
              'q': 'TC-QUESTION',
              'opts': ['Alpha', 'Beta'],
              'ans': 0,
            },
          ],
        },
      },
    };

Map<String, dynamic> _record({int? extraApplied, int deadlineInSecs = 300}) => {
      'variant': 1,
      'answers': <String, dynamic>{},
      'started_at': DateTime.now().millisecondsSinceEpoch,
      'attempt_id': 'nonce-w2',
      'deadline_epoch_ms': DateTime.now()
          .add(Duration(seconds: deadlineInSecs))
          .millisecondsSinceEpoch,
      if (extraApplied != null) 'extra_applied_s': extraApplied,
      'student_name': 'Familiya Ism',
      'student_id': _student,
      'group_name': '',
    };

Widget _engine() => MaterialApp(
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
        duration: const Duration(minutes: 10),
        onComplete: (r, s) {},
      ),
    );

Future<void> _io(WidgetTester tester, {int ms = 200}) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump(const Duration(milliseconds: 100));
}

class _FakeApi extends MonitoringApi {
  _FakeApi({this.token = false});
  final bool token;
  int resumeCalls = 0;
  final Completer<Map<String, dynamic>> resumeGate = Completer();

  @override
  bool get hasAuthToken => token;

  @override
  Future<Map<String, dynamic>> sessionResume(String testKey) {
    resumeCalls++;
    return resumeGate.future; // never answers unless the test completes it
  }

  @override
  Future<Map<String, dynamic>> sessionPing({
    required String sessionId,
    String schoolCode = '',
    String name = '',
    String variant = '',
    String testKey = '',
    String status = 'active',
    String? studentCode,
    int tabSwitchCount = 0,
    int? currentQuestionIndex,
    int? totalQuestions,
    List<int>? questionTimes,
    String? platform,
    String? appVersion,
    String? deviceName,
    Map<String, dynamic>? answers,
    int? elapsedSeconds,
    int? remainingSeconds,
    String? localIp,
    String? machineId,
    String? macAddress,
    List<String>? capabilities,
  }) async =>
      {'ok': true};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hb = HeartbeatService.instance;

  setUpAll(() async {
    await QueueCrypto.encryptPayload('{}');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    hb.cancelTest(); // resets the cumulative extra-time baseline
  });

  tearDown(() {
    hb
      ..onExtendSeconds = null
      ..cancelTest();
  });

  group('#5 extra time on restore', () {
    testWidgets(
        'extra granted while the PC was down (ping reply before the screen '
        'existed) is applied minus what the record already holds',
        (tester) async {
      await tester.runAsync(
          () => AttemptStore.save(_testKey, _record(extraApplied: 300)));
      hb.reconcileProctorState(extraTimeSeconds: 600); // consumed pre-mount
      await tester.pumpWidget(_engine());
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await _io(tester);

      // 300 s left at save, +300 s newly granted -> ~600 s (not 300, not 900).
      expect(hb.remainingSeconds, inInclusiveRange(595, 601));
    });

    testWidgets(
        'no ping reply yet: nothing changes, baseline is seeded so a '
        'later reply only adds the NEW part', (tester) async {
      await tester.runAsync(
          () => AttemptStore.save(_testKey, _record(extraApplied: 300)));
      await tester.pumpWidget(_engine());
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await _io(tester);
      expect(hb.remainingSeconds, inInclusiveRange(295, 301));

      hb.reconcileProctorState(extraTimeSeconds: 300); // same total: no-op
      await tester.pump(const Duration(milliseconds: 100));
      expect(hb.remainingSeconds, inInclusiveRange(295, 301));

      hb.reconcileProctorState(extraTimeSeconds: 480); // +180 new
      await tester.pump(const Duration(milliseconds: 100));
      expect(hb.remainingSeconds, inInclusiveRange(475, 481));
    });

    testWidgets('fresh attempt: extra granted at the roster is not lost',
        (tester) async {
      hb.reconcileProctorState(extraTimeSeconds: 120);
      await tester.pumpWidget(_engine());
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await _io(tester);
      expect(hb.remainingSeconds, inInclusiveRange(715, 721)); // 600 + 120
    });

    testWidgets('extra_applied_s and the recovery identity are persisted',
        (tester) async {
      await tester.pumpWidget(_engine());
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await _io(tester);
      hb.reconcileProctorState(extraTimeSeconds: 120);
      await _io(tester);

      final saved = (await tester.runAsync(() => AttemptStore.load(_testKey)))!;
      expect(saved['extra_applied_s'], 120);
      expect(saved['test_key'], _testKey);
      expect(saved['school'], '56');
      expect(saved['grade'], 5);
      expect(saved['group_id'], 'g-77');
      expect(saved['group_name'], '5-A');
      expect(saved['student_name'], 'Familiya Ism');
    });
  });

  group('#6 session/resume on restore', () {
    Future<void> startSession() => hb.startTest(
        schoolCode: '56',
        name: 'Ism',
        variant: '1',
        testKey: _testKey,
        studentCode: _student,
        sessionId: 'sess-w2');

    testWidgets('without an auth token the call is skipped entirely',
        (tester) async {
      final saved = api;
      final fake = _FakeApi(token: false);
      api = fake;
      addTearDown(() => api = saved);
      await tester.runAsync(startSession);
      await tester.runAsync(
          () => AttemptStore.save(_testKey, _record(extraApplied: 0)));

      await tester.pumpWidget(_engine());
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await _io(tester);

      expect(fake.resumeCalls, 0);
      expect(find.text('TC-QUESTION'), findsOneWidget);
    });

    testWidgets('with a token a hung call is cut off after 2 s',
        (tester) async {
      final saved = api;
      final fake = _FakeApi(token: true);
      api = fake;
      addTearDown(() => api = saved);
      await tester.runAsync(startSession);
      await tester.runAsync(
          () => AttemptStore.save(_testKey, _record(extraApplied: 0)));

      await tester.pumpWidget(_engine());
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await _io(tester); // local record read, server still hanging
      expect(fake.resumeCalls, 1);
      expect(find.text('TC-QUESTION'), findsNothing);

      await tester.pump(const Duration(milliseconds: 2100));
      await _io(tester);
      expect(find.text('TC-QUESTION'), findsOneWidget);
    });
  });
}
