// lib/core/offline/pack_loader.dart
//
// Opens a `.alochipack` (see offline_pack.py docstring for the byte format).
//
// Two steps so the UI can fail early before asking for a PIN:
//   [PackLoader.inspect]  names -> signature -> expires_at -> file hashes
//   [PackLoader.unlock]   PIN -> PBKDF2 (worker Isolate) -> AES-GCM -> content
//
// The PIN is never logged or written to disk; only the derived HMAC-chain key
// is kept (in memory) on the returned [LoadedPack].
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart' show RSAPublicKey;

import 'offline_crypto.dart';
import 'offline_keys.dart';

enum PackError {
  /// No (valid) public keys compiled in — offline mode is disabled.
  notConfigured,
  badFormat,
  unsafeName,
  badSignature,
  expired,
  hashMismatch,
  wrongPin,
}

class PackException implements Exception {
  final PackError code;
  final String? detail;
  const PackException(this.code, [this.detail]);
  @override
  String toString() =>
      'PackException(${code.name}${detail == null ? '' : ': $detail'})';
}

class PackManifest {
  final int formatVersion;
  final String packUuid;
  final String schoolId;
  final String schoolCode;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int kdfIter;
  final Uint8List kdfSalt;
  final Map<String, String> files;

  const PackManifest({
    required this.formatVersion,
    required this.packUuid,
    required this.schoolId,
    required this.schoolCode,
    required this.createdAt,
    required this.expiresAt,
    required this.kdfIter,
    required this.kdfSalt,
    required this.files,
  });

  factory PackManifest.fromBytes(Uint8List bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map) throw const FormatException('manifest is not an object');
      final kdf = j['kdf'];
      final files = j['files'];
      if (kdf is! Map || files is! Map) {
        throw const FormatException('kdf/files missing');
      }
      if (kdf['alg'] != 'PBKDF2-HMAC-SHA256') {
        throw FormatException('unsupported kdf ${kdf['alg']}');
      }
      final iter = (kdf['iter'] as num).toInt();
      if (iter <= 0 || iter > 10000000) {
        throw const FormatException('kdf iter out of range');
      }
      final m = PackManifest(
        formatVersion: (j['format_version'] as num).toInt(),
        packUuid: (j['pack_uuid'] ?? '').toString(),
        schoolId: (j['school_id'] ?? '').toString(),
        schoolCode: (j['school_code'] ?? '').toString(),
        createdAt: DateTime.parse(j['created_at'].toString()).toUtc(),
        expiresAt: DateTime.parse(j['expires_at'].toString()).toUtc(),
        kdfIter: iter,
        kdfSalt: Uint8List.fromList(base64.decode(kdf['salt'].toString())),
        files: files.map((k, v) => MapEntry(k.toString(), v.toString())),
      );
      if (m.formatVersion != 1) {
        throw FormatException('unsupported format_version ${m.formatVersion}');
      }
      if (m.packUuid.isEmpty) throw const FormatException('pack_uuid missing');
      return m;
    } on PackException {
      rethrow;
    } catch (e) {
      throw PackException(PackError.badFormat, e.toString());
    }
  }
}

/// A pack whose signature, expiry and file hashes are verified, PIN not yet
/// applied. Holds the zip members in memory (they are tens of MB at most).
class PackArchive {
  final PackManifest manifest;
  final Uint8List contentEnc;

  /// `media/<sha256>.<ext>` -> bytes
  final Map<String, Uint8List> media;

  const PackArchive(this.manifest, this.contentEnc, this.media);
}

class LoadedPack {
  final PackManifest manifest;
  final List<Map<String, dynamic>> tests;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> students;

  /// HMAC-SHA256(PBKDF2 key, "alochires-chain-v1") — derives the result chain.
  final Uint8List chainKey;

  const LoadedPack({
    required this.manifest,
    required this.tests,
    required this.groups,
    required this.students,
    required this.chainKey,
  });

  String get packUuid => manifest.packUuid;
  String get schoolCode => manifest.schoolCode;
  String get schoolId => manifest.schoolId;
}

typedef KdfFn = Future<Uint8List> Function(
    String pin, Uint8List salt, int iterations);

class PackLoader {
  final OfflineKeys keys;
  final DateTime Function() now;
  final KdfFn kdf;

  PackLoader({
    OfflineKeys? keys,
    DateTime Function()? now,
    KdfFn? kdf,
  })  : keys = keys ?? OfflineKeys.current,
        now = now ?? DateTime.now,
        kdf = kdf ?? OfflineCrypto.deriveKeyAsync;

  static final RegExp _mediaName =
      RegExp(r'^media/[0-9a-f]{64}\.(jpg|jpeg|png|gif|webp)$');

