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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import '../db/pack_results_db.dart';
import '../db/test_cache.dart';
import '../security/incident_log.dart';
import '../security/monitored_clock.dart';
import '../../features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'offline_diagnostic_api.dart';
import 'offline_media.dart';
import 'offline_package_api.dart';
import 'pack_loader.dart';

class OfflinePackSession {
  final LoadedPack pack;
  final Directory mediaDir;

  OfflinePackSession._(this.pack, this.mediaDir);

  /// The open session, or null in normal (online) mode.
  static OfflinePackSession? current;

  /// UI hook: fires whenever a pack is opened or closed.
  static final ValueNotifier<OfflinePackSession?> notifier =
      ValueNotifier<OfflinePackSession?>(null);

  static bool get isActive => current != null;

  static MonitoringApi? _onlineApi;
  static DiagnosticKioskApi? _onlineDiagnosticApi;

  /// Where pack images are extracted: `<appSupport>/offline_store/media`.
  static Future<Directory> defaultMediaDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'offline_store', 'media'));
  }

  /// Switches the app into pack mode for [pack] (already unlocked; its images
  /// are already extracted into [mediaDir]).
  static Future<OfflinePackSession> open(
      LoadedPack pack, Directory mediaDir) async {
    if (current != null) close();

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

    final session = OfflinePackSession._(pack, mediaDir);
    _onlineApi = api;
    _onlineDiagnosticApi = diagnosticKioskApi;
    api = OfflinePackageApi(session);
    diagnosticKioskApi = OfflineDiagnosticKioskApi(session);
    TestCache.enterMemoryMode();
    OfflineMedia.root = mediaDir;
    MonitoredClock.instance.packCreatedAt = pack.manifest.createdAt;
    current = session;
    notifier.value = session;
    return session;
  }

  /// Back to online mode. Drops the in-memory content and the chain key.
  static void close() {
    if (current == null) return;
    final online = _onlineApi;
    if (online != null) api = online;
    final onlineDiag = _onlineDiagnosticApi;
    if (onlineDiag != null) diagnosticKioskApi = onlineDiag;
    _onlineApi = null;
    _onlineDiagnosticApi = null;
    TestCache.exitMemoryMode();
    OfflineMedia.root = null;
    MonitoredClock.instance.packCreatedAt = null;
    current = null;
    notifier.value = null;
  }

  // ── pack content ──────────────────────────────────────────────────────────

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
  Future<PackResultRow> recordResult(Map<String, dynamic> payload,
      {String? token}) {
    final key =
        (token == null || token.isEmpty) ? newIdempotencyToken() : token;
    return PackResultsDb.append(
      packUuid: pack.packUuid,
      chainKey: pack.chainKey,
      idempotencyKey: key,
      payloadJson: jsonEncode(payload),
      incidents: IncidentLog.instance.drain(),
      clockFlags: MonitoredClock.instance.drainFlags(),
    );
  }
}
