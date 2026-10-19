// Online contract: the 'finished' ping sent by finishTest() keeps the REAL
// test_key (the backend's session ping compares it with the stored key).
import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/services/heartbeat_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingApi extends MonitoringApi {
  _RecordingApi({this.lan = false});
  final bool lan;
  @override
  bool get isLan => lan;

  final pings = <Map<String, dynamic>>[];
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
    pings.add({'session_id': sessionId, 'test_key': testKey, 'status': status});
    return {'ok': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("finishTest() sends status 'finished' with the real test_key", () async {
    final saved = api;
    final fake = _RecordingApi();
    api = fake;
    addTearDown(() => api = saved);

    final hb = HeartbeatService.instance;
    await hb.startTest(
        schoolCode: '56',
        name: 'Ali',
        variant: '1',
        testKey: 'cw1_key',
        studentCode: 'S1',
        sessionId: 'attempt-1');
    fake.pings.clear();

    hb.finishTest();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final fin = fake.pings.where((p) => p['status'] == 'finished').toList();
    expect(fin, hasLength(1));
    expect(fin.single['test_key'], 'cw1_key');
    expect(fin.single['session_id'], 'attempt-1');
  });

  test('LAN api: finishTest sends the device-level idle ping (no test_key)',
      () async {
    final saved = api;
    final fake = _RecordingApi(lan: true);
    api = fake;
    addTearDown(() => api = saved);

    final hb = HeartbeatService.instance;
    await hb.startTest(
        schoolCode: '56',
        name: 'Ali',
        variant: '1',
        testKey: 'cw1_key',
        studentCode: 'S1',
        sessionId: 'attempt-2');
    fake.pings.clear();

    hb.finishTest();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final fin = fake.pings.where((p) => p['status'] == 'finished').toList();
    expect(fin, hasLength(1));
    expect(fin.single['test_key'], '');
    expect(fin.single['session_id'], 'attempt-2');
  });
}
