// lib/core/offline/export_format.dart
//
// The ONE place that decides what a `.alochires` entry looks like as JSON and
// how many bytes it takes. ResultsExporter writes with [exportEntry]/
// [encodeEntries]; the LAN hub budgets the chain with [exportEntryBytes] -- the
// very same functions -- so what the hub admits is what the exporter will
// write, and the server's limit on the DECRYPTED JSON (10 MiB, offline_pack.py)
// cannot be exceeded by an entry the hub accepted. (A hand-made estimate was
// 2x off for payloads full of backslashes, which JSON escapes twice: once in
// payload_json, again in the envelope.)
import 'dart:convert';

/// EXACTLY these four keys (format 2): the server rejects the whole file on any
/// other key. idempotency_key / incidents / clock_flags live only inside
/// meta_json, which is part of the HMAC chain.
Map<String, String> exportEntry({
  required String prevHash,
  required String hash,
  required String payloadJson,
  required String metaJson,
}) =>
    {
      'prev_hash': prevHash,
      'hash': hash,
      'payload_json': payloadJson,
      'meta_json': metaJson,
    };

/// The plaintext that gets AES-GCM encrypted into payload.enc.
String encodeEntries(List<Map<String, String>> entries) =>
    jsonEncode({'entries': entries});

const String _zeroHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// Bytes [payloadJson]+[metaJson] add to the plaintext of an export: the
/// entry's own JSON (hashes are fixed-length, so placeholders are exact) plus
/// the comma that separates it from the next one.
int exportEntryBytes(String payloadJson, String metaJson) =>
    utf8
        .encode(jsonEncode(exportEntry(
            prevHash: _zeroHash,
            hash: _zeroHash,
            payloadJson: payloadJson,
            metaJson: metaJson)))
        .length +
    1;

/// Fixed bytes of the plaintext around the entries (`{"entries":[]}`).
final int exportEnvelopeBytes = utf8.encode(encodeEntries(const [])).length;

/// Running size of one pack's chain in EXPORT bytes (the unit the server's
/// 10 MiB limit is in), in total and per roster student. Whoever writes to the
/// chain while the LAN hub budgets it (the hub, and the teacher's own
/// OfflinePackSession.recordResult) does so under the session's chain lock and
/// calls [add], so the budget never drifts from what the exporter will write.
class ChainUsage {
  int bytes;
  int count;
  final Map<String, ({int count, int bytes})> perStudent;

  ChainUsage(this.bytes, this.count, this.perStudent);

  /// A chain with no results yet.
  ChainUsage.empty()
      : bytes = exportEnvelopeBytes,
        count = 0,
        perStudent = {};

  /// Student ids with at least one stored result.
  int get studentsWithResults => perStudent.length;

  void add(String? studentId, int entryBytes) {
    bytes += entryBytes;
    count++;
    if (studentId == null || studentId.isEmpty) return;
    final u = perStudent[studentId];
    perStudent[studentId] =
        (count: (u?.count ?? 0) + 1, bytes: (u?.bytes ?? 0) + entryBytes);
  }
}
