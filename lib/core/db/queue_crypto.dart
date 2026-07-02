// lib/core/db/queue_crypto.dart
// AES-GCM encryption for offline queue payloads at rest.
//
// Queue rows sit in a plain SQLite file at %AppData%/.../monitoring_queue.db
// on a shared kiosk machine. Encrypting the payload column means a student
// with local file access can no longer read or silently edit their own (or
// another student's) queued score before it syncs — and GCM's auth tag
// means a hand-tampered row fails to decrypt instead of being silently
// accepted (it just retries/purges like any other corrupt row).
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class QueueCrypto {
  static const _storage = FlutterSecureStorage(
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  );
  static const _keyStorageKey = 'queue_aes_key_v1';
  static const _prefix = 'ENC1:';

  static Future<enc.Key>? _keyFuture;

  static Future<enc.Key> _getKey() {
    return _keyFuture ??= _loadOrCreateKey();
  }

  static Future<enc.Key> _loadOrCreateKey() async {
    var stored = await _storage.read(key: _keyStorageKey);
    if (stored == null) {
      final generated = enc.Key.fromSecureRandom(32);
      stored = base64Encode(generated.bytes);
      await _storage.write(key: _keyStorageKey, value: stored);
    }
    return enc.Key(base64Decode(stored));
  }

  /// Pure encrypt given an explicit key — split out from [encryptPayload]
  /// so the crypto itself is unit-testable without touching secure storage.
  @visibleForTesting
  static String encryptWithKey(String plainJson, enc.Key key) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plainJson, iv: iv);
    return '$_prefix${base64Encode(iv.bytes)}:${encrypted.base64}';
  }

  /// Pure decrypt given an explicit key. Rows written before encryption
  /// shipped are plain JSON with no [_prefix] — returned as-is (legacy
  /// compat during the rollout window).
  @visibleForTesting
  static String decryptWithKey(String stored, enc.Key key) {
    if (!stored.startsWith(_prefix)) return stored;
    final body = stored.substring(_prefix.length);
    final parts = body.split(':');
    if (parts.length != 2) return stored;
    final iv = enc.IV(base64Decode(parts[0]));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    return encrypter.decrypt64(parts[1], iv: iv);
  }

  static Future<String> encryptPayload(String plainJson) async =>
      encryptWithKey(plainJson, await _getKey());

  static Future<String> decryptPayload(String stored) async =>
      decryptWithKey(stored, await _getKey());
}
