// lib/core/db/lan_outbox_db.dart
//
// A LAN client's not-yet-acknowledged results (decision 2 of phase 3: the
// client keeps a result until the teacher's hub acks it, and retries).
//
// Each row is the full request envelope `{payload, incidents, clock_flags}`
// the hub will receive, encrypted at rest with QueueCrypto like every other
// queue. Rows are removed ONLY on a hub ack. A result the hub refuses for good
// (unknown student, test not in the pack, ...) is kept and marked REJECTED
// with a short machine reason — never dropped silently — so it can be shown to
// the operator instead of vanishing.
//
// Rows carry the `pack_uuid` of the hub they were made for: after a re-join to
// a hub of a DIFFERENT pack, they are not posted there.
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'offline_queue.dart';
import 'queue_crypto.dart';

class OutboxRow {
  final int id;
  final String packUuid;
  final String idempotencyKey;

  /// Decrypted envelope JSON text, exactly what is POSTed.
  final String envelopeJson;
  final int attempts;

  const OutboxRow({
    required this.id,
    required this.packUuid,
    required this.idempotencyKey,
    required this.envelopeJson,
    required this.attempts,
  });
}

class LanOutboxDb {
  LanOutboxDb._();

  static const int statusPending = 0;
  static const int statusRejected = 2;

  static Future<Database> get _db => OfflineQueue.db;

  /// Idempotent on (pack, key): a repeat is ignored.
  static Future<void> enqueue({
    required String packUuid,
    required String idempotencyKey,
    required String envelopeJson,
    int? nowMs,
  }) async {
    final d = await _db;
    await d.insert(
      'lan_outbox',
      {
        'pack_uuid': packUuid,
        'idempotency_key': idempotencyKey,
        'envelope': await QueueCrypto.encryptPayload(envelopeJson),
        'created': nowMs ?? DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Pending rows of [packUuid], oldest first. A row that cannot be decrypted
  /// is skipped here but stays in the table (it is counted by [counts]).
  static Future<List<OutboxRow>> pending(String packUuid,
      {int limit = 20}) async {
    final d = await _db;
    final rows = await d.query('lan_outbox',
        where: 'pack_uuid = ? AND status = ?',
        whereArgs: [packUuid, statusPending],
        orderBy: 'id ASC',
        limit: limit);
    if (rows.isEmpty) return [];
    final out = <OutboxRow>[];
    for (final r in rows) {
      try {
        out.add(OutboxRow(
          id: r['id'] as int,
          packUuid: r['pack_uuid'] as String,
          idempotencyKey: r['idempotency_key'] as String,
          envelopeJson:
              await QueueCrypto.decryptPayload(r['envelope'] as String),
          attempts: (r['attempts'] as int?) ?? 0,
        ));
      } catch (_) {
        // Corrupt/tampered row: leave it in place, never delete a result.
      }
    }
    return out;
  }

  /// The hub acknowledged this result: it is safe to forget.
  static Future<void> ack(int id) async {
    final d = await _db;
    await d.delete('lan_outbox', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> markAttempt(int id) async {
    final d = await _db;
    await d.rawUpdate(
        'UPDATE lan_outbox SET attempts = attempts + 1 WHERE id = ?', [id]);
  }

  /// The hub refused this result permanently. Kept, flagged with [reason].
  static Future<void> markRejected(int id, String reason) async {
    final d = await _db;
    await d.update(
        'lan_outbox',
        {
          'status': statusRejected,
          'reject_reason':
              reason.length > 64 ? reason.substring(0, 64) : reason,
        },
        where: 'id = ?',
        whereArgs: [id]);
  }

  /// (pending, rejected) over ALL packs — for the operator's status line.
  static Future<({int pending, int rejected})> counts() async {
    final d = await _db;
    final res = await d
        .rawQuery('SELECT status, COUNT(*) c FROM lan_outbox GROUP BY status');
    var pending = 0, rejected = 0;
    for (final r in res) {
      final c = (r['c'] as int?) ?? 0;
      if (r['status'] == statusRejected) {
        rejected += c;
      } else {
        pending += c;
      }
    }
    return (pending: pending, rejected: rejected);
  }
}
