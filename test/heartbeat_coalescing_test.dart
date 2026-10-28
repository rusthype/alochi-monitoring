// Audit E-15 / F29: answer reports are coalesced (<= 1 in flight, latest
// answers only), and ping replies with unexpected shapes never raise.

import 'dart:async';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/services/heartbeat_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _GatedApi extends MonitoringApi {
  final pings = <Map<String, dynamic>>[];
  var inFlight = 0;
  var maxInFlight = 0;
  Completer<void>? gate;
  Object? failWith;
  Map<String, dynamic> reply = {'ok': true};

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
  }) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    pings.add({'status': status, 'answers': answers});
    try {
      if (gate != null) await gate!.future;
      if (failWith != null) throw failWith!;
      return reply;
    } finally {
      inFlight--;
    }
  }
}

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitoringApi saved;
  late _GatedApi fake;
  final hb = HeartbeatService.instance;

  setUp(() async {
    saved = api;
    fake = _GatedApi();
    api = fake;
    HeartbeatService.answerReportDelay = const Duration(milliseconds: 60);
    await hb.startTest(
        schoolCode: '56',
        name: 'Ali',
        variant: '1',
        testKey: 'hb_key',
        studentCode: 'S1',
        sessionId: 'attempt-hb');
    fake.pings.clear();
  });

  tearDown(() async {
    fake.gate?.complete();
    hb.finishTest();
    await _wait(50);
    hb.onExtendSeconds = null;
    HeartbeatService.answerReportDelay = const Duration(seconds: 2);
    api = saved;
  });

  test('a burst of answers sends ONE ping with the latest answers', () async {
    for (var i = 1; i <= 20; i++) {
      hb.reportAnswers({'S/0': i}, i);
    }
    await _wait(250);
    final withAnswers = fake.pings.where((p) => p['answers'] != null).toList();
    expect(withAnswers, hasLength(1));
    expect((withAnswers.single['answers'] as Map)['S/0'], 20);
  });

  test('never more than one in flight; changes meanwhile go out once, latest',
      () async {
    fake.gate = Completer<void>();
    hb.reportAnswers({'S/0': 1}, 1);
    await _wait(150); // first ping fired and is stuck on the gate
    expect(fake.pings, hasLength(1));

    hb.reportAnswers({'S/0': 2}, 2);
    await _wait(150); // debounce fires while #1 is in flight -> deferred
    hb.reportAnswers({'S/0': 3}, 3);
    await _wait(150);
    expect(fake.pings, hasLength(1), reason: 'no second concurrent ping');

    final done = fake.gate!;
    fake.gate = null;
    done.complete();
    await _wait(200);
    expect(fake.maxInFlight, 1);
    expect(fake.pings, hasLength(2));
    expect((fake.pings.last['answers'] as Map)['S/0'], 3);
  });

  test(
      'tolerant reply parsing: wrong shapes never throw, num extra time '
      'is accepted', () async {
    final deltas = <int>[];
    hb.onExtendSeconds = deltas.add;
    fake.reply = {
      'locked': 'yes', // not a bool -> ignored
      'extra_time_seconds': 60.0, // double -> 60
      'commands': 'nope', // not a list -> ignored
      'proctor_interval_ms': 5000.0,
    };
    hb.reportAnswers({'S/0': 1}, 1);
    await _wait(250);
    expect(deltas, [60]);
    expect(hb.locked, isFalse);
    expect(hb.proctorIntervalMs, 5000);
  });

  test('a failing ping is swallowed (no unhandled error)', () async {
    fake.failWith = StateError('network down');
    hb.reportAnswers({'S/0': 1}, 1);
    await _wait(250);
    expect(fake.pings, isNotEmpty);
  });
}
