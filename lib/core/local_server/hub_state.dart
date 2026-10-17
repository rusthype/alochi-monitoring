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

enum JoinOutcome { ok, badCode, blocked, full }

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
    final cleaned = String.fromCharCodes(v.codeUnits.where((c) => c >= 0x20));
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

class HubState extends ChangeNotifier {
  final String packUuid;
  final String schoolId;
  final String schoolCode;
  final String hubName;
  final int maxClients;
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

  // ── class code ─────────────────────────────────────────────────────────────

  String get code => _code;

  String _newCode() => _rng.nextInt(1000000).toString().padLeft(6, '0');

  /// New code for FUTURE joins; tokens already issued keep working.
  void rotateCode() {
    _code = _newCode();
    _changed();
  }

  // ── join / auth ────────────────────────────────────────────────────────────

  JoinResult join({
    required String ip,
    required String code,
    required String machineId,
    required String deviceName,
  }) {
    final wait = _gate.blockedForMs(ip);
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
    // The same PC joining again (app restarted) replaces its old token.
    final previous =
        _byToken.values.where((c) => c.machineId == machineId).toList();
    if (previous.isEmpty && _byToken.length >= maxClients) {
      return const JoinResult(JoinOutcome.full);
    }
    for (final c in previous) {
      _remove(c);
    }
    final fromThisIp = _byToken.values.where((c) => c.ip == ip).length;
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
    );
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

  /// Rate limit per token; false = over the limit.
  bool allowRequest(HubClient c) => c.bucket.take(_now());

  void touch(HubClient c) {
    c.lastSeen = _now();
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
      'proctor_interval_ms': _watchedId == c.id ? 1500 : 3000,
      // 960 = "spotlight" capture profile (single-student close-up).
      'target_width': _watchedId == c.id ? 960 : 640,
    };
  }

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

  /// First ping of a TEST attempt. False = another live PC already holds this
  /// student's test (decision 7): the newcomer is refused with `conflict`, and
  /// the client's own startTest() turns that into its "another device" message.
  /// A holder that has gone silent is taken over instead — its attempt is
  /// terminated so it cannot go on submitting.
  bool _claimSession(HubClient c, PingInput p, int now) {
    final sid = _rosterId(p.studentCode);
    if (sid != null) {
      for (final o in _byToken.values) {
        if (identical(o, c) || !o.inTest || o.studentId != sid) continue;
        if (now - o.lastSeen < HubLimits.noContactMs) return false;
        o.terminatedSessions.add(o.sessionId);
        o.endTest();
      }
    }
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
