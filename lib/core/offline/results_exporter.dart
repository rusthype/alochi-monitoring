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
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart' show RSAPublicKey;

import '../db/pack_results_db.dart';
import '../network/network_info.dart';
import '../security/monitored_clock.dart';
import 'offline_crypto.dart';
import 'offline_keys.dart';

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
  const ExportOutcome(this.file, this.count, this.chainTip);
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
  Future<({Uint8List bytes, int count, String chainTip})> build(
      String packUuid) async {
    final resultsKey = _resultsKeyOrThrow();
    final rows = await PackResultsDb.rowsForPack(packUuid);
    if (rows.isEmpty) throw const ExportException(ExportError.nothingToExport);

    final entries = [
      for (final r in rows)
        // EXACTLY these four keys (format 2): the server rejects the whole file
        // on any other key. idempotency_key / incidents / clock_flags live
        // only inside meta_json, which is part of the HMAC chain.
        {
          'prev_hash': r.prevHash,
          'hash': r.hash,
          'payload_json': r.payloadJson,
          'meta_json': r.metaJson,
        }
    ];
    final chainTip = rows.last.hash;

    final aesKey = OfflineCrypto.randomBytes(OfflineCrypto.keyLen);
    final payloadEnc = OfflineCrypto.encryptBlob(
      aesKey,
      Uint8List.fromList(utf8.encode(packUuid)),
      Uint8List.fromList(utf8.encode(jsonEncode({'entries': entries}))),
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
    return (bytes: bytes, count: rows.length, chainTip: chainTip);
  }

  /// Writes the file into [dir] and stamps the pack's rows as exported.
  Future<ExportOutcome> exportPack(String packUuid, Directory dir,
      {String schoolCode = ''}) async {
    final built = await build(packUuid);
    await dir.create(recursive: true);
    final stamp = _isoSeconds(clock.nowUtc)
        .replaceAll(RegExp(r'[-:]'), '')
        .replaceAll('T', '-')
        .replaceAll('Z', '');
    final school = schoolCode.isEmpty ? '' : '${schoolCode}_';
    final name = '$school${packUuid.substring(0, 8)}_$stamp.alochires';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(built.bytes, flush: true);
    await PackResultsDb.markExported(packUuid, clock.wallMs);
    return ExportOutcome(file, built.count, built.chainTip);
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
