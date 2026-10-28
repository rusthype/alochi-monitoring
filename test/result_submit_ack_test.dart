// A queued result counts as synced ONLY when our server acknowledged it: a 2xx
// whose body is a JSON object carrying ok / id / duplicate. A 3xx or a 2xx with
// an HTML page (captive portal, proxy) is retryable, never synced. 429 / 503
// carry the server's Retry-After through to the sync scheduler.
import 'dart:convert';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/models/models.dart';
import 'package:alochi_monitoring/core/sync/server_backoff.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _result = TestResult(
  packageId: 'pkg',
  variant: 1,
  mathScore: 1,
  engScore: 2,
  totalPct: 50,
  answers: {'1': 'a'},
  deviceId: 'dev',
);

http.Response _jsonBody(Object body, int status,
        {Map<String, String> headers = const {}}) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json', ...headers});

http.Response _html(int status) =>
    http.Response('<html><body>Please log in to the wifi</body></html>', status,
        headers: {'content-type': 'text/html'});

Future<T> _with<T>(
    http.Response Function() respond, Future<T> Function() body) {
  return http.runWithClient(body, () => MockClient((_) async => respond()));
}

void main() {
  final a = MonitoringApi();
  tearDown(ServerBackoff.clear);

  final calls = <String, Future<Map<String, dynamic>> Function()>{
    'local': () => a.submitLocalResultFull({'x': 1}, 't'),
    'report': () => a.submitQuestionReport({'x': 1}, 't'),
    'online': () => a.submitResultFull(_result, idempotencyToken: 't'),
  };

  group('only a real acknowledgement is synced', () {
    for (final e in calls.entries) {
      test('${e.key}: 302 redirect is retryable', () async {
        final r = await _with(
            () => http.Response('', 302,
                headers: {'location': 'http://portal.local/login'}),
            e.value);
        expect(r['synced'], false);
        expect(r['permanent'], isNot(true));
      });
      test('${e.key}: 302 with a JSON object body is retryable', () async {
        final r =
            await _with(() => _jsonBody({'id': 'x', 'ok': true}, 302), e.value);
        expect(r['synced'], false);
        expect(r['permanent'], isNot(true));
      });
      test('${e.key}: HTML 200 (captive portal) is retryable', () async {
        final r = await _with(() => _html(200), e.value);
        expect(r['synced'], false);
        expect(r['permanent'], isNot(true));
      });
      test('${e.key}: JSON but not an object is retryable', () async {
        final r = await _with(() => _jsonBody([1, 2], 200), e.value);
        expect(r['synced'], false);
        expect(r['permanent'], isNot(true));
      });
      test('${e.key}: JSON object without ok/id/duplicate is retryable',
          () async {
        final r =
            await _with(() => _jsonBody({'hello': 'world'}, 200), e.value);
        expect(r['synced'], false);
        expect(r['permanent'], isNot(true));
      });
      test('${e.key}: {ok:true,id} (201) is synced', () async {
        final r = await _with(
            () => _jsonBody({'ok': true, 'id': 'abc'}, 201), e.value);
        expect(r['synced'], true);
      });
    }
    for (final key in ['local', 'online']) {
      test('$key: duplicate reply is synced', () async {
        final r = await _with(
            () => _jsonBody({'ok': true, 'duplicate': true, 'sent': 0}, 200),
            calls[key]!);
        expect(r['synced'], true);
      });
    }
  });

  group('diagnostic finish', () {
    final kiosk = DiagnosticKioskApi();
    Future<Map<String, dynamic>> finish() =>
        kiosk.submitFinishOffline({'attempt_id': 'a'}, 't');

    test('HTML 200 is retryable', () async {
      final r = await _with(() => _html(200), finish);
      expect(r['synced'], false);
      expect(r['permanent'], isNot(true));
    });
    test('302 is retryable', () async {
      final r = await _with(() => http.Response('', 302), finish);
      expect(r['synced'], false);
      expect(r['permanent'], isNot(true));
    });
    test('200 with a JSON object is synced', () async {
      final r = await _with(
          () => _jsonBody({'finished': true, 'score_math': 7}, 200), finish);
      expect(r['synced'], true);
      expect(r['score_math'], 7);
    });
  });

  group('Retry-After', () {
    test('seconds', () {
      expect(ServerBackoff.parse('30'), const Duration(seconds: 30));
    });
    test('HTTP date relative to now', () {
      final now = DateTime.utc(2026, 10, 29, 10, 0, 0);
      expect(ServerBackoff.parse('Thu, 29 Oct 2026 10:01:30 GMT', now: now),
          const Duration(seconds: 90));
    });
    test('capped at 5 minutes, garbage and negatives ignored', () {
      expect(ServerBackoff.parse('99999'), const Duration(minutes: 5));
      expect(ServerBackoff.parse('abc'), isNull);
      expect(ServerBackoff.parse('-4'), isNull);
      expect(ServerBackoff.parse(null), isNull);
      expect(ServerBackoff.parse(''), isNull);
    });

    for (final status in [429, 503]) {
      for (final e in calls.entries) {
        test('${e.key}: $status exposes retry_after_s', () async {
          final r = await _with(
              () => _jsonBody({'detail': 'slow down'}, status,
                  headers: {'retry-after': '45'}),
              e.value);
          expect(r['synced'], false);
          expect(r['permanent'], isNot(true));
          expect(r['retry_after_s'], 45);
        });
      }
    }

    test('other statuses ignore Retry-After', () async {
      final r = await _with(
          () => _jsonBody({'detail': 'x'}, 500, headers: {'retry-after': '45'}),
          calls['local']!);
      expect(r['retry_after_s'], isNull);
    });

    test('note keeps the longest wait and reports remaining', () {
      ServerBackoff.note(const Duration(seconds: 20));
      ServerBackoff.note(const Duration(seconds: 5));
      expect(ServerBackoff.active, isTrue);
      expect(
          ServerBackoff.remaining(), greaterThan(const Duration(seconds: 15)));
      ServerBackoff.clear();
      expect(ServerBackoff.active, isFalse);
      expect(ServerBackoff.remaining(), Duration.zero);
    });
  });
}
