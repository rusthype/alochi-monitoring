// lib/core/local_server/hub_state.dart
//
// The LAN hub's brain: class code, joined clients, proctoring state and
// teacher commands. No sockets and no disk here — ShelfHub (shelf_hub.dart)
// owns the HTTP side and feeds validated input in — so every rule below is
// unit-testable with a fake clock.
//
// Everything is in memory ON PURPOSE: session tokens and screen frames are
// never written to disk (decision 7), and all of it disappears when the hub
// stops.
//
// Proctoring contract (must keep `HeartbeatService.reconcileProctorState`
// working unchanged): every ping/frame reply carries `locked`,
// `extra_time_seconds` (a running TOTAL for the current test attempt, never a
// delta), `commands` and `terminated`.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../security/monitored_clock.dart' show TicksFn;
import 'hub_guard.dart';

/// What the teacher sees for one client row.
enum ClientStatus { waiting, testing, inactive, locked, noContact }

enum JoinOutcome { ok, badCode, blocked, full, locked }

class JoinResult {
  final JoinOutcome outcome;
  final HubClient? client;
  final int retryAfterSec;
  const JoinResult(this.outcome, {this.client, this.retryAfterSec = 0});
}

/// A validated `POST /ping` body (see [PingInput.fromJson]).
class PingInput {
  final String sessionId;
  final String testKey;
  final String status;
  final String studentCode;
  final String name;
  final String deviceName;
  final int tabSwitchCount;
  final int? questionIndex;
  final int? totalQuestions;
  final int? elapsedSeconds;
  final int incidentCount;
  final List<String> capabilities;

  const PingInput({
    required this.sessionId,
    required this.testKey,
    required this.status,
    required this.studentCode,
    required this.name,
    required this.deviceName,
    required this.tabSwitchCount,
    required this.questionIndex,
    required this.totalQuestions,
    required this.elapsedSeconds,
    required this.incidentCount,
    required this.capabilities,
  });

  static const HubHttpError _bad = HubHttpError(400, 'bad_request');

  /// Ids: short, printable. Display text: truncated, never rejected (a long
  /// device name must not make a client look dead).
  static String _id(Object? v, int max) {
    if (v == null) return '';
    if (v is! String || v.length > max) throw _bad;
    for (final c in v.codeUnits) {
      if (c < 0x20 || c == 0x7f) throw _bad;
    }
    return v;
  }

  static String _text(Object? v, int max) {
    if (v is! String) return '';
    final cleaned = cleanDisplayText(v);
    return cleaned.length > max ? cleaned.substring(0, max) : cleaned;
  }

  static int? _int(Object? v, int min, int max) {
    if (v == null) return null;
    if (v is! num || v != v.toInt()) throw _bad;
    final n = v.toInt();
    if (n < min || n > max) throw _bad;
    return n;
  }

  factory PingInput.fromJson(Map<String, dynamic> j) {
    final status = _id(j['status'], 16);
    if (status != '' && status != 'active' && status != 'finished') throw _bad;
    final caps = j['capabilities'];
    return PingInput(
      sessionId: _id(j['session_id'], 64),
      testKey: _id(j['test_key'], 128),
      status: status.isEmpty ? 'active' : status,
      studentCode: _id(j['student_code'], 128),
      name: _text(j['name'], 120),
      deviceName: _text(j['device_name'], 64),
      tabSwitchCount: _int(j['tab_switch_count'], 0, 100000) ?? 0,
      questionIndex: _int(j['current_question_index'], 0, 100000),
      totalQuestions: _int(j['total_questions'], 0, 100000),
      elapsedSeconds: _int(j['elapsed_seconds'], 0, 1000000),
      incidentCount: _int(j['incident_count'], 0, 100000) ?? 0,
      capabilities: caps is List
          ? [
              for (final c in caps.take(16))
                if (c is String && c.length <= 32) c
            ]
          : const [],
    );
  }
}

/// One joined student PC.
class HubClient {
  /// Non-secret handle for the teacher UI.
  final int id;

  /// The bearer secret. Never logged, never serialised.
  final String token;
  final String machineId;
  final String ip;
  String deviceName;
  final TokenBucket bucket;

  int lastSeen;

  /// When this PC joined (kept across its own re-joins), for the teacher's
  /// seat-conflict banner.
  int connectedAt = 0;

  // Identity as announced by the client's pings.
  String name = '';
  String studentId = ''; // roster UUID when the ping's student_code is one
  String sessionId = ''; // current TEST attempt; '' = idle
  String testKey = '';
  String pingStatus = 'active';

