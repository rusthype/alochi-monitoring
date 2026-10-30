import 'dart:async';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/diagnostics/error_log.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs [call] against a client that never answers, lets the 20s API timeout
/// fire (fake clock) and returns the resulting ErrorLog entries.
Future<List<Map<String, dynamic>>> _timeoutEntries(
    WidgetTester tester, Future<void> Function() call) async {
  SharedPreferences.setMockInitialValues({});
  final hang = MockClient((_) => Completer<http.Response>().future);
  final done = http.runWithClient(
      () => call().then<void>((_) {}, onError: (_) {}), () => hang);
  await tester.pump(const Duration(seconds: 21));
  await tester.pump();
  await done;
  final snap = await tester.runAsync(ErrorLog.snapshot);
  return snap!.entries;
}

void main() {
  // One test on purpose: ErrorLog's static write chain / prefs cache do not
  // survive a second testWidgets fake-async zone.
  testWidgets('API timeouts log METHOD + path, no query/auth, kind other',
      (tester) async {
    final api = MonitoringApi()..setToken('Sekret-Bearer-Token-1234567890abc');
    var e = await _timeoutEntries(
        tester, () => api.fetchGroups('26', schoolId: 'abc'));
    expect(e, hasLength(1));
    var msg = e.single['message'] as String;
    expect(msg, contains('TimeoutException'));
    expect(msg, contains('[GET /api/v1/monitoring/groups/]'));
    for (final leak in ['school=', 'Sekret', 'Bearer', 'api.alochi.org']) {
      expect(msg, isNot(contains(leak)));
    }
    expect(e.single['kind'], kErrOther);

    e = await _timeoutEntries(tester, () => MonitoringApi().ping());
    expect(e.single['message'], contains('monitoring/ping'));
    expect(e.single['kind'], kErrOther);

    e = await _timeoutEntries(
        tester, () => DiagnosticKioskApi().availableSubjects(3));
    msg = e.single['message'] as String;
    expect(msg, contains('[GET /api/v1/diagnostic/cat/subjects/]'));
    expect(msg, isNot(contains('grade=')));
    expect(e.single['kind'], kErrOther);
  });
}
