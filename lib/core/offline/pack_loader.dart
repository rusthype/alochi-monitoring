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

  /// A zip member (or the whole archive) is larger than any real pack —
  /// refused before it is read into memory (zip-bomb guard).
  tooLarge,
}

class PackException implements Exception {
  final PackError code;
  final String? detail;
  const PackException(this.code, [this.detail]);
  @override
  String toString() =>
      'PackException(${code.name}${detail == null ? '' : ': $detail'})';
}

/// PBKDF2 work factor floor (offline_pack.py KDF_ITER).
const int minKdfIter = 600000;

/// Size ceilings enforced on the zip's DECLARED member sizes before anything
/// is read into memory. Real packs are far below these.
class PackLimits {
  final int maxMembers;
  final int maxManifestBytes;
  final int maxSigBytes;
  final int maxContentBytes;
  final int maxMediaBytes;
  final int maxTotalBytes;
  const PackLimits({
    this.maxMembers = 20000,
    this.maxManifestBytes = 1 << 20,
    this.maxSigBytes = 4096,
    this.maxContentBytes = 128 << 20,
    this.maxMediaBytes = 32 << 20,
    this.maxTotalBytes = 1 << 30,
  });
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
      // Lower bound = the backend's KDF_ITER. The manifest is signed, but a
      // weak work factor must never be accepted even from a signed file.
      if (iter < minKdfIter || iter > 10000000) {
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

/// Isolate entry points live at top level on purpose: a closure created inside
/// an async instance/State method captures the enclosing context (and through
/// it `this`, the widget tree and the zone), which is unsendable and made
/// "Illegal argument in isolate message" in the real dialog.
Future<Object?> _decodeJsonOffThread(Uint8List plain) =>
    Isolate.run(() => jsonDecode(utf8.decode(plain)));

/// AES-GCM of the pack content is pure Dart (~1 MB/s): a 2.4 MB school pack
/// froze the UI isolate for ~2 s, so it runs in a worker. The blob is copied
/// first: it may be a view into the whole zip buffer, and a view would drag
/// that entire buffer across the isolate boundary.
Future<Uint8List> _decryptOffThread(
    Uint8List key, Uint8List aad, Uint8List blob) {
  final copy = Uint8List.fromList(blob);
  return Isolate.run(() => OfflineCrypto.decryptBlob(key, aad, copy));
}

/// Zip decode + RSA verify + per-file SHA-256 of the pack at [path] off the
/// UI thread. Only the path and the (String-only) [keys] cross the boundary.
Future<PackArchive> inspectPackFile(String path, OfflineKeys keys) =>
    Isolate.run(
        () => PackLoader(keys: keys).inspect(File(path).readAsBytesSync()));

class PackLoader {
  final OfflineKeys keys;
  final DateTime Function() now;
  final KdfFn kdf;
  final PackLimits limits;

  PackLoader({
    OfflineKeys? keys,
    DateTime Function()? now,
    KdfFn? kdf,
    this.limits = const PackLimits(),
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
    var total = 0;
    var count = 0;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (!_knownName(f.name)) {
        throw PackException(PackError.unsafeName, f.name);
      }
      // Every member of a real pack is STORED, so nothing ever needs
      // decompressing; refusing compressed members closes the zip-bomb door.
      if (f.compression != CompressionType.none) {
        throw PackException(PackError.badFormat, 'compressed member ${f.name}');
      }
      final cap = switch (f.name) {
        'manifest.json' => limits.maxManifestBytes,
        'manifest.sig' => limits.maxSigBytes,
        'content.json.enc' => limits.maxContentBytes,
        _ => limits.maxMediaBytes,
      };
      total += f.size;
      if (++count > limits.maxMembers ||
          f.size > cap ||
          total > limits.maxTotalBytes) {
        throw PackException(PackError.tooLarge, f.name);
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
      plain = await _decryptOffThread(
          key, Uint8List.fromList(utf8.encode(m.packUuid)), archive.contentEnc);
    } on OfflineAuthException {
      throw const PackException(PackError.wrongPin);
    }

    final Object? decoded;
    try {
      decoded = await _decodeJsonOffThread(plain);
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
