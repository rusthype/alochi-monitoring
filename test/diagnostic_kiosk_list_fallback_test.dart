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

  test('lastFallbackWasOffline: true only for a network failure (status 0)',
      () async {
    await DiagnosticKioskCache.save('schools', cached);
    final offline = DiagnosticKioskApi();
    await http.runWithClient(offline.listSchools,
        () => MockClient((_) async => throw const SocketException('down')));
    expect(offline.lastFallbackWasOffline, isTrue);
    for (final status in [429, 503]) {
      final a = DiagnosticKioskApi();
      await http.runWithClient(
          a.listSchools, () => MockClient((_) async => http.Response('{}', status)));
      expect(a.lastFallbackWasOffline, isFalse, reason: '$status');
    }
  });

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

  group('listStudents language filter', () {
    Future<(List<Map<String, dynamic>>, bool)> students(
            http.Response Function(http.Request) respond,
            {String language = ''}) =>
        http.runWithClient(
            () => api.listStudents('s1', '5-A', language: language),
            () => MockClient((req) async => respond(req)));

    test('sends &language= when set, nothing when empty', () async {
      final urls = <Uri>[];
      http.Response ok(http.Request r) {
        urls.add(r.url);
        return http.Response('[]', 200);
      }

      await students(ok, language: 'ru');
      await students(ok);
      expect(urls[0].queryParameters, {'class_label': '5-A', 'language': 'ru'});
      expect(urls[1].queryParameters, {'class_label': '5-A'});
    });

    test('cache key carries the language; the old key is a fallback',
        () async {
      await students((_) => http.Response(
          jsonEncode([
            {'attempt_id': 'x'}
          ]),
          200),
          language: 'ru');
      // save is fire-and-forget
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await DiagnosticKioskCache.load('students_s1_5-A_ru'), isNotNull);
      expect(await DiagnosticKioskCache.load('students_s1_5-A'), isNull);

      // Only a pre-upgrade cache exists for 'uz': used when offline.
      await DiagnosticKioskCache.save('students_s1_5-A', [
        {'attempt_id': 'old'}
      ]);
      final (rows, fromCache) =
          await students((_) => http.Response('{}', 503), language: 'uz');
      expect(fromCache, isTrue);
      expect(rows.single['attempt_id'], 'old');

      // The language-specific copy wins over the legacy one.
      final (ru, _) =
          await students((_) => http.Response('{}', 503), language: 'ru');
      expect(ru.single['attempt_id'], 'x');
    });
  });
}
