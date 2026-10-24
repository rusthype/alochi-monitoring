// lib/core/offline/results_exporter.dart
//
// Writes a `.alochires` (see offline_pack.py docstring):
//
//   export_meta.json  format_version (2), pack_uuid, machine_id, mac, exported_at, monotonic_ms,
//                     count, chain_tip
//   key.enc           RSA-OAEP(SHA-256, MGF1-SHA-256) of a fresh AES-256 key,
//                     wrapped to the RESULTS public key
//   payload.enc       nonce(12) || AES-256-GCM({entries:[{prev_hash, hash,
//                     payload_json, meta_json}]}) || tag(16),
//                     AAD = pack_uuid
//
// The HMAC chain was already computed when each result was enqueued, so no PIN
// is needed here: exporting only needs the public results key.
//
// An export always carries the pack's WHOLE chain (hash links cannot be
// re-based), so exporting again is safe: the server de-duplicates on
// the chain hash (its client_token). Rows are kept and only stamped `exported_at` (decision 13).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart' show RSAPublicKey;

import '../db/pack_results_db.dart';
import '../local_server/hub_guard.dart' show Mutex;
import '../network/network_info.dart';
import '../security/monitored_clock.dart';
import 'export_format.dart';
import 'offline_crypto.dart';
import 'offline_keys.dart';

/// `<school>_<uuid>` (full uuid, dashes dropped; school part omitted when
/// empty), safe as a file/dir name.
String packFilePrefix(String packUuid, String schoolCode) {
  final id = _clean(packUuid.replaceAll('-', ''));
  return schoolCode.isEmpty ? id : '${_clean(schoolCode)}_$id';
}

String _clean(String v) => v.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

/// A single path segment that can never be `.`/`..` or empty.
String _segment(String v, {String fallback = 'unknown'}) {
  final c = _clean(v);
  return c.replaceAll('.', '').isEmpty ? fallback : c;
}

/// First 8 characters of the uuid (dashes dropped).
String packShortId(String packUuid) {
  final id = _clean(packUuid.replaceAll('-', ''));
  return id.length <= 8 ? id : id.substring(0, 8);
}

/// Folder name for a pack kind; anything not known (old stored packs) is
/// `unknown`.
String packKindFolder(String? kind) =>
    kind == 'monitoring' || kind == 'diagnostic' ? kind! : 'unknown';

enum ExportError { notConfigured, nothingToExport }

class ExportException implements Exception {
  final ExportError code;
  const ExportException(this.code);
  @override
  String toString() => 'ExportException(${code.name})';
}

class ExportOutcome {
  final File file;
  final int count;
  final String chainTip;

  /// Entries whose idempotency_key violates the server rule (len 1..64). The
  /// server rejects the WHOLE file because of them (`bad_meta_json`); they
  /// cannot be skipped or re-keyed here (the HMAC chain covers the key and
  /// needs the PIN-derived key), so the UI must warn the teacher.
  final int invalidKeyCount;
  const ExportOutcome(this.file, this.count, this.chainTip,
      {this.invalidKeyCount = 0});
}

class ResultsExporter {
  final OfflineKeys keys;
  final MonitoredClock clock;
  final Future<String> Function() machineId;
  final Future<String> Function() mac;

  ResultsExporter({
    OfflineKeys? keys,
    MonitoredClock? clock,
    Future<String> Function()? machineId,
    Future<String> Function()? mac,
  })  : keys = keys ?? OfflineKeys.current,
        clock = clock ?? MonitoredClock.instance,
        machineId = machineId ?? (() async => machineGuid() ?? ''),
        mac = mac ?? (() async => (await primaryMac()) ?? '');

