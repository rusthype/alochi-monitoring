// add-student / start / finish carry `device_id` + `app_version` so the panel
// can show which computer an attempt came from. Keys are omitted when empty.
import 'dart:convert';

import 'package:alochi_monitoring/core/diagnostics/device_info_collector.dart';
import 'package:alochi_monitoring/core/models/add_student.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _idKey = 'device_report_device_id';

void main() {
  late List<http.Request> sent;
  late MockClient client;

  void setUpDevice({String? id = 'dev-123', String version = '1.0.170'}) {
    SharedPreferences.setMockInitialValues({if (id != null) _idKey: id});
    PackageInfo.setMockInitialValues(
      appName: 'a',
      packageName: 'p',
      version: version,
      buildNumber: '170',
      buildSignature: '',
    );
    DeviceInfoCollector.resetCache();
  }

  setUp(() {
    sent = [];
    client = MockClient((req) async {
      sent.add(req);
      return http.Response(
          jsonEncode({
            'attempt_id': 'att-9',
            'student_name': 'Karimov Vali',
            'class_label': '4-A',
            'language': 'uz',
            'status': 'not_started',
          }),
          200,
          headers: {'content-type': 'application/json'});
    });
    setUpDevice();
  });

  Map<String, dynamic> body(int i) =>
      jsonDecode(sent[i].body) as Map<String, dynamic>;

  Future<void> callAll() => http.runWithClient(() async {
        await diagnosticKioskApi.addStudent(
          schoolId: 's1',
          classLabel: '4-A',
          language: 'uz',
          draft: const AddStudentDraft(
              firstName: 'Vali', lastName: 'Karimov', clientTempId: 'new:x'),
        );
        await diagnosticKioskApi.startAttempt(attemptId: 'a', subject: 'math');
        await diagnosticKioskApi.finishAttempt(attemptId: 'a', answers: []);
      }, () => client);

  test('add-student, start and finish send device_id + app_version', () async {
    await callAll();
    expect(sent.map((r) => r.url.path), [
      endsWith('/students/add/'),
      endsWith('/kiosk/start/'),
      endsWith('/kiosk/finish/'),
    ]);
    for (var i = 0; i < 3; i++) {
      expect(body(i)['device_id'], 'dev-123', reason: 'call $i');
      expect(body(i)['app_version'], '1.0.170+170', reason: 'call $i');
    }
    // Existing keys untouched.
    expect(body(1)['attempt_id'], 'a');
    expect(body(2)['answers'], isEmpty);
  });

  test('empty values are omitted, keys never sent blank', () async {
    DeviceInfoCollector.debugSet(id: '', version: '');
    await callAll();
    for (var i = 0; i < 3; i++) {
      expect(body(i).containsKey('device_id'), isFalse, reason: 'call $i');
      expect(body(i).containsKey('app_version'), isFalse, reason: 'call $i');
    }
  });

  test('collector caches id and version after the first read', () async {
    expect(await DeviceInfoCollector.deviceId(), 'dev-123');
    expect(await DeviceInfoCollector.appVersion(), '1.0.170+170');
    SharedPreferences.setMockInitialValues({_idKey: 'other'});
    PackageInfo.setMockInitialValues(
        appName: 'a',
        packageName: 'p',
        version: '9.9.9',
        buildNumber: '9',
        buildSignature: '');
    expect(await DeviceInfoCollector.deviceId(), 'dev-123');
    expect(await DeviceInfoCollector.appVersion(), '1.0.170+170');
    DeviceInfoCollector.resetCache();
    expect(await DeviceInfoCollector.deviceId(), 'other');
    expect(await DeviceInfoCollector.appVersion(), '9.9.9+9');
  });

  test('offline replay of a queued finish carries device fields', () async {
    // Queued payloads are built by the runner screen without device keys
    // (and by older app versions); the replay adds them.
    await http.runWithClient(
      () => diagnosticKioskApi.submitFinishOffline(
        {'attempt_id': 'a', 'answers': []},
        'tok',
      ),
      () => client,
    );
    expect(body(0)['device_id'], 'dev-123');
    expect(body(0)['app_version'], '1.0.170+170');
    expect(sent[0].headers['Idempotency-Key'], 'tok');
  });

  test('replay keeps device fields already present in the payload', () async {
    await http.runWithClient(
      () => diagnosticKioskApi.submitFinishOffline(
        {'attempt_id': 'a', 'answers': [], 'device_id': 'queued-id'},
        'tok',
      ),
      () => client,
    );
    expect(body(0)['device_id'], 'queued-id');
    expect(body(0)['app_version'], '1.0.170+170');
  });
}
