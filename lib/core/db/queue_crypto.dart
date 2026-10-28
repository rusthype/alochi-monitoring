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
import 'dart:io';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class QueueCrypto {
  static const _storage = FlutterSecureStorage(
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  );
  static const _keyStorageKey = 'queue_aes_key_v1';
  static const _prefix = 'ENC1:';
  static const _fallbackKeyFileName = '.queue_aes_key_v1_fallback';

  static Future<QueueKeys>? _keysFuture;

  static Future<QueueKeys> _getKeys() {
    return _keysFuture ??= resolveKeys(
      readStore: () => _storage.read(key: _keyStorageKey),
      writeStore: (v) => _storage.write(key: _keyStorageKey, value: v),
      readFile: _readFallbackFile,
      writeFile: _writeFallbackFile,
    );
  }

  /// Finds the AES key(s) for the queue. The key lives in the OS keychain AND
  /// a file in the app's data dir (a flaky keychain - e.g. an ad-hoc-signed
  /// macOS build whose ACL stops matching after a rebuild - must never cost
  /// the exam results queued under the old key):
  ///  * every readable copy is a candidate; decrypt tries all of them;
  ///  * a missing copy is re-created from the other one, but a copy whose
  ///    READ FAILED is never written over (it may still hold the real key);
  ///  * a new key is generated only when neither place has one, and then
  ///    written to every place that is known to be empty.
  /// If nothing at all is reachable the key is ephemeral (this run only).
  @visibleForTesting
  static Future<QueueKeys> resolveKeys({
    required Future<String?> Function() readStore,
    required Future<void> Function(String) writeStore,
    required Future<String?> Function() readFile,
    required Future<void> Function(String) writeFile,
  }) async {
    String? inStore, inFile;
    var storeFailed = false, fileFailed = false;
    try {
      inStore = await readStore();
    } catch (e) {
      storeFailed = true;
      debugPrint('QueueCrypto: secure storage unavailable ($e)');
    }
    try {
      inFile = await readFile();
    } catch (e) {
      fileFailed = true;
      debugPrint('QueueCrypto: fallback key file unreadable ($e)');
    }

    final all = <enc.Key>[];
    void add(String? b64) {
      if (b64 == null || b64.trim().isEmpty) return;
      try {
        final k = enc.Key(base64Decode(base64.normalize(b64.trim())));
        if (!all.any((e) => listEquals(e.bytes, k.bytes))) all.add(k);
      } catch (e) {
        debugPrint('QueueCrypto: unreadable stored key ignored ($e)');
      }
    }

    add(inStore);
    add(inFile);

    var primary = all.isEmpty ? null : all.first;
    if (primary == null) {
      primary = enc.Key.fromSecureRandom(32);
      all.add(primary);
    }
    final b64 = base64Encode(primary.bytes);
    // Heal / seed only the places known to be empty (never a failed read).
    if (!storeFailed && (inStore == null || inStore.trim().isEmpty)) {
      try {
        await writeStore(b64);
      } catch (e) {
        debugPrint('QueueCrypto: keychain write failed ($e)');
      }
    }
    if (!fileFailed && (inFile == null || inFile.trim().isEmpty)) {
      try {
        await writeFile(b64);
      } catch (e) {
        debugPrint('QueueCrypto: fallback key file write failed ($e)');
      }
    }
    return QueueKeys(primary, all);
  }

  static Future<File> _fallbackFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _fallbackKeyFileName));
  }

  static Future<String?> _readFallbackFile() async {
    final file = await _fallbackFile();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// temp + rename: a power cut mid-write must not leave a half key file.
  static Future<void> _writeFallbackFile(String b64) async {
    final file = await _fallbackFile();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(b64, flush: true);
    await tmp.rename(file.path);
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
    final iv = enc.IV(base64Decode(base64.normalize(parts[0])));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    return encrypter.decrypt64(parts[1], iv: iv);
  }

  static Future<String> encryptPayload(String plainJson) async =>
      encryptWithKey(plainJson, (await _getKeys()).primary);

  /// Tries every known key; throws if none decrypts the row (the caller keeps
  /// the row - an unreadable row is never counted as an attempt or deleted).
  static Future<String> decryptPayload(String stored) async {
    final keys = await _getKeys();
    return decryptWithKeys(stored, keys.all);
  }

  @visibleForTesting
  static String decryptWithKeys(String stored, List<enc.Key> keys) {
    Object? last;
    for (final k in keys) {
      try {
        return decryptWithKey(stored, k);
      } catch (e) {
        last = e;
      }
    }
    throw last ?? StateError('no queue key');
  }

  @visibleForTesting
  static void resetKeysForTest() => _keysFuture = null;
}

/// The key encrypting new rows plus every key that may have encrypted old ones.
class QueueKeys {
  final enc.Key primary;
  final List<enc.Key> all;
  const QueueKeys(this.primary, this.all);
}
