// lib/core/services/attempt_recovery_service.dart
//
// Startup recovery of attempts a power cut / crash / forced close left behind.
//
// Until now an attempt was only picked up again when the SAME student started
// the same test, so a finished-but-never-queued result (power cut between the
// "completed" marker and the queue write) or an abandoned attempt whose time
// ran out sat on disk unseen, and the teacher never got the result.
//
// One scan over every stored record (main and parked slots):
//  * completed, never queued  -> queue it now;
//  * unfinished, deadline passed (trusted clock, see MonitoredClock) ->
//    queue the saved answers as the result (the server re-scores from
//    `raw_answers`), product decision: the child loses nothing;
//  * unfinished attempt saved under ANOTHER test version -> queued right away
//    (reason `test_version_changed`): the engine cannot resume it, and the
//    first save of a new attempt would otherwise bury it;
//  * unfinished with time left, paused or empty -> left alone (the student
//    resumes through the normal flow).
//
// The queue token is the one the engine host would derive for the same
// attempt (buildResultToken), so a later normal completion or a second scan
// can never create a duplicate: the queue's unique token index ignores it and
// the server dedups on the same Idempotency-Key.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/test/engine_host_screen.dart'
    show buildResultToken, tokenForStoredAttempt;
import '../diagnostics/active_test_gate.dart';
import '../db/attempt_store.dart';
import '../db/offline_queue.dart';
import '../db/test_cache.dart';
import '../network/connectivity_service.dart';
import '../offline/lan_client_session.dart';
import '../offline/offline_session.dart';
import '../security/monitored_clock.dart';
import 'heartbeat_service.dart';
import 'roster_done_store.dart';

class AttemptRecoveryService {
  AttemptRecoveryService({
    Future<List<AttemptEntry>> Function()? listAll,
    Future<void> Function(AttemptEntry)? clearEntry,
    Future<void> Function(Map<String, dynamic> payload, String token)? enqueue,
    Future<void> Function(String testKey, String studentId)? markDone,
    Future<int?> Function(String testKey)? currentVersion,
    MonitoredClock? clock,
    bool Function()? testScreenActive,
    bool Function()? offlineSessionActive,
  })  : _listAll = listAll ?? AttemptStore.listAll,
        _clearEntry = clearEntry ?? AttemptStore.clearEntry,
        _enqueue = enqueue ?? OfflineQueue.enqueueLocal,
        _markDone = markDone ?? RosterDoneStore.add,
        _currentVersion = currentVersion ?? TestCache.versionOf,
        _clock = clock,
        _testScreenActive = testScreenActive ??
            // The gate is held from the Start tap (before the engine screen
            // exists), the heartbeat flag only once the engine is mounted.
            (() =>
                HeartbeatService.instance.testScreenActive ||
                ActiveTestGate.active.value),
        _offlineSessionActive = offlineSessionActive ??
            (() =>
                OfflinePackSession.current != null ||
                LanClientSession.current != null);

  static final AttemptRecoveryService instance = AttemptRecoveryService();

  final Future<List<AttemptEntry>> Function() _listAll;
  final Future<void> Function(AttemptEntry) _clearEntry;
  final Future<void> Function(Map<String, dynamic>, String) _enqueue;
  final Future<void> Function(String, String) _markDone;
  final Future<int?> Function(String) _currentVersion;
  final MonitoredClock? _clock;
  final bool Function() _testScreenActive;

  /// An offline pack / LAN session routes results through its own chain, not
  /// the online queue, so nothing is recovered into the queue meanwhile.
  final bool Function() _offlineSessionActive;

  MonitoredClock get _c => _clock ?? MonitoredClock.instance;

  bool _running = false;
  StreamSubscription<SignalReading>? _sub;

  /// Scans once now (in the background) and again on every offline -> online
  /// edge. Idempotent; never throws.
  void start() {
    if (_sub != null) return;
    unawaited(run());
    var wasOffline = false;
    _sub = ConnectivityService.instance.readings.listen((r) {
      if (r.checking) return;
      final online = r.tier != SignalTier.none;
      if (online && wasOffline) unawaited(run());
      wasOffline = !online;
    });
  }

