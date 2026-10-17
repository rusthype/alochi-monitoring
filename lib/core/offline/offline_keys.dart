// lib/core/offline/offline_keys.dart
//
// Public keys for the offline USB flow, baked in at build time:
//
//   flutter build windows --release \
//     --dart-define=OFFLINE_SIGNING_PUBKEY_B64=$(base64 -w0 < signing_public.pem) \
//     --dart-define=OFFLINE_RESULTS_PUBKEY_B64=$(base64 -w0 < results_public.pem)
//
// The defaults are EMPTY on purpose. Release builds must never fall back to
// the public test keys that live in the backend fixtures (their private halves
// are in the repo): with no key configured offline mode is simply disabled.
import 'dart:convert';

import 'package:pointycastle/export.dart' show RSAPublicKey;

import 'offline_crypto.dart';

class OfflineKeys {
  static const String _signingB64 =
      String.fromEnvironment('OFFLINE_SIGNING_PUBKEY_B64');
  static const String _resultsB64 =
      String.fromEnvironment('OFFLINE_RESULTS_PUBKEY_B64');

  /// PEM text of the manifest-signing public key (null = not configured).
  final String? signingPem;

  /// PEM text of the results (.alochires key wrap) public key.
  final String? resultsPem;

  const OfflineKeys({this.signingPem, this.resultsPem});

  factory OfflineKeys.fromEnvironment() => OfflineKeys(
        signingPem: _decode(_signingB64),
        resultsPem: _decode(_resultsB64),
      );

  /// Process-wide keys. Tests / the loader receive their own instance, so
  /// this is only the production default.
  static OfflineKeys current = OfflineKeys.fromEnvironment();

  /// Both keys must be present AND parse — otherwise offline mode is off.
  bool get isConfigured {
    try {
      signingKey;
      resultsKey;
      return true;
    } catch (_) {
      return false;
    }
  }

  RSAPublicKey get signingKey => _parse(signingPem, 'signing');
  RSAPublicKey get resultsKey => _parse(resultsPem, 'results');

  static RSAPublicKey _parse(String? pem, String name) {
    if (pem == null || pem.trim().isEmpty) {
      throw StateError('offline $name public key is not configured');
    }
    return OfflineCrypto.parseRsaPublicKeyPem(pem);
  }

  /// Accepts either base64(PEM) (the dart-define form) or a raw PEM.
  static String? _decode(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('-----')) return v;
    try {
      return utf8.decode(base64.decode(base64.normalize(v)));
    } catch (_) {
      return null;
    }
  }
}
