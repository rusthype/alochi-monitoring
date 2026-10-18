// lib/core/offline/offline_session.dart
//
// The one open `.alochipack`. Opening it flips the app into "offline pack
// mode": the global `api` becomes an [OfflinePackageApi] reading the pack,
// test content is kept in memory only (TestCache memory mode), pack images are
// served from disk, and every finished test is appended to the pack's HMAC
// chain (PackResultsDb) instead of being uploaded.
//
// Closing it restores the online client. The session holds only the derived
// chain key — never the PIN.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../db/pack_results_db.dart';
import '../db/test_cache.dart';
import '../security/incident_log.dart';
import '../local_server/hub_guard.dart' show Mutex;
import '../security/monitored_clock.dart';
import 'export_format.dart';
import '../../features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'offline_diagnostic_api.dart';
import 'offline_content_source.dart';
import 'offline_media.dart';
import 'offline_package_api.dart';
import 'pack_loader.dart';

class OfflinePackSession implements OfflineContentSource {
  final LoadedPack pack;
  final Directory mediaDir;

  OfflinePackSession._(this.pack, this.mediaDir);

  /// "Check budget -> append -> account" on this pack's chain is one critical
  /// section for EVERY writer (LAN hub results and the teacher's own).
  final Mutex chainLock = Mutex();

  /// Export-format size of the chain, cached by the LAN hub's budget; null =
  /// unknown (re-measured from the database). Touch only under [chainLock].
  ChainUsage? chainUsage;

  /// The open session, or null in normal (online) mode.
  static OfflinePackSession? current;

  /// UI hook: fires whenever a pack is opened or closed.
  static final ValueNotifier<OfflinePackSession?> notifier =
      ValueNotifier<OfflinePackSession?>(null);

  static bool get isActive => current != null;

  static DiagnosticKioskApi? _onlineDiagnosticApi;