  // Progress.
  int? questionIndex;
  int? totalQuestions;
  int tabSwitchCount = 0;
  int incidentCount = 0;
  int? elapsedReported;
  int elapsedReportedAt = 0;
  int sessionStartedAt = 0;
  List<String> capabilities = const [];

  // Teacher control. All per test attempt.
  bool locked = false;
  int extraTimeSeconds = 0;
  final Set<String> terminatedSessions = {};

  /// Attempts that are over. A late 'finished' ping that still carries such an
  /// id must not re-open it (it would look like a live holder for ~30 s).
  final Set<String> endedSessions = {};

  // Latest KEYFRAME (memory only).
  Uint8List? frame;
  int frameAt = 0;
  int frameVersion = 0;
  bool frameFocus = true;
  int monitorCount = 1;

  int resultsAccepted = 0;

  /// Requests being served for this token right now (S-002).
  int inFlight = 0;

  /// When the last frame arrived (any type), for the minimum frame interval.
  int lastFrameAt = 0;

  /// When a seat conflict of this client was last reported to the teacher.
  int lastConflictAt = 0;

  HubClient({
    required this.id,
    required this.token,
    required this.machineId,
    required this.ip,
    required this.deviceName,
    required this.bucket,
    required this.lastSeen,
  });

  bool get inTest => sessionId.isNotEmpty;

  /// A PC that joined again (same machine AND address) keeps what the hub
  /// already knows about it: which attempts were terminated or are over (a
  /// restart must not make a terminated attempt look fresh), its seat, quota
  /// counters.
  void inheritFrom(HubClient old) {
    terminatedSessions.addAll(old.terminatedSessions);
    endedSessions.addAll(old.endedSessions);
    sessionId = old.sessionId;
    testKey = old.testKey;
    studentId = old.studentId;
    sessionStartedAt = old.sessionStartedAt;
    resultsAccepted = old.resultsAccepted;
    lastConflictAt = old.lastConflictAt;
    connectedAt = old.connectedAt;
    // Pause and extra time belong to the attempt (same sessionId, copied
    // above): a re-join must neither lift the teacher's pause nor take back the
    // time already granted (N-6). A different attempt id resets both in
    // _claimSession as usual.
    locked = old.locked;
    extraTimeSeconds = old.extraTimeSeconds;
  }

  /// The test attempt is over (result submitted, idle ping, or taken over):
  /// forget its live state, including the screen frame.
  void endTest() {
    if (sessionId.isNotEmpty) {
      endedSessions.add(sessionId);
      if (endedSessions.length > 64) endedSessions.remove(endedSessions.first);
    }
    sessionId = '';
    testKey = '';
    studentId = '';
    questionIndex = null;
    totalQuestions = null;
    elapsedReported = null;
    locked = false;
    extraTimeSeconds = 0;
    frame = null;
    frameVersion++;
  }
}

class ClientView {
  final int id;
  final String name;
  final String className;
  final ClientStatus status;
  final int? questionNumber; // 1-based
  final int? totalQuestions;
  final int? remainingSeconds;
  final int tabSwitchCount;
  final int incidentCount;
  final int lastSeenAgoMs;
  final String ip;
  final String deviceName;
  final bool hasFrame;
  final int frameVersion;
  final bool locked;
  final int extraTimeSeconds;
  final int resultsAccepted;
  final bool inTest;

  const ClientView({
    required this.id,
    required this.name,
    required this.className,
    required this.status,
    required this.questionNumber,
    required this.totalQuestions,
    required this.remainingSeconds,
    required this.tabSwitchCount,
    required this.incidentCount,
    required this.lastSeenAgoMs,
    required this.ip,
    required this.deviceName,
    required this.hasFrame,
    required this.frameVersion,
    required this.locked,
    required this.extraTimeSeconds,
    required this.resultsAccepted,
    required this.inTest,
  });
}

/// One side of a seat conflict, as the teacher needs to judge it.
class SeatParty {
  final String deviceName;
  final String ip;
  final int connectedAgoMs;
  final ClientStatus status;
  const SeatParty({
    required this.deviceName,
    required this.ip,
    required this.connectedAgoMs,
    required this.status,
  });
}

/// Two PCs want the same student's seat. The first one keeps it until the
/// teacher decides; the hub never ends anybody's attempt on its own (S-003).
class SeatConflict {
  final int id;
  final String studentId;
  final String studentName;
  final String className;
  final int holderId;
  final SeatParty holder;
  final int claimantId;
  final SeatParty claimant;
  const SeatConflict({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.holderId,
    required this.holder,
    required this.claimantId,
    required this.claimant,
  });
}