  static bool _knownName(String n) =>
      n == 'manifest.json' ||
      n == 'manifest.sig' ||
      n == 'content.json.enc' ||
      _mediaName.hasMatch(n);

  /// Step 1: structure, signature, expiry and per-file hashes. No PIN needed.
  PackArchive inspect(Uint8List zipBytes) {
    final signingKey = _signingKeyOrThrow();

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (e) {
      throw PackException(PackError.badFormat, 'not a zip: $e');
    }

    final members = <String, Uint8List>{};
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (!_knownName(f.name)) {
        throw PackException(PackError.unsafeName, f.name);
      }
      if (members.containsKey(f.name)) {
        throw PackException(PackError.badFormat, 'duplicate ${f.name}');
      }
      members[f.name] = f.readBytes() ?? Uint8List(0);
    }

    final manifestBytes = members['manifest.json'];
    final sig = members['manifest.sig'];
    final content = members['content.json.enc'];
    if (manifestBytes == null || sig == null || content == null) {
      throw const PackException(PackError.badFormat, 'missing member');
    }

    // Signature over the EXACT manifest bytes, before trusting anything in it.
    if (!OfflineCrypto.verifyRsaSha256(signingKey, manifestBytes, sig)) {
      throw const PackException(PackError.badSignature);
    }
    final manifest = PackManifest.fromBytes(manifestBytes);

    if (now().toUtc().isAfter(manifest.expiresAt)) {
      throw const PackException(PackError.expired);
    }

    // Every listed member must exist with the right hash; nothing unlisted.
    final listed = manifest.files.keys.toSet();
    final present = members.keys
        .where((n) => n != 'manifest.json' && n != 'manifest.sig')
        .toSet();
    if (!listed.containsAll(present) || !present.containsAll(listed)) {
      throw const PackException(PackError.hashMismatch, 'member set differs');
    }
    for (final e in manifest.files.entries) {
      if (OfflineCrypto.sha256Hex(members[e.key]!) != e.value.toLowerCase()) {
        throw PackException(PackError.hashMismatch, e.key);
      }
    }

    final media = <String, Uint8List>{
      for (final e in members.entries)
        if (e.key.startsWith('media/')) e.key: e.value,
    };
    return PackArchive(manifest, content, media);
  }

  /// Step 2: PIN -> key -> content. [mediaDir], when given, receives the
  /// pack's images (content-addressed, unencrypted by design — decision 14).
  Future<LoadedPack> unlock(PackArchive archive, String pin,
      {Directory? mediaDir}) async {
    final m = archive.manifest;
    final key = await kdf(pin, m.kdfSalt, m.kdfIter);

    final Uint8List plain;
    try {
      plain = OfflineCrypto.decryptBlob(
          key, Uint8List.fromList(utf8.encode(m.packUuid)), archive.contentEnc);
    } on OfflineAuthException {
      throw const PackException(PackError.wrongPin);
    }

    final Object? decoded;
    try {
      decoded = await Isolate.run(() => jsonDecode(utf8.decode(plain)));
    } catch (e) {
      throw PackException(PackError.badFormat, 'content: $e');
    }
    if (decoded is! Map) {
      throw const PackException(
          PackError.badFormat, 'content is not an object');
    }
    final root = decoded;
    List<Map<String, dynamic>> list(String k) {
      final v = root[k];
      if (v is! List || v.isEmpty) return const [];
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }

    if (mediaDir != null && archive.media.isNotEmpty) {
      await _extractMedia(archive.media, mediaDir);
    }

    return LoadedPack(
      manifest: m,
      tests: list('tests'),
      groups: list('groups'),
      students: list('students'),
      chainKey: OfflineCrypto.chainKeyOf(key),
    );
  }

  /// Convenience: file bytes -> inspect -> unlock.
  Future<LoadedPack> open(Uint8List zipBytes, String pin,
      {Directory? mediaDir}) {
    return unlock(inspect(zipBytes), pin, mediaDir: mediaDir);
  }

  Future<void> _extractMedia(
      Map<String, Uint8List> media, Directory mediaDir) async {
    await mediaDir.create(recursive: true);
    for (final e in media.entries) {
      // Names were validated against _mediaName, so basename is the whole
      // `<sha256>.<ext>` and cannot escape [mediaDir].
      final f = File(p.join(mediaDir.path, p.basename(e.key)));
      if (await f.exists() && await f.length() == e.value.length) continue;
      await f.writeAsBytes(e.value, flush: true);
    }
  }

  RSAPublicKey _signingKeyOrThrow() {
    try {
      return keys.signingKey;
    } catch (_) {
      throw const PackException(PackError.notConfigured);
    }
  }
}
