// lib/features/diagnostic/data/diagnostic_pin_verifier.dart
//
// The one place that decides whether a typed kiosk PIN is right. The server
// is the authority (`DiagnosticKioskApi.verifyPin`); the school list's legacy
// `kiosk_pin` is only a fallback for a backend without that route, and offline
// the cached sha256('<school_id>:<pin>') is compared. The plain PIN is never
// stored or logged.
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/api/api_client.dart' show ApiException;
import '../../../core/db/diagnostic_kiosk_cache.dart';
import 'diagnostic_kiosk_api.dart';

enum DiagnosticPinResult { ok, wrong, throttled, noInternet, error }

String _hashKey(String schoolId) => 'pin_hash_$schoolId';

String diagnosticPinHash(String schoolId, String pin) =>
    sha256.convert(utf8.encode('${schoolId.toLowerCase()}:$pin')).toString();

/// [legacyPin]: the school list row's `kiosk_pin` ('' when absent).
Future<DiagnosticPinResult> verifyDiagnosticPin({
  required String schoolId,
  required String pin,
  String legacyPin = '',
  DiagnosticKioskApi? api,
}) async {
  final typed = pin.trim();
  DiagnosticPinResult legacy(DiagnosticPinResult none) => legacyPin.isEmpty
      ? none
      : (typed == legacyPin
          ? DiagnosticPinResult.ok
          : DiagnosticPinResult.wrong);
  // Cached hash, else the list pin, else [none]: no server verdict available.
  Future<DiagnosticPinResult> local(DiagnosticPinResult none) async {
    final cached = await DiagnosticKioskCache.load(_hashKey(schoolId));
    if (cached is String && cached.isNotEmpty) {
      return diagnosticPinHash(schoolId, typed) == cached.toLowerCase()
          ? DiagnosticPinResult.ok
          : DiagnosticPinResult.wrong;
    }
    return legacy(none);
  }

  try {
    final hash = await (api ?? diagnosticKioskApi).verifyPin(schoolId, typed);
    await DiagnosticKioskCache.save(_hashKey(schoolId), hash);
    return DiagnosticPinResult.ok;
  } on ApiException catch (e) {
    switch (e.statusCode) {
      case 403:
        return DiagnosticPinResult.wrong;
      case 429:
        // One shared school NAT IP: a student looping verify-pin must not lock
        // every PC out, so compare locally when a cached hash / list pin exists.
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
}
