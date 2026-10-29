// A finished exam is only ever dropped from the offline queue when the server
// DEFINITIVELY rejected the payload (400 / 409 / 422) and then it is HELD, not dropped (wave 8a). Everything else - auth
// glitches, proxies, 404 during a deploy, 413, 429, 5xx, captive-portal HTML,
// no network - must stay retryable.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/models/models.dart';
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

http.Response _json(int status) => http.Response.bytes(
    utf8.encode(jsonEncode({'detail': 'x', 'id': 'r1'})), status,
    headers: {'content-type': 'application/json'});

http.Response _html(int status) => http.Response(
    '<html><body>Please log in to the wifi</body></html>', status,
    headers: {'content-type': 'text/html'});

Future<T> _with<T>(
    http.Response Function() respond, Future<T> Function() body) {
  return http.runWithClient(body, () => MockClient((_) async => respond()));
}

Future<T> _withThrow<T>(Object error, Future<T> Function() body) {
  return http.runWithClient(body, () => MockClient((_) async => throw error));
}

const _retryable = [401, 403, 404, 408, 413, 429, 500, 502, 503];

void main() {
  final a = MonitoringApi();

  group('submitResultFull', () {
    for (final s in [400, 422]) {
      test('$s is permanent', () async {
        final r = await _with(() => _json(s), () => a.submitResultFull(_result));
        expect(r['synced'], false);
        expect(r['permanent'], true);
        // Wave 8a: a rejected finished exam is HELD (rejected_results), not
        // dropped.
        expect(r['rejected'], true);
        expect(r['reject_reason'], isA<String>());
      });
    }
    test('409 means the server already has it -> synced', () async {
      final r = await _with(() => _json(409), () => a.submitResultFull(_result));
      expect(r['synced'], true);
    });
    for (final s in _retryable) {
      test('$s stays retryable', () async {
        final r = await _with(() => _json(s), () => a.submitResultFull(_result));
        expect(r['synced'], false);
        expect(r['permanent'], isNot(true), reason: 'status $s');
        expect(r['retryable'], true);
      });
    }
    for (final s in [200, 400, 403, 404, 502]) {
      test('HTML body ($s) stays retryable', () async {
        final r = await _with(() => _html(s), () => a.submitResultFull(_result));
        expect(r['synced'], false);
        expect(r['permanent'], isNot(true), reason: 'html $s');
      });
    }
    test('network failure stays retryable', () async {
      final r = await _withThrow(const SocketException('down'),
          () => a.submitResultFull(_result));
      expect(r['synced'], false);
      expect(r['permanent'], isNot(true));
    });
  });

  group('rejection reason (400 / 422 result payloads)', () {
    http.Response body(int status, Object? b) => http.Response.bytes(
        utf8.encode(b is String ? b : jsonEncode(b)), status,
        headers: {'content-type': 'application/json'});

    test('machine error / code wins over free text', () {
      expect(
          resultRejectionReason(400, {'error': 'bad_answers', 'detail': 'x'}),
          'bad_answers');
      expect(resultRejectionReason(422, {'code': 'invalid'}), 'invalid');
    });
    test('free-text detail is truncated', () {
      final r = resultRejectionReason(400, {'detail': 'a' * 500});
      expect(r.length, lessThanOrEqualTo(80));
    });
    test('DRF field errors name only the fields, never the values', () {
      final r = resultRejectionReason(
          400, {'answers': ['secret-token-123'], 'total_pct': ['bad']});
      expect(r, contains('answers'));
      expect(r, isNot(contains('secret')));
    });
    test('absent / odd bodies fall back to http_<status>', () {
      expect(resultRejectionReason(422, null), 'http_422');
      expect(resultRejectionReason(400, {}), 'http_400');
      expect(resultRejectionReason(400, {'error': 42}), 'http_400');
    });
    test('online and local paths use the same reason', () async {
      final b = {'error': 'invalid_payload'};
      final on = await _with(
          () => body(400, b), () => a.submitResultFull(_result));
      final loc = await _with(
          () => body(422, b), () => a.submitLocalResultFull({'x': 1}, 't'));
      expect(on['reject_reason'], 'invalid_payload');
      expect(loc['reject_reason'], 'invalid_payload');
    });
    test('a non-JSON 400 body from our server is still held', () async {
      final r = await _with(() => body(400, 'oops'),
          () => a.submitLocalResultFull({'x': 1}, 't'));
      expect(r['rejected'], true);
      expect(r['reject_reason'], 'http_400');
    });
    test('keepUnsyncedResult: kept when retryable or rejected, not when dropped',
        () {
      expect(keepUnsyncedResult({'synced': false, 'retryable': true}), true);
      expect(
          keepUnsyncedResult(
              {'synced': false, 'permanent': true, 'rejected': true}),
          true);
      expect(keepUnsyncedResult({'synced': false, 'permanent': true}), false);
      expect(keepUnsyncedResult({'synced': true}), false);
    });
  });

  group('submitLocalResultFull / submitQuestionReport', () {
    final calls = <String, Future<Map<String, dynamic>> Function()>{
      'local': () => a.submitLocalResultFull({'x': 1}, 't'),
      'report': () => a.submitQuestionReport({'x': 1}, 't'),
    };
    for (final e in calls.entries) {
      // Local results split 409 (already stored vs rejected) - see
      // rejected_results_test.dart; the question report keeps 409 permanent.
      for (final s in [400, if (e.key == 'report') 409, 422]) {
        test('${e.key}: $s is permanent', () async {
          final r = await _with(() => _json(s), e.value);
          expect(r['synced'], false);
          expect(r['permanent'], true);
          // Result payloads are held on 400/422 (wave 8a); the question
          // report is not a result and keeps drop-on-permanent.
          expect(r['rejected'], e.key == 'local' ? true : isNull,
              reason: '${e.key} $s');
        });
      }
      for (final s in _retryable) {
        test('${e.key}: $s stays retryable', () async {
          final r = await _with(() => _json(s), e.value);
          expect(r['synced'], false);
          expect(r['permanent'], false, reason: 'status $s');
        });
      }
      for (final s in [200, 400, 403, 404, 502]) {
        test('${e.key}: HTML body ($s) stays retryable', () async {
          final r = await _with(() => _html(s), e.value);
          expect(r['permanent'], false, reason: 'html $s');
          expect(r['synced'], isNot(true));
        });
      }
      test('${e.key}: 200 is synced', () async {
        final r = await _with(() => _json(200), e.value);
        expect(r['synced'], true);
      });
      test('${e.key}: network failure stays retryable', () async {
        final r = await _withThrow(const SocketException('down'), e.value);
        expect(r['synced'], false);
        expect(r['permanent'], false);
      });
    }
  });
}
