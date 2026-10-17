// lib/core/db/pack_results_db.dart
//
// Results produced while an offline USB pack is open. Each row is one link of
// the pack's HMAC chain (see offline_pack.py docstring):
//
//   hash_i = HMAC(chain_key, prev_hash_i + ":" + payload_json_i)
//
// The link is computed at enqueue time, inside one transaction with the read
// of the previous link, so the chain is gap-free per pack_uuid. Rows are NEVER
// deleted by an export (decision 13): `exported_at` is stamped instead, and a
// pack's rows are only purged `expires_at + 30 days` after the pack expired.
//
// payload_json is stored encrypted at rest (QueueCrypto) like every other
// queue row; hash/prev_hash are over the PLAIN text, which is what the server
// recomputes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../offline/offline_crypto.dart';
import 'offline_queue.dart';
import 'queue_crypto.dart';

class PackResultRow {
  final int id;
  final String packUuid;
  final String idempotencyKey;
  final String payloadJson;
  final List<dynamic> incidents;
  final List<dynamic> clockFlags;
  final String prevHash;
  final String hash;
  final int created;
  final int? exportedAt;

  const PackResultRow({
    required this.id,
    required this.packUuid,
    required this.idempotencyKey,
    required this.payloadJson,
    required this.incidents,
    required this.clockFlags,
    required this.prevHash,
    required this.hash,
    required this.created,
    required this.exportedAt,
  });
}

class PackSummary {
  final String packUuid;
  final String schoolCode;
  final int total;
  final int unexported;
  final DateTime? expiresAt;

  const PackSummary({
    required this.packUuid,
    required this.schoolCode,
    required this.total,
    required this.unexported,
    required this.expiresAt,
  });
}

class PackResultsDb {
  PackResultsDb._();

  /// Pack rows survive this long after the pack's own `expires_at`.
  static const Duration retentionAfterExpiry = Duration(days: 30);

  static Future<Database> get _db => OfflineQueue.db;

