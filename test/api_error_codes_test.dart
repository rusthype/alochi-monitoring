// Transport failures carry a stable machine `code` (the UI maps it to ARB
// text) and the list endpoints throw instead of returning a fake empty list.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/api/api_error_text.dart';
import 'package:alochi_monitoring/l10n/app_localizations_ru.dart';
import 'package:alochi_monitoring/l10n/app_localizations_uz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<T> _respond<T>(http.Response r, Future<T> Function() body) =>
    http.runWithClient(body, () => MockClient((_) async => r));

Future<T> _throw<T>(Object e, Future<T> Function() body) =>
    http.runWithClient(body, () => MockClient((_) async => throw e));

Future<ApiException> _caught(Future<Object?> f) async {
  try {
    await f;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  final a = MonitoringApi();
  Future<Object?> call() => a.sessionResume('k');

  group('_send maps transport errors to codes', () {
    final cases = <String, (Object, String)>{
      'timeout': (TimeoutException('t'), kApiTimeout),
      'socket': (const SocketException('down'), kApiNetwork),
      'handshake': (const HandshakeException('bad cert'), kApiTls),
      'tls': (const TlsException('tls'), kApiTls),
      'format': (const FormatException('x'), kApiBadResponse),
      'http': (const HttpException('x'), kApiNetwork),
      'client': (http.ClientException('x'), kApiNetwork),
      'os': (const OSError('x', 10054), kApiNetwork),
    };
    for (final e in cases.entries) {
      test(e.key, () async {
        final ex = await _caught(_throw(e.value.$1, call));
        expect(ex.code, e.value.$2);
        expect(ex.statusCode, 0);
      });
    }
  });

  test('HTML 200 body is bad_response, not a FormatException', () async {
    final ex = await _caught(_respond(
        http.Response('<html>portal</html>', 200,
            headers: {'content-type': 'text/html'}),
        call));
    expect(ex.code, kApiBadResponse);
  });

  test('fetchGroups throws on non-200, HTML and network errors', () async {
    for (final r in [500, 403, 404]) {
      await _caught(_respond(
          http.Response.bytes(utf8.encode('[]'), r), () => a.fetchGroups('1')));
    }
    final html = await _caught(_respond(
        http.Response('<html/>', 200), () => a.fetchGroups('1')));
    expect(html.code, kApiBadResponse);
    await _caught(_throw(const SocketException('x'), () => a.fetchGroups('1')));
  });

  test('fetchGroups / fetchStudents return a real empty list for []', () async {
    final ok = http.Response.bytes(utf8.encode('[]'), 200);
    expect(await _respond(ok, () => a.fetchGroups('1')), isEmpty);
    expect(await _respond(ok, () => a.fetchStudents('g')), isEmpty);
  });

  test('fetchStudents throws on non-200 and non-list bodies', () async {
    await _caught(_respond(
        http.Response.bytes(utf8.encode('[]'), 502), () => a.fetchStudents('g')));
    final ex = await _caught(_respond(
        http.Response.bytes(utf8.encode('{"a":1}'), 200),
        () => a.fetchStudents('g')));
    expect(ex.code, kApiBadResponse);
  });

  group('localizedApiError never leaks the raw message', () {
    final uz = AppLocalizationsUz();
    final ru = AppLocalizationsRu();
    test('codes map to ARB strings', () {
      for (final code in [kApiTimeout, kApiNetwork, kApiTls]) {
        final e = ApiException(0, 'RAW DEBUG', code: code);
        expect(localizedApiError(uz, e), uz.connectionError);
        expect(localizedApiError(ru, e), ru.connectionError);
      }
      expect(
          localizedApiError(
              uz, const ApiException(200, 'RAW', code: kApiBadResponse)),
          uz.serverErrorRetry);
      expect(localizedApiError(uz, const ApiException(503, 'RAW')),
          uz.serverErrorRetry);
      expect(localizedApiError(uz, const ApiException(429, 'RAW')),
          uz.tooManyAttempts);
      expect(localizedApiError(uz, const ApiException(404, 'RAW')),
          uz.loadFailed);
      expect(localizedApiError(uz, StateError('RAW')), uz.loadFailed);
      expect(localizedApiError(uz, const SocketException('RAW')),
          uz.connectionError);
      for (final e in [
        const ApiException(0, 'RAW', code: kApiTls),
        const ApiException(404, 'RAW'),
        StateError('RAW'),
      ]) {
        expect(localizedApiError(uz, e), isNot(contains('RAW')));
      }
    });
  });
}
