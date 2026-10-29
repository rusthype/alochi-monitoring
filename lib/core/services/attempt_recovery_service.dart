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
// Offline modes (wave 8a). A scan used to be a no-op while a USB pack or a LAN
// session was open. Every stored attempt now carries `result_scope`
// (`cloud` | `pack:<uuid>` | `lan:<uuid>`, see currentResultScope), and during
// a session the sweep only finalises attempts of THAT session, through the
// channel the session itself uses for results (pack HMAC chain /
// hub outbox) - never the online queue. Everything else is left parked on
// disk, untouched, and counted in [deferred]:
//  * an attempt of another scope (a cloud attempt while a pack is open, another
//    pack, a record from before `result_scope` existed) - submitting it into
//    the wrong chain would misattribute it;
//  * anything the student is still taking, paused, or with time left.
// With no session open the scan behaves as before (online queue, every scope):
// the result then has no other way to reach anyone.
// KNOWN GAP: an attempt of a session that is never reopened is only delivered
// by the next cloud-mode scan, i.e. through the online queue.
//
// The queue token is the one the engine host would derive for the same
// attempt (buildResultToken), so a later normal completion or a second scan
// can never create a duplicate: the queue's unique token index ignores it and
// the server dedups on the same Idempotency-Key.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/test/engine_host_screen.dart'
    show buildResultToken, tokenForStoredAttempt;
