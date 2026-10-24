// lib/core/db/pack_results_db.dart
//
// Results produced while an offline USB pack is open. Each row is one link of
// the pack's HMAC chain (`.alochires` format 2, see offline_pack.py docstring):
//
//   hash_i = HMAC(chain_key, prev_hash_i + ":" + payload_json_i + ":" + meta_json_i)
//
// meta_json is the TEXT {"idempotency_key","incidents","clock_flags"}; it sits
// inside the chain so those fields are authenticated too. The link is computed
// ONCE at enqueue time (inside one transaction with the read of the previous
// link) and stored — never recomputed — so the hash is stable across
// re-exports. The server uses the hash as the result's client_token: a repeat
// export of the same rows is therefore a duplicate, not a second result. Rows are NEVER
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

import '../offline/export_format.dart';
import '../offline/offline_crypto.dart';
import '../security/monitored_clock.dart';
import 'offline_queue.dart';
import 'pack_local_students_db.dart';
import 'queue_crypto.dart';

class PackResultRow {
  final int id;
  final String packUuid;
  final String idempotencyKey;
  final String payloadJson;

  /// Exact meta text that went into the chain (and into the export).
  final String metaJson;
  final String prevHash;
  final String hash;
  final int created;
  final int? exportedAt;

  const PackResultRow({
    required this.id,
    required this.packUuid,
    required this.idempotencyKey,
    required this.payloadJson,
    required this.metaJson,
    required this.prevHash,
    required this.hash,
    required this.created,
    required this.exportedAt,
  });

  Map<String, dynamic> get _meta {
    try {
      final d = jsonDecode(metaJson);
      return d is Map ? Map<String, dynamic>.from(d) : const {};
    } catch (_) {
      return const {};
    }
  }

  List<dynamic> get incidents =>
      _meta['incidents'] is List ? _meta['incidents'] as List : const [];
  List<dynamic> get clockFlags =>
      _meta['clock_flags'] is List ? _meta['clock_flags'] as List : const [];
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

  /// The backend (offline_pack.py `_parse_entry_meta`) rejects the WHOLE file
  /// unless `0 < len(idempotency_key) <= 64`; the hub/online API also only
  /// accept [A-Za-z0-9:_.-]. Mirror of that rule.
  static final RegExp _keyRe = RegExp(r'^[A-Za-z0-9:_.\-]{1,64}$');
  static bool isValidKey(String key) => _keyRe.hasMatch(key);

  /// [key] unchanged when valid, else a deterministic `h:<40 hex>` digest, so a
  /// retry still dedupes and an over-long key can never poison an export.
  static String safeKey(String key) => isValidKey(key)
      ? key
      : 'h:${OfflineCrypto.sha256Hex(utf8.encode(key)).substring(0, 40)}';