  /// Remembers a pack's expiry so [purgeExpired] knows when to clean up.
  static Future<void> registerPack({
    required String packUuid,
    required String schoolCode,
    required DateTime expiresAt,
    int? nowMs,
  }) async {
    final d = await _db;
    await d.insert(
      'pack_meta',
      {
        'pack_uuid': packUuid,
        'school_code': schoolCode,
        'expires_at': expiresAt.toUtc().millisecondsSinceEpoch,
        'loaded_at': nowMs ?? DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Appends one result to [packUuid]'s chain and returns the stored link.
  /// Idempotent on [idempotencyKey]: a repeat returns the existing row.
  static Future<PackResultRow> append({
    required String packUuid,
    required Uint8List chainKey,
    required String idempotencyKey,
    required String payloadJson,
    List<dynamic> incidents = const [],
    List<dynamic> clockFlags = const [],
    int? nowMs,
  }) async {
    final d = await _db;
    final encrypted = await QueueCrypto.encryptPayload(payloadJson);
    return d.transaction((txn) async {
      final existing = await txn.query('pack_results',
          where: 'pack_uuid = ? AND idempotency_key = ?',
          whereArgs: [packUuid, idempotencyKey],
          limit: 1);
      if (existing.isNotEmpty) return _rowOf(existing.first, payloadJson);

      final last = await txn.query('pack_results',
          columns: ['hash'],
          where: 'pack_uuid = ?',
          whereArgs: [packUuid],
          orderBy: 'id DESC',
          limit: 1);
      final prev =
          last.isEmpty ? OfflineCrypto.zeroHash : last.first['hash'] as String;
      final hash = OfflineCrypto.chainHash(chainKey, prev, payloadJson);
      final created = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      final id = await txn.insert('pack_results', {
        'pack_uuid': packUuid,
        'idempotency_key': idempotencyKey,
        'payload': encrypted,
        'incidents': jsonEncode(incidents),
        'clock_flags': jsonEncode(clockFlags),
        'prev_hash': prev,
        'hash': hash,
        'created': created,
      });
      return PackResultRow(
        id: id,
        packUuid: packUuid,
        idempotencyKey: idempotencyKey,
        payloadJson: payloadJson,
        incidents: incidents,
        clockFlags: clockFlags,
        prevHash: prev,
        hash: hash,
        created: created,
        exportedAt: null,
      );
    });
  }

  /// Every row of [packUuid], oldest first (= chain order), payload decrypted.
  /// A row that fails to decrypt is a corrupt/tampered link: the export must
  /// not silently skip it (that would break the chain on the server), so this
  /// throws.
  static Future<List<PackResultRow>> rowsForPack(String packUuid) async {
    final d = await _db;
    final rows = await d.query('pack_results',
        where: 'pack_uuid = ?', whereArgs: [packUuid], orderBy: 'id ASC');
    if (rows.isEmpty) return [];
    final out = <PackResultRow>[];
    for (final r in rows) {
      final plain = await QueueCrypto.decryptPayload(r['payload'] as String);
      out.add(_rowOf(r, plain));
    }
    return out;
  }

  static Future<void> markExported(String packUuid, int atMs) async {
    final d = await _db;
    await d.update('pack_results', {'exported_at': atMs},
        where: 'pack_uuid = ?', whereArgs: [packUuid]);
  }

  static Future<int> unexportedCount([String? packUuid]) async {
    final d = await _db;
    final res = packUuid == null
        ? await d.rawQuery(
            'SELECT COUNT(*) c FROM pack_results WHERE exported_at IS NULL')
        : await d.rawQuery(
            'SELECT COUNT(*) c FROM pack_results WHERE exported_at IS NULL AND pack_uuid = ?',
            [packUuid]);
    return (res.first['c'] as int?) ?? 0;
  }

  /// One entry per pack that has stored results.
  static Future<List<PackSummary>> summaries() async {
    final d = await _db;
    final rows = await d.rawQuery('''
      SELECT r.pack_uuid AS pack_uuid,
             COUNT(*) AS total,
             SUM(CASE WHEN r.exported_at IS NULL THEN 1 ELSE 0 END) AS unexported,
             m.school_code AS school_code,
             m.expires_at AS expires_at
        FROM pack_results r
        LEFT JOIN pack_meta m ON m.pack_uuid = r.pack_uuid
       GROUP BY r.pack_uuid
       ORDER BY MAX(r.id) DESC
    ''');
    if (rows.isEmpty) return [];
    return rows.map((r) {
      final exp = r['expires_at'] as int?;
      return PackSummary(
        packUuid: r['pack_uuid'] as String,
        schoolCode: (r['school_code'] as String?) ?? '',
        total: (r['total'] as int?) ?? 0,
        unexported: (r['unexported'] as int?) ?? 0,
        expiresAt: exp == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true),
      );
    }).toList();
  }

  /// Deletes rows (and meta) of packs whose `expires_at + 30 days` is past.
  /// Rows of packs with no meta are kept — we cannot tell how old they are.
  static Future<int> purgeExpired({int? nowMs}) async {
    final d = await _db;
    final cutoff = (nowMs ?? DateTime.now().millisecondsSinceEpoch) -
        retentionAfterExpiry.inMilliseconds;
    final stale = await d.query('pack_meta',
        columns: ['pack_uuid'], where: 'expires_at < ?', whereArgs: [cutoff]);
    var removed = 0;
    for (final m in stale) {
      final id = m['pack_uuid'] as String;
      removed += await d
          .delete('pack_results', where: 'pack_uuid = ?', whereArgs: [id]);
      await d.delete('pack_meta', where: 'pack_uuid = ?', whereArgs: [id]);
    }
    return removed;
  }

  static PackResultRow _rowOf(Map<String, Object?> r, String payloadJson) {
    List<dynamic> list(Object? v) {
      try {
        final d = jsonDecode((v as String?) ?? '[]');
        return d is List ? d : const [];
      } catch (_) {
        return const [];
      }
    }

    return PackResultRow(
      id: r['id'] as int,
      packUuid: r['pack_uuid'] as String,
      idempotencyKey: r['idempotency_key'] as String,
      payloadJson: payloadJson,
      incidents: list(r['incidents']),
      clockFlags: list(r['clock_flags']),
      prevHash: r['prev_hash'] as String,
      hash: r['hash'] as String,
      created: r['created'] as int,
      exportedAt: r['exported_at'] as int?,
    );
  }

  @visibleForTesting
  static Future<void> wipeForTest() async {
    final d = await _db;
    await d.delete('pack_results');
    await d.delete('pack_meta');
  }
}