import '../api/api_client.dart' show api;
import '../diagnostics/active_test_gate.dart';
import '../db/attempt_store.dart';
import '../db/offline_queue.dart';
import '../db/test_cache.dart';
import '../models/test_version.dart';
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
    Future<int?> Function(AttemptEntry entry)? serverRemainingSeconds,
    Future<void> Function(AttemptEntry entry, Map<String, dynamic> record)?
        extendEntry,
    MonitoredClock? clock,
    bool Function()? testScreenActive,
    String Function()? resultScope,
    Future<void> Function(Map<String, dynamic> payload, String token)?
        recordInSession,
    ValueListenable<bool>? gate,
    this.scanEvery = const Duration(minutes: 10),
    this.gateDebounce = const Duration(seconds: 5),
    this.retryAfter = const Duration(minutes: 1),
    this.startWait = const Duration(seconds: 5),
  })  : _listAll = listAll ?? AttemptStore.listAll,
        _clearEntry = clearEntry ?? AttemptStore.clearEntry,
        _enqueue = enqueue ?? OfflineQueue.enqueueLocal,
        _markDone = markDone ?? RosterDoneStore.add,
        _currentVersion = currentVersion ?? TestCache.versionOf,
        _serverRemaining = serverRemainingSeconds ?? _serverRemainingDefault,
        _extendEntry = extendEntry ?? _extendEntryDefault,
        _clock = clock,
        _gate = gate ?? ActiveTestGate.active,
        _testScreenActive = testScreenActive ??
            // The gate is held from the Start tap (before the engine screen
            // exists), the heartbeat flag only once the engine is mounted.
            (() =>
                HeartbeatService.instance.testScreenActive ||
                ActiveTestGate.active.value),
        _scope = resultScope ?? currentResultScope,
        _recordInSession = recordInSession ?? _recordInSessionDefault;

  static final AttemptRecoveryService instance = AttemptRecoveryService();

  /// Slow safety-net rescan while the app runs (an always-online kiosk has no
  /// restart and no offline -> online edge).
  final Duration scanEvery;

  /// Delay between the active-test gate releasing and the rescan.
  final Duration gateDebounce;

  /// Delay before a scan that was aborted / had a failure is repeated.
  final Duration retryAfter;

  /// Longest a Start tap waits for a recovery of the same student in flight.
  final Duration startWait;

  /// How long the hub is asked for the remaining time of an expired attempt.
  static const Duration _serverTimeout = Duration(seconds: 3);

  final Future<List<AttemptEntry>> Function() _listAll;
  final Future<void> Function(AttemptEntry) _clearEntry;
  final Future<void> Function(Map<String, dynamic>, String) _enqueue;
  final Future<void> Function(String, String) _markDone;
  final Future<int?> Function(String) _currentVersion;
  final Future<int?> Function(AttemptEntry) _serverRemaining;
  final Future<void> Function(AttemptEntry, Map<String, dynamic>) _extendEntry;
  final MonitoredClock? _clock;
  final ValueListenable<bool> _gate;
  final bool Function() _testScreenActive;

  /// `cloud` with no session open, else the scope of the open pack / LAN
  /// session (see [currentResultScope]).
  final String Function() _scope;

  /// An open pack / LAN session routes results through its own chain / outbox,
  /// never the online queue: this is that channel.
  final Future<void> Function(Map<String, dynamic>, String) _recordInSession;

  /// Attempts the last scan left parked because they belong to another result
  /// channel than the open session (see the file header). Never lost: they are
  /// swept in the matching mode.
  int get deferred => _deferred;
  int _deferred = 0;

  MonitoredClock get _c => _clock ?? MonitoredClock.instance;

  bool _running = false;
  bool _rerun = false;
  bool _retryNeeded = false;
  bool _serverDown = false;
  bool _disposed = false;
  bool _started = false;
  StreamSubscription<SignalReading>? _sub;
  Timer? _periodic;
  Timer? _pending;
  bool _gateWasActive = false;

  /// Students whose record is being queued/cleared right now.
  final Map<String, Completer<void>> _recovering = {};

  /// Scans once now (in the background), again on every offline -> online
  /// edge, when the active-test gate releases (debounced) and every
  /// [scanEvery]. Idempotent; never throws.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(run());
    var wasOffline = false;
    _sub = ConnectivityService.instance.readings.listen((r) {
      if (r.checking) return;
      final online = r.tier != SignalTier.none;
      if (online && wasOffline) unawaited(run());
      wasOffline = !online;
    });
    _periodic = Timer.periodic(scanEvery, (_) => unawaited(run()));
    _gate.addListener(_onGate);
  }

  /// Cancels every timer / subscription; no scan starts afterwards.
  void dispose() {
    _disposed = true;
    _periodic?.cancel();
    _pending?.cancel();
    _periodic = _pending = null;
    unawaited(_sub?.cancel());
    _sub = null;
    if (_started) _gate.removeListener(_onGate);
  }

  void _onGate() {
    final active = _gate.value;
    if (_gateWasActive && !active) _scheduleRun(gateDebounce);
    _gateWasActive = active;
  }

  void _scheduleRun(Duration after) {
    if (_disposed) return;
    _pending?.cancel();
    _pending = Timer(after, () => unawaited(run()));
  }

  /// The Start path calls this (holding the active-test gate) before it reads
  /// the student's stored attempt: a recovery of the same student that is
  /// already queueing / clearing it finishes first, so the engine never reads
  /// a record that is being cleared. Bounded; never throws.
  Future<void> waitForRecovery(String studentId) async {
    final c = _recovering[studentId];
    if (c == null) return;
    try {
      await c.future.timeout(startWait);
    } on TimeoutException {
      debugPrint('AttemptRecovery: gave up waiting for $studentId');
    }
  }

  /// One scan. Returns how many attempts were queued. Overlapping calls never
  /// run concurrently (one more scan follows the running one); scans while a
  /// test screen is open are no-ops (the open attempt owns its own
  /// completion). An aborted scan or a failed record schedules a retry.
  Future<int> run() async {
    if (_disposed) return 0;
    if (_running) {
      _rerun = true;
      return 0;
    }
    if (_testScreenActive()) return 0;
    _running = true;
    _retryNeeded = false;
    _serverDown = false;
    _deferred = 0;
    var recovered = 0;
    try {
      for (final entry in await _listAll()) {
        if (_disposed) break;
        if (_testScreenActive()) {
          _retryNeeded = true;
          break;
        }
        try {
          if (await _recover(entry)) recovered++;
        } catch (e, st) {
          _retryNeeded = true;
          debugPrint(
              'AttemptRecovery: ${entry.slotKey} failed, kept for later: '
              '$e\n$st');
        }
      }
    } catch (e, st) {
      _retryNeeded = true;
      debugPrint('AttemptRecovery: scan failed: $e\n$st');
    } finally {
      _running = false;
    }
    if (recovered > 0) {
      debugPrint('AttemptRecovery: queued $recovered attempt(s)');
    }
    if (_rerun) {
      _rerun = false;
      _scheduleRun(gateDebounce);
    } else if (_retryNeeded) {
      _scheduleRun(retryAfter);
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
        versionChanged = testVersionChanged(savedVersion.toInt(), now);
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
          serverEpochAtSaveMs:
              (rec['server_epoch_at_save_ms'] as num?)?.toInt(),
          serverSourceAtSave: rec['server_source']?.toString(),
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

    // During a pack / LAN session only that session's own attempts are
    // finalised, and through its own channel. Anything else stays parked.
    final scope = _scope();
    final inSession = scope != 'cloud';
    if (inSession && rec['result_scope']?.toString() != scope) {
      _deferred++;
      return false;
    }

    final studentId = rec['student_id']?.toString() ?? '';
    final token = tokenForStoredAttempt(testKey, rec) ??
        buildResultToken(testKey, studentId, 'rec-');

    // The student may have tapped Start while this scan was reading: the open
    // attempt owns its completion (same token), so leave it alone. Nothing
    // awaits between this check and the flag, so a Start tap either sees the
    // gate here or finds the flag in [waitForRecovery].
    if (_testScreenActive()) {
      _retryNeeded = true;
      return false;
    }
    final busy = Completer<void>();
    _recovering[studentId] = busy;
    try {
      if (reason == 'deadline_passed' && await _serverGrantsTime(entry)) {
        return false; // the hub says time remains: not ours to submit
      }
      // The hub lookup above awaited: a session may have opened / closed since
      // the channel was chosen. Never write into a different one.
      if (_testScreenActive() || _scope() != scope) {
        _retryNeeded = true;
        return false;
      }
      final payload = _payload(rec, testKey, reason, durationS);
      if (inSession) {
        // Same token as the engine host: a second record is a no-op.
        await _recordInSession(payload, token);
      } else {
        await _enqueue(payload, token);
      }
      // Queued: from here the result is safe; bookkeeping must not undo that.
      try {
        // The engine host marks the roster for the online queue and the LAN
        // client only - a pack roster reads its own chain.
        if (!scope.startsWith('pack:')) await _markDone(testKey, studentId);
      } catch (e) {
        debugPrint('AttemptRecovery: roster mark failed: $e');
      }
      // A Start tap in the window above may already have the engine reading
      // this record: keep it (same token -> the engine's own completion is
      // deduplicated) rather than clear it under the engine. clearEntry itself
      // only deletes a record that is still unchanged.
      if (_testScreenActive()) {
        _retryNeeded = true;
        return true;
      }
      await _clearEntry(entry);
      return true;
    } finally {
      _recovering.remove(studentId);
      busy.complete();
    }
  }

  /// Local deadline passed: ask the hub (it knows teacher pause / extra time)
  /// for the session's remaining time. True = time remains, the stored
  /// deadline was moved accordingly and the attempt is NOT submitted. Offline,
  /// error, timeout or no such session = false (the local deadline stands).
  Future<bool> _serverGrantsTime(AttemptEntry entry) async {
    if (_serverDown) return false;
    int? remainingS;
    try {
      remainingS = await _serverRemaining(entry);
    } catch (e) {
      _serverDown = true; // do not make every further record wait again
      debugPrint('AttemptRecovery: hub remaining-time check failed: $e');
      return false;
    }
    if (remainingS == null || remainingS <= 0) return false;
    final c = _c;
    try {
      await _extendEntry(entry, {
        // The old server epoch belongs to the old save: a snapshot without
        // one (server unknown now) must not leave it next to the new
        // epoch_at_save / ticks_at_save.
        ...({...entry.record}
          ..remove('server_epoch_at_save_ms')
          ..remove('server_source')),
        'deadline_epoch_ms': c.nowMs + remainingS * 1000,
        ...c.snapshotRecord(),
      });
    } catch (e) {
      // Could not persist the extension: still do not submit what the hub
      // says is live; the next scan asks again.
      _retryNeeded = true;
      debugPrint('AttemptRecovery: could not store hub extension: $e');
    }
    return true;
  }

  static Future<void> _recordInSessionDefault(
      Map<String, dynamic> payload, String token) async {
    final pack = OfflinePackSession.current;
    if (pack != null) {
      await pack.recordResult(payload, token: token);
      return;
    }
    final lan = LanClientSession.current;
    if (lan == null) throw StateError('offline session closed during recovery');
    await lan.recordResult(payload, token: token);
  }

  /// Production hub lookup: the engine's own session-resume call, bounded by
  /// [_serverTimeout]. Null = unknown (no login, no session, other variant).
  static Future<int?> _serverRemainingDefault(AttemptEntry entry) async {
    if (!api.isLan && !api.hasAuthToken) return null;
    final resp =
        await api.sessionResume(entry.testKey).timeout(_serverTimeout);
    return remainingFromResume(resp, entry.record);
  }

  /// The hub's remaining seconds, honoured only when the answer is about THIS
  /// attempt: same variant, same student id, and - when the backend sends
  /// `student_code` (older ones omit it) - the same student code. The stored
  /// attempt keeps the code in `student_id` (the engine passes the one as the
  /// other); both sides are compared exactly, as everywhere else in the app.
  @visibleForTesting
  static int? remainingFromResume(
      Map<String, dynamic> resp, Map<String, dynamic> rec) {
    if (resp['exists'] != true) return null;
    final sv = int.tryParse(resp['variant']?.toString() ?? '');
    final lv = int.tryParse(rec['variant']?.toString() ?? '');
    if (sv != null && lv != null && sv != lv) return null;
    final stored = rec['student_id']?.toString() ?? '';
    final sid = resp['student_id']?.toString() ?? '';
    if (sid.isNotEmpty && sid != stored) return null;
    final code = resp['student_code']?.toString() ?? '';
    if (code.isNotEmpty && code != stored) return null;
    final r = resp['remaining_seconds'];
    return r is num ? r.toInt() : null;
  }

  static Future<void> _extendEntryDefault(
      AttemptEntry entry, Map<String, dynamic> record) async {
    await AttemptStore.replaceEntry(entry, record);
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
