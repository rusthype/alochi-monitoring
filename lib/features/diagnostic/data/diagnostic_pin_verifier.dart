// lib/features/diagnostic/data/diagnostic_pin_verifier.dart
//
// The one place that decides whether a typed kiosk PIN is right. The server
// is the authority (`DiagnosticKioskApi.verifyPin`); the school list's legacy
// `kiosk_pin` is only a fallback for a backend without that route.
//
// Offline, the client compares against a LOCAL salted slow verifier it derived
// itself the last time the server confirmed the PIN: PBKDF2-HMAC-SHA256(pin,
// random salt, iterations). The server's `pin_hash` is ignored (it is an
// unsalted sha256 over 10k possible PINs). The verifier expires after
// [kDiagnosticPinCacheTtl] and is deleted on a server 403 (wrong / changed
// PIN). The plain PIN is never stored or logged.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart' show ApiException;
import '../../../core/db/diagnostic_kiosk_cache.dart';
import '../../../core/local_server/hub_guard.dart' show constantTimeEquals;
import '../../../core/offline/offline_crypto.dart';
import 'diagnostic_kiosk_api.dart';

enum DiagnosticPinResult { ok, wrong, throttled, noInternet, error }

/// A cached verifier older than this is treated as absent.
const kDiagnosticPinCacheTtl = Duration(days: 14);

/// PBKDF2 cost. ~0.3 s on a dev machine; runs off the UI isolate.
const kDiagnosticPinKdfIterations = 100000;

// Refuse stored iteration counts outside this range (corrupt / hostile entry
// must not hang the kiosk).
const _maxStoredIterations = 1000000;
// A verifier "saved" later than now + this means the clock was rolled back.
const _clockSkewTolerance = Duration(minutes: 5);

/// Storage for the per-school offline verifier.
abstract class DiagnosticPinCache {
  Future<Object?> load(String schoolId);
  Future<void> save(String schoolId, Map<String, Object?> entry);
  Future<void> clear(String schoolId);
}

/// Default: the encrypted-at-rest [DiagnosticKioskCache].
class KioskDiagnosticPinCache implements DiagnosticPinCache {
  const KioskDiagnosticPinCache();
  static String _key(String schoolId) => 'pin_hash_$schoolId';

  @override
  Future<Object?> load(String schoolId) =>
      DiagnosticKioskCache.load(_key(schoolId));
  @override
  Future<void> save(String schoolId, Map<String, Object?> entry) =>
      DiagnosticKioskCache.save(_key(schoolId), entry);
  @override
  Future<void> clear(String schoolId) =>
      DiagnosticKioskCache.remove(_key(schoolId));
}

/// Builds a v2 verifier `{v, salt, iter, hash, savedAt}` for [pin].
Future<Map<String, Object?>> diagnosticPinEntry(
  String pin, {
  required DateTime now,
  int iterations = kDiagnosticPinKdfIterations,
}) async {
  final salt = OfflineCrypto.randomBytes(16);
  final key = await OfflineCrypto.deriveKeyAsync(pin, salt, iterations);
  return {
    'v': 2,
    'salt': base64Encode(salt),
    'iter': iterations,
    'hash': base64Encode(key),
    'savedAt': now.millisecondsSinceEpoch,
  };
}

/// ok / wrong from a cached [entry], or null when it is absent, malformed,
/// expired or from the future (treat as no cache).
Future<DiagnosticPinResult?> _compare(
    Object? entry, String pin, DateTime now) async {
  if (entry is! Map || entry['v'] != 2) return null;
  final salt = entry['salt'], hash = entry['hash'];
  final iter = entry['iter'], savedAt = entry['savedAt'];
  if (salt is! String || hash is! String || iter is! int || savedAt is! int) {
    return null;
  }
  if (iter < 1 || iter > _maxStoredIterations) return null;
  final age = now.difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
  if (age > kDiagnosticPinCacheTtl || age < -_clockSkewTolerance) return null;
  try {
    final key = await OfflineCrypto.deriveKeyAsync(
        pin, Uint8List.fromList(base64Decode(salt)), iter);
    return constantTimeEquals(base64Encode(key), hash)
        ? DiagnosticPinResult.ok
        : DiagnosticPinResult.wrong;
  } on FormatException {
    return null; // bad base64
  }
}

/// [legacyPin]: the school list row's `kiosk_pin` ('' when absent).
/// [cache] / [now] are injectable for tests.
Future<DiagnosticPinResult> verifyDiagnosticPin({
  required String schoolId,
  required String pin,
  String legacyPin = '',
  DiagnosticKioskApi? api,
  DiagnosticPinCache cache = const KioskDiagnosticPinCache(),
  DateTime Function()? now,
}) async {
  final clock = now ?? DateTime.now;
  final typed = pin.trim();
  DiagnosticPinResult legacy(DiagnosticPinResult none) => legacyPin.isEmpty
      ? none
      : (typed == legacyPin
          ? DiagnosticPinResult.ok
          : DiagnosticPinResult.wrong);
  // Fresh cached verifier, else the list pin, else [none]: no server verdict.
  Future<DiagnosticPinResult> local(DiagnosticPinResult none) async {
    DiagnosticPinResult? cached;
    try {
      cached = await _compare(await cache.load(schoolId), typed, clock());
    } catch (e) {
      debugPrint('PIN cache read failed: ${e.runtimeType}');
    }
    return cached ?? legacy(none);
  }

  try {
    await (api ?? diagnosticKioskApi).verifyPin(schoolId, typed);
  } on ApiException catch (e) {
    switch (e.statusCode) {
      case 403:
        // Wrong PIN, or the school changed it: the old verifier must not keep
        // working offline.
        try {
          await cache.clear(schoolId);
        } catch (e) {
          debugPrint('PIN cache clear failed: ${e.runtimeType}');
        }
        return DiagnosticPinResult.wrong;
      case 429:
        // One shared school NAT IP: a student looping verify-pin must not lock
        // every PC out, so compare locally when a cached verifier / list pin
        // exists.
        return local(DiagnosticPinResult.throttled);
      case 0:
        return local(DiagnosticPinResult.noInternet);
      default:
        // 404 / 5xx / anything else: an old backend without the route.
        return legacy(DiagnosticPinResult.error);
    }
  } catch (_) {
    // TLS handshake / certificate failures and other unmapped transport errors
    // escape DiagnosticKioskApi._send: same as being offline.
    return local(DiagnosticPinResult.noInternet);
  }
  // Server confirmed [typed]: remember a local salted verifier.
  try {
    await cache.save(schoolId, await diagnosticPinEntry(typed, now: clock()));
  } catch (e) {
    // Best-effort: a server 200 stays ok even if deriving/saving fails.
    debugPrint('PIN cache save failed: ${e.runtimeType}');
  }
  return DiagnosticPinResult.ok;
}
