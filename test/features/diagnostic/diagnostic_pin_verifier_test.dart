// Kiosk PIN is checked by the server (kiosk/schools/<id>/verify-pin/); the
// list's `kiosk_pin` is only a fallback for an old backend. For offline use
// the client caches a LOCAL salted PBKDF2 verifier (v2) that expires after 14
// days and is dropped on a server 403; the server's `pin_hash` is ignored.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/diagnostic_kiosk_cache.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_pin_verifier.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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

  // Fast seeded verifier (low iteration count; the iteration count is stored
  // in the entry so the verifier honours it).
  Future<Map<String, Object?>> entry(String pin,
          {DateTime? at, int iter = 1000}) =>
      diagnosticPinEntry(pin, now: at ?? DateTime.now(), iterations: iter);
  Future<void> seed(String pin, {DateTime? at}) async => DiagnosticKioskCache
      .save('pin_hash_$_school', await entry(pin, at: at));
  Future<Object?> stored() => DiagnosticKioskCache.load('pin_hash_$_school');

  test('online ok: posts the stripped pin and caches a v2 PBKDF2 verifier',
      () async {
    late http.Request sent;
    final r = await check(MockClient((req) async {
      sent = req;
      return ok();
    }), pin: ' $_pin ');
    expect(r, DiagnosticPinResult.ok);
    expect(
        sent.url.path, '/api/v1/diagnostic/kiosk/schools/$_school/verify-pin/');
    expect(jsonDecode(sent.body), {'pin': _pin});
    final e = (await stored()) as Map;
    expect(e['v'], 2);
    expect(e['iter'], kDiagnosticPinKdfIterations);
    expect(base64Decode(e['salt'] as String), hasLength(16));
    expect(base64Decode(e['hash'] as String), hasLength(32));
    expect(e['savedAt'], isA<int>());
    // Neither the plain PIN nor the server's sha256 form is stored.
    final raw = jsonEncode(e);
    expect(raw, isNot(contains(_pin)));
    expect(raw, isNot(contains(_hash)));
    expect(raw, isNot(contains(
        sha256.convert(utf8.encode('$_school:$_pin')).toString())));
  });

  test('every save draws a fresh random salt', () async {
    await check(MockClient((_) async => ok()));
    final a = (await stored()) as Map;
    await check(MockClient((_) async => ok()));
    final b = (await stored()) as Map;
    expect(a['salt'], isNot(b['salt']));
    expect(a['hash'], isNot(b['hash']));
  });

  test('a throwing cache save never turns a server 200 into a failure',
      () async {
    final cache = _FakeCache(throwOnSave: true);
    final r = await http.runWithClient(
        () => verifyDiagnosticPin(
            schoolId: _school, pin: _pin, cache: cache),
        () => MockClient((_) async => ok()));
    expect(r, DiagnosticPinResult.ok);
    expect(cache.saveCalls, 1, reason: 'the save was attempted');
  });

  test('a throwing cache clear never turns a server 403 into a failure',
      () async {
    final cache = _FakeCache(throwOnClear: true);
    final r = await http.runWithClient(
        () => verifyDiagnosticPin(
            schoolId: _school, pin: _pin, cache: cache),
        () => MockClient((_) async => json(403)));
    expect(r, DiagnosticPinResult.wrong);
    expect(cache.clearCalls, 1);
  });

  test('a throwing cache load is treated as absent when offline', () async {
    final cache = _FakeCache(throwOnLoad: true);
    Future<DiagnosticPinResult> run(String legacy) => http.runWithClient(
        () => verifyDiagnosticPin(
            schoolId: _school, pin: _pin, legacyPin: legacy, cache: cache),
        () => offline);
    expect(await run(''), DiagnosticPinResult.noInternet);
    expect(await run(_pin), DiagnosticPinResult.ok);
  });

  test('the plain PIN is never persisted (default cache, raw prefs)',
      () async {
    await check(MockClient((_) async => ok()), legacyPin: _pin);
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys()) {
      expect('${prefs.get(k)}', isNot(contains(_pin)), reason: k);
    }
  });

  test('the plain PIN is never logged', () async {
    final logs = <String>[];
    final old = debugPrint;
    debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');
    try {
      await check(MockClient((_) async => ok()), legacyPin: _pin);
      await check(offline);
    } finally {
      debugPrint = old;
    }
    expect(logs.join('\n'), isNot(contains(_pin)));
  });

  test('online wrong pin (403) is wrong, even if a legacy pin matches',
      () async {
    expect(await check(MockClient((_) async => json(403)), legacyPin: _pin),
        DiagnosticPinResult.wrong);
  });

  test('403 deletes the cached verifier, so the old PIN stops working offline',
      () async {
    await seed(_pin);
    expect(await check(offline), DiagnosticPinResult.ok);
    // School changed its PIN: the server now rejects the old one.
    expect(await check(MockClient((_) async => json(403))),
        DiagnosticPinResult.wrong);
    expect(await stored(), isNull);
    expect(await check(offline), DiagnosticPinResult.noInternet);
  });

  test('403 for one school leaves another school\'s verifier alone', () async {
    await seed(_pin);
    await http.runWithClient(
        () => verifyDiagnosticPin(schoolId: 'other-school', pin: '1'),
        () => MockClient((_) async => json(403)));
    expect(await stored(), isNotNull);
  });

  test('429 with nothing cached and no list pin is throttled', () async {
    expect(await check(MockClient((_) async => json(429))),
        DiagnosticPinResult.throttled);
  });

  test('429 with a cached hash compares it like offline (ok / wrong)',
      () async {
    await seed(_pin);
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
    await seed(_pin);
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

  test('offline with a cached v2 verifier compares PBKDF2(pin, salt)',
      () async {
    await seed(_pin);
    expect(await check(offline), DiagnosticPinResult.ok);
    expect(await check(offline, pin: '0000'), DiagnosticPinResult.wrong);
    expect(await check(offline, pin: ' $_pin '), DiagnosticPinResult.ok);
  });

  test('a cached verifier wins over a (stale) list pin offline', () async {
    await seed(_pin);
    expect(await check(offline, legacyPin: '9999'), DiagnosticPinResult.ok);
  });

  test('TTL: 14 days old is absent (list pin, else no-internet)', () async {
    final t0 = DateTime(2026, 11, 1, 12);
    await seed(_pin, at: t0);
    Future<DiagnosticPinResult> at(Duration age, {String legacy = ''}) =>
        http.runWithClient(
            () => verifyDiagnosticPin(
                schoolId: _school,
                pin: _pin,
                legacyPin: legacy,
                now: () => t0.add(age)),
            () => offline);
    expect(kDiagnosticPinCacheTtl, const Duration(days: 14));
    expect(await at(const Duration(days: 13, hours: 23)),
        DiagnosticPinResult.ok);
    expect(await at(const Duration(days: 14, minutes: 1)),
        DiagnosticPinResult.noInternet);
    expect(await at(const Duration(days: 14, minutes: 1), legacy: _pin),
        DiagnosticPinResult.ok);
    expect(await at(const Duration(days: 30), legacy: '9999'),
        DiagnosticPinResult.wrong);
  });

  test('a verifier saved in the future (clock rolled back) is absent',
      () async {
    final t0 = DateTime(2026, 11, 1, 12);
    await seed(_pin, at: t0.add(const Duration(days: 30)));
    final r = await http.runWithClient(
        () => verifyDiagnosticPin(
            schoolId: _school, pin: _pin, now: () => t0),
        () => offline);
    expect(r, DiagnosticPinResult.noInternet);
  });

  test('legacy / corrupt cache values are absent, never ok', () async {
    final cache = _FakeCache();
    Future<DiagnosticPinResult> run() => http.runWithClient(
        () => verifyDiagnosticPin(
            schoolId: _school, pin: _pin, cache: cache),
        () => offline);
    for (final bad in <Object?>[
      _hash, // the old v1 sha256 string
      <String, Object?>{'v': 1},
      <String, Object?>{'v': 2, 'salt': 'x', 'iter': 0, 'hash': 'y'},
      <String, Object?>{
        ...await entry(_pin),
        'iter': 999999999 // absurd cost: refuse rather than hang the kiosk
      },
    ]) {
      cache.value = bad;
      expect(await run(), DiagnosticPinResult.noInternet, reason: '$bad');
    }
  });

  test('default 100k-iteration verify stays well under a second', () async {
    final e = await diagnosticPinEntry(_pin, now: DateTime.now());
    expect(e['iter'], 100000);
    await DiagnosticKioskCache.save('pin_hash_$_school', e);
    final sw = Stopwatch()..start();
    final r = await check(offline);
    sw.stop();
    // ignore: avoid_print
    print('KDF offline compare (100k iter, incl. isolate spawn): '
        '${sw.elapsedMilliseconds} ms');
    expect(r, DiagnosticPinResult.ok);
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('offline without a cached hash uses the list pin, else no-internet',
      () async {
    expect(await check(offline, legacyPin: _pin), DiagnosticPinResult.ok);
    expect(await check(offline, legacyPin: '9999'), DiagnosticPinResult.wrong);
    expect(await check(offline), DiagnosticPinResult.noInternet);
  });
}

class _FakeCache implements DiagnosticPinCache {
  _FakeCache({
    this.throwOnLoad = false,
    this.throwOnSave = false,
    this.throwOnClear = false,
  });
  final bool throwOnLoad, throwOnSave, throwOnClear;
  Object? value;
  int saveCalls = 0, clearCalls = 0;

  @override
  Future<Object?> load(String schoolId) async {
    if (throwOnLoad) throw StateError('disk');
    return value;
  }

  @override
  Future<void> save(String schoolId, Map<String, Object?> entry) async {
    saveCalls++;
    if (throwOnSave) throw StateError('disk');
    value = entry;
  }

  @override
  Future<void> clear(String schoolId) async {
    clearCalls++;
    if (throwOnClear) throw StateError('disk');
    value = null;
  }
}