  /// The exact meta text that goes into a chain link (and the export). Public
  /// so the LAN hub can measure an entry before it stores it.
  static String metaJsonFor(String idempotencyKey, List<dynamic> incidents,
          List<dynamic> clockFlags) =>
      jsonEncode({
        'idempotency_key': idempotencyKey,
        'incidents': incidents,
        'clock_flags': clockFlags,
      });

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
    idempotencyKey = safeKey(idempotencyKey);
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
      final metaJson = metaJsonFor(idempotencyKey, incidents, clockFlags);
      final hash =
          OfflineCrypto.chainHash(chainKey, prev, payloadJson, metaJson);
      final created = nowMs ?? DateTime.now().millisecondsSinceEpoch;
      final id = await txn.insert('pack_results', {
        'pack_uuid': packUuid,
        'idempotency_key': idempotencyKey,
        'payload': encrypted,
        'meta_json': metaJson,
        'prev_hash': prev,
        'hash': hash,
        'created': created,
      });
      return PackResultRow(
        id: id,
        packUuid: packUuid,
        idempotencyKey: idempotencyKey,
        payloadJson: payloadJson,
        metaJson: metaJson,
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

  /// Stamps rows with `id <= [upToId]` only: a result appended after the
  /// export snapshot is not in the file, so it must stay unexported.
  static Future<void> markExported(
      String packUuid, int atMs, int upToId) async {
    final d = await _db;
    await d.update('pack_results', {'exported_at': atMs},
        where: 'pack_uuid = ? AND id <= ?', whereArgs: [packUuid, upToId]);
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

  /// True when [idempotencyKey] is already a link of [packUuid]'s chain (a
  /// repeat [append] with it would be a no-op).
  static Future<bool> hasKey(String packUuid, String idempotencyKey) async {
    idempotencyKey = safeKey(idempotencyKey);
    final d = await _db;
    final rows = await d.query('pack_results',
        columns: ['id'],
        where: 'pack_uuid = ? AND idempotency_key = ?',
        whereArgs: [packUuid, idempotencyKey],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// The plaintext payload of [idempotencyKey]'s row (decrypted), or null.
  static Future<String?> payloadOf(
      String packUuid, String idempotencyKey) async {
    final d = await _db;
    final rows = await d.query('pack_results',
        columns: ['payload'],
        where: 'pack_uuid = ? AND idempotency_key = ?',
        whereArgs: [packUuid, idempotencyKey],
        limit: 1);
    if (rows.isEmpty) return null;
    return QueueCrypto.decryptPayload(rows.first['payload'] as String);
  }

  /// Size in bytes of the DECRYPTED JSON an export of [packUuid] would carry
  /// today (see export_format.dart).
  static Future<int> exportPlainBytes(String packUuid) async =>
      (await chainUsage(packUuid)).bytes;

  /// [exportPlainBytes] plus the row count and the per-student tally, in one
  /// pass. Decrypts every row, so callers cache it (ChainUsage).
  static Future<ChainUsage> chainUsage(String packUuid) async {
    final d = await _db;
    final rows = await d.query('pack_results',
        columns: ['payload', 'meta_json'],
        where: 'pack_uuid = ?',
        whereArgs: [packUuid]);
    final usage = ChainUsage.empty();
    for (final r in rows) {
      final payload = await QueueCrypto.decryptPayload(r['payload'] as String);
      usage.add(_studentIdOf(payload),
          exportEntryBytes(payload, r['meta_json'] as String));
    }
    return usage;
  }

  /// `student_id` of a stored payload, or null when it has none.
  static String? studentIdOf(String payloadJson) => _studentIdOf(payloadJson);

  static String? _studentIdOf(String payloadJson) {
    try {
      final d = jsonDecode(payloadJson);
      final id = d is Map ? d['student_id'] : null;
      return id is String ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// Rows and stored (encrypted + base64) bytes of one pack's chain. The LAN
  /// hub uses it to stop accepting results before the chain grows past what the
  /// server will import (5000 entries / 10 MB decrypted per file).
  static Future<({int count, int storedBytes})> stats(String packUuid) async {
    final d = await _db;
    final res = await d.rawQuery(
        'SELECT COUNT(*) c, COALESCE(SUM(LENGTH(payload) + LENGTH(meta_json)), 0) b '
        'FROM pack_results WHERE pack_uuid = ?',
        [packUuid]);
    return (
      count: (res.first['c'] as int?) ?? 0,
      storedBytes: (res.first['b'] as int?) ?? 0,
    );
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

  /// Housekeeping. A row is deleted only when ALL of these hold:
  ///   * the pack expired more than 30 days ago (`expires_at + 30d`), AND
  ///   * the row was EXPORTED (`exported_at IS NOT NULL`) — a result nobody
  ///     has carried to the server is never dropped, however old, AND
  ///   * the export itself is more than 30 days old, so a lost USB stick still
  ///     leaves time to export again.
  /// "Now" is the monitored clock (monotonic-anchored), not the raw system
  /// clock; `exported_at` is stamped from the same clock. A date set a year
  /// ahead — before or after the app started — therefore cannot make a fresh
  /// export look old. A pack's meta row is kept while any of its rows remain.
  static Future<int> purgeExpired({int? nowMs, MonitoredClock? clock}) async {
    final d = await _db;
    final now = nowMs ?? (clock ?? MonitoredClock.instance).nowMs;
    final cutoff = now - retentionAfterExpiry.inMilliseconds;
    final stale = await d.query('pack_meta',
        columns: ['pack_uuid'], where: 'expires_at < ?', whereArgs: [cutoff]);
    var removed = 0;
    for (final m in stale) {
      final id = m['pack_uuid'] as String;
      removed += await d.delete('pack_results',
          where:
              'pack_uuid = ? AND exported_at IS NOT NULL AND exported_at < ?',
          whereArgs: [id, cutoff]);
      final left = await d.rawQuery(
          'SELECT COUNT(*) c FROM pack_results WHERE pack_uuid = ?', [id]);
      if (((left.first['c'] as int?) ?? 0) == 0) {
        await d.delete('pack_meta', where: 'pack_uuid = ?', whereArgs: [id]);
        await PackLocalStudentsDb.deleteForPack(id);
      }
    }
    return removed;
  }

  /// How many rows of [packUuid] have an idempotency key starting with
  /// [prefix] (used to number repeat attempts).
  static Future<int> countKeyPrefix(String packUuid, String prefix) async {
    final d = await _db;
    final res = await d.rawQuery(
        "SELECT COUNT(*) c FROM pack_results WHERE pack_uuid = ? AND idempotency_key LIKE ? ESCAPE '\\'",
        [packUuid, '${prefix.replaceAll('%', r'\%').replaceAll('_', r'\_')}%']);
    return (res.first['c'] as int?) ?? 0;
  }

  /// Every idempotency key of [packUuid] (keys only: no payload decrypt).
  static Future<List<String>> keysForPack(String packUuid) async {
    final d = await _db;
    final res = await d.query('pack_results',
        columns: ['idempotency_key'],
        where: 'pack_uuid = ?',
        whereArgs: [packUuid]);
    return [for (final r in res) r['idempotency_key'] as String];
  }

  static PackResultRow _rowOf(Map<String, Object?> r, String payloadJson) {
    return PackResultRow(
      id: r['id'] as int,
      packUuid: r['pack_uuid'] as String,
      idempotencyKey: r['idempotency_key'] as String,
      payloadJson: payloadJson,
      metaJson: r['meta_json'] as String,
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