  /// One scan. Returns how many attempts were queued. Re-entrant calls and
  /// scans while a test screen is open are no-ops (the open attempt owns its
  /// own completion; the record stays and the next scan picks it up).
  Future<int> run() async {
    if (_running) return 0;
    if (_testScreenActive() || _offlineSessionActive()) return 0;
    _running = true;
    var recovered = 0;
    try {
      for (final entry in await _listAll()) {
        if (_testScreenActive()) break;
        try {
          if (await _recover(entry)) recovered++;
        } catch (e, st) {
          debugPrint(
              'AttemptRecovery: ${entry.slotKey} failed, kept for later: '
              '$e\n$st');
        }
      }
    } catch (e, st) {
      debugPrint('AttemptRecovery: scan failed: $e\n$st');
    } finally {
      _running = false;
    }
    if (recovered > 0) {
      debugPrint('AttemptRecovery: queued $recovered attempt(s)');
    }
    return recovered;
  }

  Future<bool> _recover(AttemptEntry entry) async {
    final rec = entry.record;
    final testKey = entry.testKey;
    // The diagnostic runner keeps its own blobs here; it has its own recovery.
    if (testKey.isEmpty || testKey.startsWith('diag_')) return false;

    final completed = rec['completed'] == true;
    final answers = rec['answers'];
    if (answers is! Map) return false;

    String reason;
    int? durationS;
    if (completed) {
      reason = 'completed';
    } else {
      if (answers.isEmpty) return false; // nothing worth submitting
      final deadlineRaw = rec['deadline_epoch_ms'];
      if (deadlineRaw is! num) return false; // seeded, never started
      final savedVersion = rec['test_version'];
      var versionChanged = false;
      if (savedVersion is num) {
        final now = await _currentVersion(testKey);
        versionChanged = now != null && now != savedVersion.toInt();
      }
      if (versionChanged) {
        // The engine drops an attempt of another version (its keys map to
        // different questions), so it will never be resumed: submit what the
        // child answered instead of letting a new attempt bury it.
        reason = 'test_version_changed';
      } else {
        if (rec['paused_remaining_ms'] is num) return false; // frozen
        final c = _c;
        final deadline = c.rebaseSavedDeadline(
          deadlineEpochMs: deadlineRaw.toInt(),
          epochAtSaveMs: (rec['epoch_at_save'] as num?)?.toInt(),
          ticksAtSaveMs: (rec['ticks_at_save'] as num?)?.toInt(),
        );
        if (deadline > c.nowMs) return false; // time left: student resumes
        reason = 'deadline_passed';
      }
      final startedAt = rec['started_at'];
      if (startedAt is num) {
        final s = ((deadlineRaw.toInt() - startedAt.toInt()) / 1000).round();
        if (s > 0) durationS = s;
      }
    }

    // Identity needed to attribute the result; records written before the
    // recovery fields existed are left to the normal same-student replay.
    final school = rec['school'];
    if (school == null) return false;

    final studentId = rec['student_id']?.toString() ?? '';
    final token = tokenForStoredAttempt(testKey, rec) ??
        buildResultToken(testKey, studentId, 'rec-');

    // The student may have tapped Start while this scan was reading: the open
    // attempt owns its completion (same token), so leave it alone.
    if (_testScreenActive()) return false;
    await _enqueue(_payload(rec, testKey, reason, durationS), token);
    // Queued: from here the result is safe; bookkeeping must not undo that.
    try {
      await _markDone(testKey, studentId);
    } catch (e) {
      debugPrint('AttemptRecovery: roster mark failed: $e');
    }
    await _clearEntry(entry);
    return true;
  }

  /// Same shape as the engine host's minimal payload (the backend re-scores
  /// from `raw_answers`, so no local score is sent).
  Map<String, dynamic> _payload(
    Map<String, dynamic> rec,
    String testKey,
    String reason,
    int? durationS,
  ) =>
      <String, dynamic>{
        'name': rec['student_name']?.toString() ?? '',
        'grade': (rec['grade'] as num?)?.toInt() ?? 0,
        'variant': rec['variant']?.toString() ?? '',
        'source': 'flutter',
        'math': {'cor': 0, 'tot': 0},
        'english': {'cor': 0, 'tot': 0},
        'vocab': {'cor': 0, 'tot': 0},
        'pct': 0,
        'school_code': rec['school']?.toString() ?? '',
        'group_name': rec['group_name']?.toString() ?? '',
        'group_id': rec['group_id']?.toString() ?? '',
        'student_id': rec['student_id']?.toString() ?? '',
        'raw_answers': Map<String, dynamic>.from(rec['answers'] as Map),
        if (durationS != null) 'duration_seconds': durationS,
        'detail': <String, dynamic>{
          'sections': <Map<String, dynamic>>[],
          'topics': <Map<String, dynamic>>[],
          'units': <Map<String, dynamic>>[],
          'test_key': testKey,
          // The backend ignores unknown detail keys; kept in the stored
          // detail as an audit trail that this result was recovered.
          'recovered': reason,
        },
      };
}