  /// Builds the `.alochires` bytes for [packUuid] without touching disk or
  /// stamping `exported_at`. Public so tests can inspect/verify the bytes.
  Future<
      ({
        Uint8List bytes,
        int count,
        String chainTip,
        int maxId,
        int invalidKeyCount
      })> build(
      String packUuid) async {
    final resultsKey = _resultsKeyOrThrow();
    final rows = await PackResultsDb.rowsForPack(packUuid);
    if (rows.isEmpty) throw const ExportException(ExportError.nothingToExport);

    final entries = [
      for (final r in rows)
        exportEntry(
            prevHash: r.prevHash,
            hash: r.hash,
            payloadJson: r.payloadJson,
            metaJson: r.metaJson)
    ];
    final chainTip = rows.last.hash;
    final invalid =
        rows.where((r) => !PackResultsDb.isValidKey(r.idempotencyKey)).length;
    if (invalid > 0) {
      debugPrint('ResultsExporter: $invalid entries have an invalid '
          'idempotency_key; the server will reject this file');
    }

    final aesKey = OfflineCrypto.randomBytes(OfflineCrypto.keyLen);
    final payloadEnc = OfflineCrypto.encryptBlob(
      aesKey,
      Uint8List.fromList(utf8.encode(packUuid)),
      Uint8List.fromList(utf8.encode(encodeEntries(entries))),
    );
    final keyEnc = OfflineCrypto.rsaOaepWrap(resultsKey, aesKey);

    final meta = {
      'format_version': 2,
      'pack_uuid': packUuid,
      'machine_id': await machineId(),
      'mac': await mac(),
      'exported_at': _isoSeconds(clock.nowUtc),
      'monotonic_ms': clock.ticksMs,
      'count': rows.length,
      'chain_tip': chainTip,
    };

    final archive = Archive()
      ..addFile(_stored('export_meta.json', utf8.encode(jsonEncode(meta))))
      ..addFile(_stored('key.enc', keyEnc))
      ..addFile(_stored('payload.enc', payloadEnc));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    return (
      bytes: bytes,
      count: rows.length,
      chainTip: chainTip,
      maxId: rows.last.id,
      invalidKeyCount: invalid
    );
  }

  /// Writes the file into `<dir>/<school>/<monitoring|diagnostic|unknown>/
  /// <YYYY-MM-DD>_<packShort8>.alochires` and stamps the pack's rows as
  /// exported. The date is the pack's created_at day (one test round = one
  /// pack), else the export day. Never overwrites: a taken name gets -2, -3 ...
  Future<ExportOutcome> exportPack(String packUuid, Directory dir,
      {String schoolCode = ''}) async {
    final built = await build(packUuid);
    final meta = await PackResultsDb.metaOf(packUuid);
    final school =
        schoolCode.isNotEmpty ? schoolCode : (meta?.schoolCode ?? '');
    final target = Directory(
        p.join(dir.path, _segment(school), packKindFolder(meta?.kind)));
    await target.create(recursive: true);
    final day = (meta?.createdAt ?? clock.nowUtc).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final base = '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-'
        '${two(day.day)}_${packShortId(packUuid)}';
    var file = File(p.join(target.path, '$base.alochires'));
    for (var n = 2; file.existsSync(); n++) {
      file = File(p.join(target.path, '$base-$n.alochires'));
    }
    await file.writeAsBytes(built.bytes, flush: true);
    // Trusted (monotonic-anchored) time, same clock purgeExpired compares with.
    await PackResultsDb.markExported(packUuid, clock.nowMs, built.maxId);
    return ExportOutcome(file, built.count, built.chainTip,
          invalidKeyCount: built.invalidKeyCount);
  }

  static final Map<String, Mutex> _latestLocks = {};

  /// Safety backup: (re)writes the pack's WHOLE chain to `<dir>/latest.alochires`
  /// via temp file + atomic rename, so a half-written file is never visible.
  /// Does NOT stamp `exported_at` (only a manual export does). Calls for the
  /// same pack are serialised.
  Future<ExportOutcome> writeLatest(String packUuid, Directory dir) {
    return (_latestLocks[packUuid] ??= Mutex()).run(() async {
      final built = await build(packUuid);
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, 'latest.alochires'));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(built.bytes, flush: true);
      try {
        await tmp.rename(file.path);
      } catch (_) {
        // Target may be briefly locked (Windows): retry once, else keep the
        // old file and drop the temp.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        try {
          await tmp.rename(file.path);
        } catch (_) {
          try {
            await tmp.delete();
          } catch (_) {}
          rethrow;
        }
      }
      return ExportOutcome(file, built.count, built.chainTip,
          invalidKeyCount: built.invalidKeyCount);
    });
  }

  static ArchiveFile _stored(String name, List<int> data) =>
      ArchiveFile.noCompress(name, data.length, data);

  static String _isoSeconds(DateTime utc) {
    final s = utc.toUtc().toIso8601String();
    final dot = s.indexOf('.');
    return '${dot < 0 ? s.replaceAll('Z', '') : s.substring(0, dot)}Z';
  }

  RSAPublicKey _resultsKeyOrThrow() {
    try {
      return keys.resultsKey;
    } catch (_) {
      throw const ExportException(ExportError.notConfigured);
    }
  }
}