class _ConflictRec {
  final int id;
  final String studentId;
  int holderId;
  int claimantId;
  _ConflictRec(this.id, this.studentId, this.holderId, this.claimantId);
}

class _Quota {
  int count = 0;
  int bytes = 0;
}

/// A seat the teacher freed for ONE claimant: only that PC may take it until
/// [until] (N-3).
class _SeatReserve {
  int claimantId;
  final int since;
  _SeatReserve(this.claimantId, this.since);
}

class HubState extends ChangeNotifier {
  final String packUuid;
  final String schoolId;
  final String schoolCode;
  final String hubName;
  final int maxClients;
  final int maxResultsPerIp;
  final int maxResultBytesPerIp;
  final TicksFn _ticks;
  final Random _rng;

  /// Every `tests[].key` of the pack — the only keys a result may carry.
  final Set<String> allowedTestKeys;

  /// `test key -> duration in minutes`, for the "time left" column.
  final Map<String, int> _durations;

  final Map<String, Map<String, dynamic>> _studentsById = {};
  final Map<String, String> _groupNames = {};
  final Set<String> _studentGroupPairs = {};
  final Map<String, List<String>> _groupsOfStudent = {};

  final JoinFailureGate _gate;
  final Map<String, HubClient> _byToken = {};
  late String _code;
  int _nextId = 1;
  int? _watchedId;

  int resultsAccepted = 0;

  /// Idempotency keys of results the hub refused and that are not stored yet
  /// (quota, pack full, key conflict, bad token...): what the teacher sees as
  /// "results are being refused". A key leaves the set when it is stored. Keys,
  /// not requests, so a PC's slow retries of one result count once (F-2).
  final Set<String> _refusedKeys = {};
  int get refusedResults => _refusedKeys.length;

  void noteResultRefused(String key) {
    if (_refusedKeys.length >= 1000 && !_refusedKeys.contains(key)) return;
    if (_refusedKeys.add(key)) _changed();
  }

  void noteResultStored(String key) {
    if (_refusedKeys.remove(key)) _changed();
  }

  final Map<String, _Quota> _quota = {};
  final Map<String, int> _ipInFlight = {};
  final List<_ConflictRec> _conflicts = [];
  final Map<String, int> _rejectedClaims = {};
  final Map<String, _SeatReserve> _seatReserved = {};
  int _nextConflictId = 1;
  bool _joinsLocked = false;

  Timer? _notifyTimer;
  bool _disposed = false;

