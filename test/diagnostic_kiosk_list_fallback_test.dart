// listSchools/listClasses/listStudents fall back to the last cached copy when
// the live fetch fails transiently: offline (status 0), rate limited (429) or
// a server error (5xx). A definitive 4xx (e.g. 404) is never masked by cache.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart' show ApiException;
import 'package:alochi_monitoring/core/db/diagnostic_kiosk_cache.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return Directory.systemTemp.path;
      }
      return null;
    });
  });

  final api = DiagnosticKioskApi();
  const cached = [
    {'school_id': '1', 'school_name': 'Keshlangan maktab'},
  ];

  Future<(List<Map<String, dynamic>>, bool)> listWith(
          http.Response Function() respond) =>
      http.runWithClient(
          api.listSchools, () => MockClient((_) async => respond()));

  for (final status in [429, 500, 502, 503]) {
    test('$status with a cached copy returns it as fromCache', () async {
      await DiagnosticKioskCache.save('schools', cached);
      final (rows, fromCache) = await listWith(() => http.Response('{}', status));
      expect(fromCache, isTrue);
      expect(rows.single['school_name'], 'Keshlangan maktab');
    });
  }

  test('429 without any cached copy still throws', () async {
    // listClasses for a school id nothing ever cached.
    await expectLater(
      http.runWithClient(() => api.listClasses('never-cached-school'),
          () => MockClient((_) async => http.Response('{}', 429))),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
    );
  });

  test('a definitive 404 is never masked by the cache', () async {
    await DiagnosticKioskCache.save('schools', cached);
    await expectLater(
      listWith(() => http.Response('{}', 404)),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
    );
  });

  test('a live success is returned fresh (fromCache false)', () async {
    final (rows, fromCache) = await listWith(() => http.Response(
        jsonEncode([
          {'school_id': '9', 'school_name': 'Yangi'}
        ]),
        200));
    expect(fromCache, isFalse);
    expect(rows.single['school_id'], '9');
  });
}
