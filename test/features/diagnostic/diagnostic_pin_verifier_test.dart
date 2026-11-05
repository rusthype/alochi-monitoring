// Kiosk PIN is checked by the server (kiosk/schools/<id>/verify-pin/); the
// list's `kiosk_pin` is only a fallback for an old backend, and only a sha256
// of '<school_id>:<pin>' is ever cached for offline use.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/diagnostic_kiosk_cache.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_pin_verifier.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _school = '3f2b8c1e-0000-4000-8000-000000000001';
const _pin = '4821';
final _hash = sha256.convert(utf8.encode('$_school:$_pin')).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationSupportDirectory'
                ? Directory.systemTemp.path
                : null);
  });

  Future<DiagnosticPinResult> check(
    http.Client client, {
    String pin = _pin,
    String legacyPin = '',
  }) =>
      http.runWithClient(
          () => verifyDiagnosticPin(
              schoolId: _school, pin: pin, legacyPin: legacyPin),
          () => client);

  http.Response ok() =>
      http.Response(jsonEncode({'ok': true, 'pin_hash': _hash}), 200);
  http.Response json(int status) =>
      http.Response(jsonEncode({'detail': "PIN noto'g'ri."}), status);
  final offline = MockClient((_) async => throw const SocketException('down'));

  test('online ok: posts the stripped pin and caches only the hash', () async {
    late http.Request sent;
    final r = await check(MockClient((req) async {
      sent = req;
      return ok();
    }), pin: ' $_pin ');
    expect(r, DiagnosticPinResult.ok);
    expect(
        sent.url.path, '/api/v1/diagnostic/kiosk/schools/$_school/verify-pin/');
    expect(jsonDecode(sent.body), {'pin': _pin});
    expect(await DiagnosticKioskCache.load('pin_hash_$_school'), _hash);
  });

  test('the plain PIN is never persisted', () async {
    await check(MockClient((_) async => ok()), legacyPin: _pin);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      expect('${prefs.get(k)}', isNot(contains(_pin)), reason: k);
    }
  });

  test('online wrong pin (403) is wrong, even if a legacy pin matches',
      () async {
    expect(await check(MockClient((_) async => json(403)), legacyPin: _pin),
        DiagnosticPinResult.wrong);
  });

  test('429 with nothing cached and no list pin is throttled', () async {
    expect(await check(MockClient((_) async => json(429))),
        DiagnosticPinResult.throttled);
  });

  test('429 with a cached hash compares it like offline (ok / wrong)',
      () async {
    await DiagnosticKioskCache.save('pin_hash_$_school', _hash);
    final throttled = MockClient((_) async => json(429));
    expect(await check(throttled), DiagnosticPinResult.ok);
    expect(await check(throttled, pin: '0000'), DiagnosticPinResult.wrong);
  });

  test('429 without a cache falls back to the list pin, else throttled',
      () async {
    final throttled = MockClient((_) async => json(429));
    expect(await check(throttled, legacyPin: _pin), DiagnosticPinResult.ok);
    expect(await check(throttled, legacyPin: '9999'), DiagnosticPinResult.wrong);
  });

  test('a TLS handshake failure behaves like offline and never throws',
      () async {
    final tls = MockClient((_) async => throw const HandshakeException('bad'));
    expect(await check(tls), DiagnosticPinResult.noInternet);
    expect(await check(tls, legacyPin: _pin), DiagnosticPinResult.ok);
    await DiagnosticKioskCache.save('pin_hash_$_school', _hash);
    expect(await check(tls), DiagnosticPinResult.ok);
    expect(await check(tls, pin: '0000'), DiagnosticPinResult.wrong);
  });

  test('any other exception is treated as offline too', () async {
    final boom = MockClient((_) async => throw StateError('boom'));
    expect(await check(boom), DiagnosticPinResult.noInternet);
  });

  test('route missing (old backend): falls back to the list kiosk_pin',
      () async {
    final html =
        MockClient((_) async => http.Response('<html>404</html>', 404));
    expect(await check(html, legacyPin: _pin), DiagnosticPinResult.ok);
    expect(await check(html, legacyPin: '9999'), DiagnosticPinResult.wrong);
    expect(await check(html), DiagnosticPinResult.error);
    expect(await check(MockClient((_) async => json(500)), legacyPin: _pin),
        DiagnosticPinResult.ok);
  });

  test('offline with a cached hash compares sha256(school:pin)', () async {
    await DiagnosticKioskCache.save('pin_hash_$_school', _hash);
    expect(await check(offline), DiagnosticPinResult.ok);
    expect(await check(offline, pin: '0000'), DiagnosticPinResult.wrong);
  });

  test('offline without a cached hash uses the list pin, else no-internet',
      () async {
    expect(await check(offline, legacyPin: _pin), DiagnosticPinResult.ok);
    expect(await check(offline, legacyPin: '9999'), DiagnosticPinResult.wrong);
    expect(await check(offline), DiagnosticPinResult.noInternet);
  });
}