  static Future<Directory> _mediaRoot() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'offline_store', 'media'));
  }

  /// Where ONE pack's images are extracted:
  /// `<appSupport>/offline_store/media/<pack_uuid>/`.
  static Future<Directory> mediaDirFor(String packUuid) async =>
      Directory(p.join((await _mediaRoot()).path, packUuid));

  /// Deletes extracted images of every pack except [keepPackUuid] (and any
  /// stray files from older layouts). Called when a pack is opened, when
  /// offline mode is left, and when the control center opens with no pack
  /// open — decrypted-at-rest content must not outlive its session (the pack
  /// has to be re-opened with its PIN after a restart anyway).
  static Future<void> cleanupMedia({String? keepPackUuid}) async {
    try {
      final root = await _mediaRoot();
      if (!await root.exists()) return;
      await for (final e in root.list()) {
        if (keepPackUuid != null && p.basename(e.path) == keepPackUuid) {
          continue;
        }
        await e.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('OfflinePackSession.cleanupMedia failed (non-fatal): $e');
    }
  }

  static final Mutex _openLock = Mutex();

  /// Switches the app into pack mode for [pack] (already unlocked; its images
  /// are already extracted into [mediaDir]).
  ///
  /// Opens are serialised and every awaited step runs BEFORE the active
  /// session is touched: a second open (double click, re-open of the same
  /// pack) that fails must never leave the first one closed, and two opens
  /// must never both park "the online api" (the second would park the first's
  /// offline api and close() could never get back online).
  static Future<OfflinePackSession> open(LoadedPack pack, Directory mediaDir) =>
      _openLock.run(() async {
        await PackResultsDb.registerPack(
          packUuid: pack.packUuid,
          schoolCode: pack.schoolCode,
          expiresAt: pack.manifest.expiresAt,
        );
        try {
          await PackResultsDb.purgeExpired();
        } catch (e) {
          debugPrint('OfflinePackSession: purgeExpired failed (non-fatal): $e');
        }

        // From here to `notifier.value = session` nothing awaits.
        if (current != null) _restoreOnline();
        final session = OfflinePackSession._(pack, mediaDir);
        parkedOnlineApi = api;
        _onlineDiagnosticApi = diagnosticKioskApi;
        api = OfflinePackageApi(session);
        diagnosticKioskApi = OfflineDiagnosticKioskApi(session);
        TestCache.enterMemoryMode();
        OfflineMedia.root = mediaDir;
        MonitoredClock.instance.packCreatedAt = pack.manifest.createdAt;
        current = session;
        notifier.value = session;
        await cleanupMedia(keepPackUuid: pack.packUuid);
        return session;
      });

  /// Back to online mode. Drops the in-memory content and the chain key, and
  /// deletes the extracted images.
  static void close() {
    if (current == null) return;
    _restoreOnline();
    unawaited(cleanupMedia());
  }

  static void _restoreOnline() {
    if (current == null) return;
    final online = parkedOnlineApi;
    if (online != null) api = online;
    final onlineDiag = _onlineDiagnosticApi;
    if (onlineDiag != null) diagnosticKioskApi = onlineDiag;
    parkedOnlineApi = null;
    _onlineDiagnosticApi = null;
    TestCache.exitMemoryMode();
    OfflineMedia.root = null;
    MonitoredClock.instance.packCreatedAt = null;
    current = null;
    notifier.value = null;
  }

  // ── pack content ──────────────────────────────────────────────────────────

  @override
  String get packUuid => pack.packUuid;
  @override
  String get schoolId => pack.schoolId;
  @override
  String get schoolCode => pack.schoolCode;
  @override
  List<Map<String, dynamic>> get groups => pack.groups;
  @override
  List<Map<String, dynamic>> get students => pack.students;

  @override
  Future<int> nextAttemptOrdinal(String keyPrefix) async =>
      await PackResultsDb.countKeyPrefix(pack.packUuid, keyPrefix) + 1;

  @override
  Future<bool> hasAttempt(String keyPrefix) async =>
      await PackResultsDb.countKeyPrefix(pack.packUuid, keyPrefix) > 0;

  /// Student ids (the payload's `student_id`, = the roster `id`) that already
  /// have a stored result for [testKey]. Monitoring keys are random UUIDs (no
  /// per-student prefix like the diagnostic's), so the done-state is read from
  /// the payloads. ponytail: decrypts the whole chain per roster load; add a
  /// key->student index if packs grow past a few thousand rows.
  Future<Set<String>> finishedStudentIds(String testKey) async {
    final out = <String>{};
    for (final r in await PackResultsDb.rowsForPack(pack.packUuid)) {
      try {
        final m = jsonDecode(r.payloadJson);
        if (m is! Map) continue;
        final d = m['detail'];
        final key = (d is Map ? d['test_key'] : null) ?? m['test_key'];
        final sid = m['student_id']?.toString() ?? '';
        if (sid.isNotEmpty && key?.toString() == testKey) out.add(sid);
      } catch (e) {
        debugPrint('finishedStudentIds: skipped unreadable row: $e');
      }
    }
    return out;
  }

  @override
  Future<void> prepareMedia(Object? data) async {} // images already on disk

  @override
  List<Map<String, dynamic>> testsOfType(String type) =>
      pack.tests.where((t) => t['type'] == type).toList(growable: false);

  Map<String, dynamic>? testByKey(String key) {
    for (final t in pack.tests) {
      if (t['key']?.toString() == key) return t;
    }
    return null;
  }

  // ── results ───────────────────────────────────────────────────────────────

  /// Appends one finished test to the pack's HMAC chain. [payload] is exactly
  /// the body the online `POST /monitoring/result/` would get; it is hashed as
  /// text, so it is serialised once, here. Proctoring metadata and clock flags
  /// gathered since the last result ride along (decision 12).
  @override
  Future<PackResultRow> recordResult(Map<String, dynamic> payload,
      {String? token}) {
    final key =
        (token == null || token.isEmpty) ? newIdempotencyToken() : token;
    // Same critical section the LAN hub budgets the chain in: a result written
    // here must not slip between its check and its write, and must be counted.
    return chainLock.run(() async {
      final uuid = pack.packUuid;
      final payloadJson = jsonEncode(payload);
      final incidents = IncidentLog.instance.drain();
      final flags = MonitoredClock.instance.drainFlags();
      try {
        final isNew =
            chainUsage != null && !await PackResultsDb.hasKey(uuid, key);
        final row = await PackResultsDb.append(
          packUuid: uuid,
          chainKey: pack.chainKey,
          idempotencyKey: key,
          payloadJson: payloadJson,
          incidents: incidents,
          clockFlags: flags,
        );
        if (isNew) {
          chainUsage?.add(PackResultsDb.studentIdOf(payloadJson),
              exportEntryBytes(row.payloadJson, row.metaJson));
        }
        return row;
      } catch (_) {
        chainUsage = null; // unknown outcome: the next budget re-measures
        rethrow;
      }
    });
  }
}
