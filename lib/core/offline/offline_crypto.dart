// lib/core/offline/offline_crypto.dart
//
// Byte-level crypto for the offline USB formats (`.alochipack` / `.alochires`).
// The reference spec is the module docstring of the backend's
// apps/monitoring/services/offline_pack.py — keep this file in lock-step with it.
//
// Pure Dart (no Flutter imports) so it also runs under `dart run` and inside
// a worker Isolate.
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// Wrong PIN, tampered ciphertext or wrong AAD — GCM authentication failed.
class OfflineAuthException implements Exception {
  const OfflineAuthException();
  @override
  String toString() => 'OfflineAuthException';
}

class OfflineCrypto {
  OfflineCrypto._();

  static const int nonceLen = 12;
  static const int tagLen = 16;
  static const int keyLen = 32;
  static const String chainLabel = 'alochires-chain-v1';
  static final String zeroHash = '0' * 64;

  // ── KDF ───────────────────────────────────────────────────────────────────

  /// PBKDF2-HMAC-SHA256(pin as UTF-8, salt, iter, 32). CPU heavy (600k
  /// iterations) — call [deriveKeyAsync] from UI code.
  static Uint8List deriveKey(String pin, Uint8List salt, int iterations) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, keyLen));
    return kdf.process(Uint8List.fromList(utf8.encode(pin)));
  }

  /// Same as [deriveKey] but in a short-lived Isolate so the UI never freezes.
  /// The PIN only crosses into the worker as a message and is never logged.
  static Future<Uint8List> deriveKeyAsync(
      String pin, Uint8List salt, int iterations) {
    return Isolate.run(() => deriveKey(pin, salt, iterations));
  }

  // ── AES-256-GCM: nonce(12) || ciphertext || tag(16) ────────────────────────

  static Uint8List decryptBlob(Uint8List key, Uint8List aad, Uint8List blob) {
    if (blob.length < nonceLen + tagLen) throw const OfflineAuthException();
    final nonce = Uint8List.sublistView(blob, 0, nonceLen);
    final body = Uint8List.sublistView(blob, nonceLen);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), tagLen * 8, nonce, aad));
    try {
      return cipher.process(body);
    } on InvalidCipherTextException {
      throw const OfflineAuthException();
    }
  }

  static Uint8List encryptBlob(Uint8List key, Uint8List aad, Uint8List plain,
      {Uint8List? nonce}) {
    final n = nonce ?? randomBytes(nonceLen);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), tagLen * 8, n, aad));
    final ct = cipher.process(plain);
    return Uint8List.fromList([...n, ...ct]);
  }

  // ── HMAC chain ─────────────────────────────────────────────────────────────

  static Uint8List chainKeyOf(Uint8List packKey) =>
      Uint8List.fromList(crypto.Hmac(crypto.sha256, packKey)
          .convert(utf8.encode(chainLabel))
          .bytes);

  /// hex_lowercase(HMAC-SHA256(chain_key,
  ///   utf8(prev_hash + ":" + payload_json + ":" + meta_json))) -- format 2.
  /// Both JSON strings are hashed as TEXT, exactly as stored/exported.
  static String chainHash(Uint8List chainKey, String prevHash,
      String payloadJson, String metaJson) {
    return crypto.Hmac(crypto.sha256, chainKey)
        .convert(utf8.encode('$prevHash:$payloadJson:$metaJson'))
        .toString();
  }

  // ── RSA ────────────────────────────────────────────────────────────────────

  /// RSA PKCS#1 v1.5 + SHA-256 signature check over the exact [message] bytes.
  static bool verifyRsaSha256(
      RSAPublicKey key, Uint8List message, Uint8List signature) {
    try {
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
        ..init(false, PublicKeyParameter<RSAPublicKey>(key));
      return signer.verifySignature(message, RSASignature(signature));
    } catch (_) {
      // Malformed signature (wrong length etc.) is simply "not valid".
      return false;
    }
  }

  /// RSA-OAEP, SHA-256 + MGF1-SHA-256, empty label.
  static Uint8List rsaOaepWrap(RSAPublicKey key, Uint8List data) {
    final oaep = OAEPEncoding.withSHA256(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(key));
    return oaep.process(data);
  }

  // ── PEM (SubjectPublicKeyInfo / PKCS#1 public keys) ─────────────────────────

  static RSAPublicKey parseRsaPublicKeyPem(String pem) {
    final body = pem
        .replaceAll(RegExp(r'-----(BEGIN|END)[^-]*-----'), '')
        .replaceAll(RegExp(r'\s+'), '');
    final der = base64.decode(body);
    final top = _der(der, 0);
    if (top.tag != 0x30) throw const FormatException('bad public key');
    final first = _der(der, top.start);
    BigInt n, e;
    if (first.tag == 0x30) {
      // SPKI: SEQUENCE { SEQUENCE algId, BIT STRING { RSAPublicKey } }
      final bits = _der(der, first.end);
      if (bits.tag != 0x03) throw const FormatException('bad public key');
      // skip the "unused bits" byte
      final inner = Uint8List.sublistView(der, bits.start + 1, bits.end);
      final seq = _der(inner, 0);
      final nTlv = _der(inner, seq.start);
      final eTlv = _der(inner, nTlv.end);
      n = _int(inner, nTlv);
      e = _int(inner, eTlv);
    } else {
      // PKCS#1: SEQUENCE { INTEGER n, INTEGER e }
      final eTlv = _der(der, first.end);
      n = _int(der, first);
      e = _int(der, eTlv);
    }
    return RSAPublicKey(n, e);
  }

  static _Tlv _der(Uint8List b, int off) {
    final tag = b[off];
    var len = b[off + 1];
    var p = off + 2;
    if (len & 0x80 != 0) {
      final cnt = len & 0x7f;
      len = 0;
      for (var i = 0; i < cnt; i++) {
        len = (len << 8) | b[p++];
      }
    }
    return _Tlv(tag, p, p + len);
  }

  static BigInt _int(Uint8List b, _Tlv t) {
    var r = BigInt.zero;
    for (var i = t.start; i < t.end; i++) {
      r = (r << 8) | BigInt.from(b[i]);
    }
    return r;
  }

  // ── misc ───────────────────────────────────────────────────────────────────

  static final Random _rng = Random.secure();

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  static String sha256Hex(List<int> data) =>
      crypto.sha256.convert(data).toString();
}

class _Tlv {
  final int tag;
  final int start;
  final int end;
  const _Tlv(this.tag, this.start, this.end);
}