  HubState({
    required this.packUuid,
    required this.schoolId,
    required this.schoolCode,
    required this.hubName,
    required Iterable<Map<String, dynamic>> groups,
    required Iterable<Map<String, dynamic>> students,
    required Iterable<String> allowedTestKeys,
    Map<String, int> testDurationsMinutes = const {},
    TicksFn? ticks,
    Random? random,
    this.maxClients = HubLimits.maxClients,
    this.maxResultsPerIp = HubLimits.maxResultsPerIp,
    this.maxResultBytesPerIp = HubLimits.maxResultBytesPerIp,
  })  : _ticks = ticks ?? (() => DateTime.now().millisecondsSinceEpoch),
        _rng = random ?? Random.secure(),
        allowedTestKeys = Set.unmodifiable(allowedTestKeys),
        _durations = Map.unmodifiable(testDurationsMinutes),
        _gate = JoinFailureGate(
            ticks: ticks ?? (() => DateTime.now().millisecondsSinceEpoch)) {
    for (final g in groups) {
      final id = g['id']?.toString() ?? '';
      if (id.isNotEmpty) _groupNames[id] = g['name']?.toString() ?? '';
    }
    for (final s in students) {
      final id = s['id']?.toString() ?? '';
      final gid = s['group_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      _studentsById[id] = s;
      if (gid.isNotEmpty) {
        _studentGroupPairs.add('$id|$gid');
        (_groupsOfStudent[id] ??= []).add(gid);
      }
    }
    _code = _newCode();
  }

  int _now() => _ticks();

  /// Students on the pack's roster (the reserve in ShelfHub counts these).
  int get rosterSize => _studentsById.length;

  // ── class code ─────────────────────────────────────────────────────────────

  String get code => _code;

  String _newCode() => _rng.nextInt(1000000).toString().padLeft(6, '0');

  /// New code for FUTURE joins; tokens already issued keep working.
  void rotateCode() {
    _code = _newCode();
    _changed();
  }

  // ── join / auth ────────────────────────────────────────────────────────────

  /// While locked, nobody new can join (the teacher closes joining once the
  /// whole class is in). It also keeps a flood of wrong codes -- which can
  /// trip the failure gates for everyone -- from mattering any more (S-005).
  bool get joinsLocked => _joinsLocked;

  void setJoinsLocked(bool locked) {
    if (_joinsLocked == locked) return;
    _joinsLocked = locked;
    _changed();
  }

  /// [holdsValidToken]: the caller presented a live token of the SAME machine.
  /// Such a PC is refreshing, not guessing, so the global failure gate and the
  /// join lock do not apply to it (the per-address gate still does).
  JoinResult join({
    required String ip,
    required String code,
    required String machineId,
    required String deviceName,
    bool holdsValidToken = false,
  }) {
    // Locked: refuse BEFORE looking at the code and without touching any
    // failure counter.
    if (_joinsLocked && !holdsValidToken) {
      return const JoinResult(JoinOutcome.locked);
    }
    final wait = _gate.blockedForMs(ip, ignoreGlobal: holdsValidToken);
    if (wait != null) {
      return JoinResult(JoinOutcome.blocked,
          retryAfterSec: (wait / 1000).ceil());
    }
    if (!constantTimeEquals(code, _code)) {
      _gate.recordFailure(ip);
      return const JoinResult(JoinOutcome.badCode);
    }
    _gate.recordSuccess(ip);

    sweep();
    // The same PC joining again (app restarted) replaces its old token -- but
    // ONLY when machine id AND address both match. machine_id alone is a claim
    // the client makes about itself: anyone could send another PC's id to evict
    // it, and cloned lab images share ids (S-004).
    final previous = _byToken.values
        .where((c) => c.machineId == machineId && c.ip == ip)
        .toList();
    if (previous.isEmpty && _byToken.length >= maxClients) {
      return const JoinResult(JoinOutcome.full);
    }
    final fromThisIp = _byToken.values
        .where((c) => c.ip == ip && !previous.contains(c))
        .length;
    if (fromThisIp >= HubLimits.maxClientsPerIp) {
      return const JoinResult(JoinOutcome.full);
    }

    final token = _newToken();
    final now = _now();
    final c = HubClient(
      id: _nextId++,
      token: token,
      machineId: machineId,
      ip: ip,
      deviceName: deviceName,
      // Generous for media bursts at test start; a flooding client still hits it.
      bucket: TokenBucket(120, 40, now),
      lastSeen: now,
    )..connectedAt = now;
    for (final old in previous) {
      c.inheritFrom(old);
      for (final rec in _conflicts) {
        if (rec.holderId == old.id) rec.holderId = c.id;
        if (rec.claimantId == old.id) rec.claimantId = c.id;
      }
      for (final r in _seatReserved.values) {
        if (r.claimantId == old.id) r.claimantId = c.id;
      }
      if (_watchedId == old.id) _watchedId = c.id;
      _remove(old);
    }
    _byToken[token] = c;
    _changed();
    return JoinResult(JoinOutcome.ok, client: c);
  }

  String _newToken() {
    final bytes =
        Uint8List.fromList(List.generate(32, (_) => _rng.nextInt(256)));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  HubClient? authenticate(String token) => _byToken[token];

  /// Rate limit per token; false = over the limit. Frames cost more.
  bool allowRequest(HubClient c, {double cost = 1}) =>
      c.bucket.take(_now(), cost);

  /// Liveness: any authenticated request proves the PC is there, so this runs
  /// BEFORE any cap or limit can turn the request away -- a flood must not make
  /// its victims look dead (S-002).
  void touch(HubClient c) {
    c.lastSeen = _now();
  }

  /// Concurrency slots: a token may hold [HubLimits.maxConcurrentPerToken]
  /// requests, an address [HubLimits.maxConcurrentPerIp]. Pair with [leave].
  bool tryEnter(HubClient c, String ip) {
    if (c.inFlight >= HubLimits.maxConcurrentPerToken) return false;
    if ((_ipInFlight[ip] ?? 0) >= HubLimits.maxConcurrentPerIp) return false;
    c.inFlight++;
    _ipInFlight[ip] = (_ipInFlight[ip] ?? 0) + 1;
    return true;
  }

  void leave(HubClient c, String ip) {
    if (c.inFlight > 0) c.inFlight--;
    final n = (_ipInFlight[ip] ?? 1) - 1;
    if (n <= 0) {
      _ipInFlight.remove(ip);
    } else {
      _ipInFlight[ip] = n;
    }
  }

  // ── result quota (per source address, kept across re-joins) ───────────────

  /// Null when [ip] may still store a result of [bytes] export-format bytes,
  /// else the stable refusal code.
  String? quotaProblem(String ip, int bytes) {
    final q = _quota[ip];
    if (q == null) return bytes > maxResultBytesPerIp ? 'client_quota' : null;
    if (q.count >= maxResultsPerIp || q.bytes + bytes > maxResultBytesPerIp) {
      return 'client_quota';
    }
    return null;
  }

  void quotaCommit(String ip, int bytes) {
    if (_quota.length > 2048) _quota.clear();
    final q = _quota.putIfAbsent(ip, _Quota.new);
    q.count++;
    q.bytes += bytes;
  }

  void _remove(HubClient c) {
    _byToken.remove(c.token);
    if (_watchedId == c.id) _watchedId = null;
    c.frame = null;
  }

  /// Forgets clients silent for [HubLimits.evictMs].
  void sweep() {
    final now = _now();
    final dead = _byToken.values
        .where((c) => now - c.lastSeen > HubLimits.evictMs)
        .toList();
    for (final c in dead) {
      _remove(c);
    }
    if (dead.isNotEmpty) _changed();
  }

  int get clientCount => _byToken.length;

  // ── roster ─────────────────────────────────────────────────────────────────

  /// The roster student a ping's `student_code` stands for: the student's UUID
  /// (engine tests), or `DIAG-offline|<student>|<group>|<lang>` (diagnostics).
  String? _rosterId(String studentCode) {
    var id = studentCode;
    if (id.startsWith('DIAG-offline|')) {
      final parts = id.split('|');
      if (parts.length == 4) id = parts[1];
    }
    return _studentsById.containsKey(id) ? id : null;
  }

  String _classNameOf(String studentId) {
    final gids = _groupsOfStudent[studentId];
    if (gids == null || gids.isEmpty) return '';
    return gids
        .map((g) => _groupNames[g] ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
  }

  // ── proctoring ─────────────────────────────────────────────────────────────

  Map<String, Object?> _reply(HubClient c, String sessionId,
      {bool conflict = false}) {
    return {
      'ok': true,
      'locked': c.locked,
      'extra_time_seconds': c.extraTimeSeconds,
      'commands': [
        if (_wantsKeyframe(c)) {'action': 'request_keyframe'},
      ],
      // Keyed by the id the CLIENT sent: a PC whose attempt was taken over or
      // already ended must still be told.
      'terminated':
          sessionId.isNotEmpty && c.terminatedSessions.contains(sessionId),
      'conflict': conflict,
      // ProctorService only sends frames once it holds a token; real auth is
      // the bearer header, so this is a plain marker.
      'proctor_token': 'lan',
      'proctor_interval_ms': _intervalMs(c),
      // 960 = "spotlight" capture profile (single-student close-up).
      'target_width': _watchedId == c.id ? 960 : 640,
    };
  }

  int _intervalMs(HubClient c) => _watchedId == c.id ? 1500 : 3000;

  bool _wantsKeyframe(HubClient c) =>
      c.inTest && (c.frame == null || _watchedId == c.id);

  /// Applies a ping and returns the reply body.
  Map<String, Object?> ping(HubClient c, PingInput p) {
    final now = _now();
    c.lastSeen = now;
    if (p.deviceName.isNotEmpty) c.deviceName = p.deviceName;
    c.name = p.name;
    c.pingStatus = p.status;
    c.capabilities = p.capabilities;

    var conflict = false;
    if (p.testKey.isNotEmpty) {
      if (c.endedSessions.contains(p.sessionId)) {
        // Late ping of an attempt that is already over: nothing to track.
      } else if (p.sessionId != c.sessionId) {
        conflict = !_claimSession(c, p, now);
      }
      if (!conflict && c.sessionId == p.sessionId) {
        c.tabSwitchCount = p.tabSwitchCount;
        c.incidentCount = p.incidentCount;
        if (p.questionIndex != null) c.questionIndex = p.questionIndex;
        if (p.totalQuestions != null) c.totalQuestions = p.totalQuestions;
        if (p.elapsedSeconds != null) {
          c.elapsedReported = p.elapsedSeconds;
          c.elapsedReportedAt = now;
        }
      }
    } else if (c.inTest) {
      // Idle (device-level) ping: the test attempt is over.
      c.endTest();
    }
    _changed();
    return _reply(c, p.sessionId, conflict: conflict);
  }

  /// First ping of a TEST attempt. False = the seat is not available: another
  /// PC already holds this student's test, or the teacher turned this PC's
  /// claim down. The newcomer gets `conflict: true` (the client's own
  /// startTest() turns that into its "another device" message) and the teacher
  /// gets a [SeatConflict] to decide. The holder is NEVER ended automatically,
  /// however long it has been silent: a hostile PC could otherwise squat a seat
  /// and, once the victim's link flickers, take it and have the victim's
  /// attempt force-submitted (S-003).
  bool _claimSession(HubClient c, PingInput p, int now) {
    final sid = _rosterId(p.studentCode);
    if (sid != null) {
      // A seat the teacher freed belongs to the claimant they chose.
      final reserved = _seatReserved[sid];
      if (reserved != null) {
        if (!_reserveActive(reserved, now)) {
          _seatReserved.remove(sid);
        } else if (reserved.claimantId != c.id) {
          return false;
        }
      }
      final until = _rejectedClaims['${c.id}|$sid'];
      if (until != null) {
        if (now < until) return false;
        _rejectedClaims.remove('${c.id}|$sid');
      }
      for (final o in _byToken.values) {
        if (identical(o, c) || !o.inTest || o.studentId != sid) continue;
        _noteConflict(c, o, sid, now);
        return false;
      }
    }
    if (sid != null) _seatReserved.remove(sid);
    c.sessionId = p.sessionId;
    c.testKey = p.testKey;
    c.studentId = sid ?? '';
    c.sessionStartedAt = now;
    // Pause/extra time belong to ONE attempt; the client resets its baseline
    // at startTest, so the hub must too.
    c.locked = false;
    c.extraTimeSeconds = 0;
    c.questionIndex = null;
    c.totalQuestions = null;
    c.elapsedReported = null;
    c.frame = null;
    c.frameVersion++;
    return true;
  }

  /// A freed seat stays reserved for its claimant for at least
  /// [HubLimits.seatReserveMs]; after that only while the claimant is still in
  /// touch, and never past [HubLimits.seatReserveMaxMs] (F-4).
  bool _reserveActive(_SeatReserve r, int now) {
    final age = now - r.since;
    if (age >= HubLimits.seatReserveMaxMs) return false;
    if (age < HubLimits.seatReserveMs) return true;
    final c = _byId(r.claimantId);
    return c != null && now - c.lastSeen <= HubLimits.noContactMs;
  }

  void _noteConflict(
      HubClient claimant, HubClient holder, String sid, int now) {
    final known = _conflicts
        .any((r) => r.claimantId == claimant.id && r.studentId == sid);
    // One report per claimant+student, and a client that was just reported
    // does not get another banner for a different student for a while.
    if (known) return;
    if (claimant.lastConflictAt != 0 &&
        now - claimant.lastConflictAt < HubLimits.claimCooldownMs) {
      return;
    }
    // One address cannot bury the honest conflicts under its own (N-3).
    var fromIp = 0;
    for (final r in _conflicts) {
      if (_byId(r.claimantId)?.ip == claimant.ip) fromIp++;
    }
    if (fromIp >= HubLimits.maxOpenConflictsPerIp) return;
    claimant.lastConflictAt = now;
    if (_conflicts.length >= 64) _conflicts.removeAt(0);
    _conflicts
        .add(_ConflictRec(_nextConflictId++, sid, holder.id, claimant.id));
  }

  /// Open seat conflicts (pruned of anything that no longer applies).
  List<SeatConflict> conflicts() {
    _conflicts.removeWhere((r) {
      final h = _byId(r.holderId);
      final c = _byId(r.claimantId);
      return h == null || c == null || !h.inTest || h.studentId != r.studentId;
    });
    final now = _now();
    SeatParty party(HubClient c) => SeatParty(
          deviceName: c.deviceName.isNotEmpty ? c.deviceName : c.name,
          ip: c.ip,
          connectedAgoMs: now - c.connectedAt < 0 ? 0 : now - c.connectedAt,
          status: _viewOf(c, now).status,
        );
    // Most trustworthy first: claimants from an address with few open claims
    // (an honest PC) before a flood from one address; newest first among equals
    // (F-3). The screen shows the first few and lets the teacher open the rest.
    final perIp = <String, int>{};
    for (final r in _conflicts) {
      final ip = _byId(r.claimantId)!.ip;
      perIp[ip] = (perIp[ip] ?? 0) + 1;
    }
    final ordered = [..._conflicts]..sort((a, b) {
        final byIp = perIp[_byId(a.claimantId)!.ip]!
            .compareTo(perIp[_byId(b.claimantId)!.ip]!);
        return byIp != 0 ? byIp : b.id.compareTo(a.id);
      });
    return [
      for (final r in ordered)
        SeatConflict(
          id: r.id,
          studentId: r.studentId,
          studentName: (_studentsById[r.studentId]?['name'] ?? '').toString(),
          className: _classNameOf(r.studentId),
          holderId: r.holderId,
          holder: party(_byId(r.holderId)!),
          claimantId: r.claimantId,
          claimant: party(_byId(r.claimantId)!),
        )
    ];
  }

  /// Turns down every open claim on [studentId]'s seat at once (a flood of
  /// claimants for one seat, F-3).
  void rejectAllClaims(String studentId) {
    for (final r
        in _conflicts.where((r) => r.studentId == studentId).toList()) {
      resolveConflict(r.id, releaseHolder: false);
    }
  }

  /// The teacher's decision. [releaseHolder]: end the holder's attempt (it is
  /// told `terminated`) so the claimant can take the seat on its next ping.
  /// Otherwise the claim is turned down and stays refused for a while.
  void resolveConflict(int id, {required bool releaseHolder}) {
    final i = _conflicts.indexWhere((r) => r.id == id);
    if (i < 0) return;
    final r = _conflicts.removeAt(i);
    if (releaseHolder) {
      final h = _byId(r.holderId);
      if (h != null && h.inTest) {
        h.terminatedSessions.add(h.sessionId);
        h.endTest();
      }
      // Only the claimant the teacher saw may take the freed seat, for a while:
      // otherwise a second token of the squatter wins the race (N-3).
      if (_seatReserved.length > 256) _seatReserved.clear();
      _seatReserved[r.studentId] = _SeatReserve(r.claimantId, _now());
    } else {
      if (_rejectedClaims.length > 256) _rejectedClaims.clear();
      _rejectedClaims['${r.claimantId}|${r.studentId}'] =
          _now() + HubLimits.rejectedClaimMs;
    }
    _changed();
  }

  /// Stores a screen frame (KEYFRAMES only: a patch is useless without the
  /// image it patches, and the hub never composites). Returns the reply body.
  Map<String, Object?> acceptFrame(
    HubClient c, {
    required String sessionId,
    required String frameType,
    required Uint8List jpeg,
    required bool focus,
    required int monitorCount,
    int? questionIndex,
    int? totalQuestions,
  }) {
    final now = _now();
    c.lastSeen = now;
    if (!c.inTest || sessionId != c.sessionId) {
      throw const HubHttpError(409, 'stale_session');
    }
    // A client may not send faster than half the interval it was told (S-007).
    if (c.lastFrameAt != 0 && now - c.lastFrameAt < _intervalMs(c) ~/ 2) {
      throw const HubHttpError(429, 'too_fast', headers: {'retry-after': '1'});
    }
    c.lastFrameAt = now;
    if (frameType == 'keyframe' || frameType.isEmpty) {
      c.frame = jpeg;
      c.frameAt = now;
      c.frameVersion++;
    }
    c.frameFocus = focus;
    c.monitorCount = monitorCount;
    if (questionIndex != null) c.questionIndex = questionIndex;
    if (totalQuestions != null) c.totalQuestions = totalQuestions;
    _changed();
    return _reply(c, sessionId);
  }

  // ── results ────────────────────────────────────────────────────────────────

  /// Why a result must be refused, or null. Mirrors the server's
  /// `student_invalid` / `test_not_in_pack` checks but is STRICTER on keys:
  /// the hub has no database, so "a key the server has never heard of" cannot
  /// be told apart from a forged one — every non-blank key must be a key of
  /// this pack.
  String? checkResult(Map<String, dynamic> payload) {
    final sid = payload['student_id'];
    if (sid is! String || !_studentsById.containsKey(sid)) {
      return 'student_invalid';
    }
    final gid = payload['group_id'];
    if (gid != null && gid != '') {
      if (gid is! String || !_studentGroupPairs.contains('$sid|$gid')) {
        return 'student_invalid';
      }
    }
    final detail = payload['detail'];
    for (final v in [
      payload['test_key'],
      if (detail is Map) detail['test_key']
    ]) {
      if (v == null || v == '') continue;
      if (v is! String ||
          v.length > 128 ||
          v.contains('\u0000') ||
          !allowedTestKeys.contains(v.trim())) {
        return 'test_not_in_pack';
      }
    }
    return null;
  }

  /// A result for [studentId] was stored: that PC's attempt is finished.
  void resultStored(HubClient c, String studentId) {
    c.resultsAccepted++;
    resultsAccepted++;
    if (c.inTest && c.studentId == studentId) c.endTest();
    _changed();
  }

  // ── teacher commands ───────────────────────────────────────────────────────

  HubClient? _byId(int id) {
    for (final c in _byToken.values) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Pause/resume (only meaningful while the PC is in a test).
  void setLocked(int id, bool locked) {
    final c = _byId(id);
    if (c == null || !c.inTest) return;
    c.locked = locked;
    _changed();
  }

  /// Adds to the running total of extra time of the current attempt.
  void addExtraTime(int id, int seconds) {
    final c = _byId(id);
    if (c == null || !c.inTest || seconds <= 0) return;
    c.extraTimeSeconds = min(c.extraTimeSeconds + seconds, 4 * 3600);
    _changed();
  }

  /// "Finish the test": the next ping makes the client auto-submit.
  void terminate(int id) {
    final c = _byId(id);
    if (c == null || !c.inTest) return;
    c.terminatedSessions.add(c.sessionId);
    _changed();
  }

  /// Revokes a client's token (it must join again with the code).
  void kick(int id) {
    final c = _byId(id);
    if (c == null) return;
    _remove(c);
    _changed();
  }

  /// Which student the teacher is looking at: that PC is asked for a keyframe
  /// on every reply (so its frame stays fresh) and a larger capture.
  void watch(int? id) {
    if (_watchedId == id) return;
    _watchedId = id;
    _changed();
  }

  int? get watchedId => _watchedId;

  Uint8List? frameOf(int id) => _byId(id)?.frame;

  // ── view ───────────────────────────────────────────────────────────────────

  List<ClientView> views() {
    final now = _now();
    final out = _byToken.values.map((c) => _viewOf(c, now)).toList();
    out.sort((a, b) {
      final x = a.name.isEmpty ? a.deviceName : a.name;
      final y = b.name.isEmpty ? b.deviceName : b.name;
      return x.toLowerCase().compareTo(y.toLowerCase());
    });
    return out;
  }

  ClientView? viewOfId(int id) {
    final c = _byId(id);
    return c == null ? null : _viewOf(c, _now());
  }

  ClientView _viewOf(HubClient c, int now) {
    final silent = now - c.lastSeen;
    final ClientStatus status;
    if (silent > HubLimits.noContactMs) {
      status = ClientStatus.noContact;
    } else if (c.locked && c.inTest) {
      status = ClientStatus.locked;
    } else if (c.inTest) {
      status = c.pingStatus == 'finished'
          ? ClientStatus.inactive
          : ClientStatus.testing;
    } else {
      status = ClientStatus.waiting;
    }

    int? remaining;
    if (c.inTest) {
      final minutes = _durations[c.testKey];
      if (minutes != null) {
        // `elapsed_seconds` only rides along with answers, so extrapolate from
        // the last report (or the attempt start); paused PCs do not advance.
        final base = c.elapsedReported ?? 0;
        final since = c.elapsedReported != null
            ? c.elapsedReportedAt
            : c.sessionStartedAt;
        final extra = c.locked ? 0 : ((now - since) / 1000).floor();
        final elapsed = base + (extra < 0 ? 0 : extra);
        remaining = max(0, minutes * 60 + c.extraTimeSeconds - elapsed);
      }
    }

    final qi = c.questionIndex;
    final total = c.totalQuestions;
    return ClientView(
      id: c.id,
      name: c.name,
      className: _classNameOf(c.studentId),
      status: status,
      questionNumber: (qi != null && total != null && total > 0)
          ? min(qi + 1, total)
          : null,
      totalQuestions: total,
      remainingSeconds: remaining,
      tabSwitchCount: c.tabSwitchCount,
      incidentCount: c.incidentCount,
      lastSeenAgoMs: silent < 0 ? 0 : silent,
      ip: c.ip,
      deviceName: c.deviceName,
      hasFrame: c.frame != null,
      frameVersion: c.frameVersion,
      locked: c.locked,
      extraTimeSeconds: c.extraTimeSeconds,
      resultsAccepted: c.resultsAccepted,
      inTest: c.inTest,
    );
  }

  // ── change notification (coalesced: frames arrive every few seconds ×60) ───

  void _changed() {
    if (_disposed || _notifyTimer != null) return;
    _notifyTimer = Timer(const Duration(milliseconds: 400), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
  }

  /// Drops every token and frame. The hub calls this when it stops.
  void clear() {
    for (final c in _byToken.values) {
      c.frame = null;
    }
    _byToken.clear();
    _watchedId = null;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    clear();
    super.dispose();
  }
}
