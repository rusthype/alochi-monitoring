// lib/core/local_server/shelf_hub.dart
//
// The teacher PC's LAN hub (phase 3): a `shelf` HTTP server that serves the
// OPEN offline pack to student PCs, collects their results into the pack's
// HMAC chain, and relays proctoring state/commands.
//
// Plain HTTP, no TLS — an accepted limitation for an isolated classroom LAN
// (see docs/offline_lan_hub.md): the class code and bearer tokens are visible
// to anyone who can sniff that network segment. Everything sensitive is kept
// OFF the wire or OFF disk instead:
//   * the pack PIN never leaves ShelfHub's process (clients never need it);
//   * the HMAC chain key lives only in the open OfflinePackSession;
//   * tokens and screen frames live in memory only (HubState).
//
// Endpoints (JSON unless noted; everything except /health and /join needs
// `Authorization: Bearer <token>`):
//   GET  /health                      -> {ok}
//   POST /join     {code,machine_id,device_name?}        -> {token, ...}
//   POST /keepalive                   -> {ok}   (liveness, every few seconds)
//   POST /ping     (sessionPing shape)                    -> locked/extra/...
//   POST /frame?session_id=..&frame_type=..  body=JPEG    -> same reply shape
//   POST /result   Idempotency-Key + {payload,incidents,clock_flags} -> {ok}
//   GET  /groups | /students?group_id= | /catalog?group_id= | /test?key=
//   GET  /packages | /package_questions?id=&variant=
//   GET  /media/<sha256>.<ext>
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../db/pack_results_db.dart';
import '../offline/asset_test_keys.dart';
import '../offline/export_format.dart';
import '../offline/offline_package_api.dart';
import '../offline/offline_session.dart';
import '../security/monitored_clock.dart';
import 'hub_guard.dart';
import 'hub_state.dart';
import 'lan_discovery.dart';

enum HubStartError { notActive, portUnavailable }

class HubStartException implements Exception {
  final HubStartError code;
  const HubStartException(this.code);
  @override
  String toString() => 'HubStartException(${code.name})';
}

const int kHubFirstPort = 8080;
const int kHubLastPort = 8090;

class ShelfHub extends ChangeNotifier {
  /// The app-wide hub (so the monitoring screen can be left and re-entered
  /// while the server keeps running). Null until first started.
  static ShelfHub? current;

  final OfflinePackSession session;
  final InternetAddress bindAddress;
  final int firstPort;
  final int lastPort;
  final String hubName;
  final MonitoredClock clock;

  /// Chain budget and result quota (defaults: HubLimits; tests lower them).
  final int maxPackEntries;
  final int maxPackPlainBytes;
  final int maxResultsPerIp;
  final int maxResultBytesPerIp;
  final int? _maxResultsPerStudent;
  final int maxResultBytesPerStudent;
  final int reservePerStudent;

  /// Overrides the UDP announcer (tests aim it at loopback).
  final LanBroadcaster Function(String name, int port, String packLabel)?
      broadcasterFactory;

  ShelfHub(
    this.session, {
    InternetAddress? bindAddress,
    this.firstPort = kHubFirstPort,
    this.lastPort = kHubLastPort,
    String? hubName,
    MonitoredClock? clock,
    this.broadcasterFactory,
    this.maxPackEntries = HubLimits.maxPackEntries,
    this.maxPackPlainBytes = HubLimits.maxPackPlainBytes,
    this.maxResultsPerIp = HubLimits.maxResultsPerIp,
    this.maxResultBytesPerIp = HubLimits.maxResultBytesPerIp,
    int? maxResultsPerStudent,
    this.maxResultBytesPerStudent = HubLimits.maxResultBytesPerStudent,
    this.reservePerStudent = HubLimits.reservePerStudent,
  })  : _maxResultsPerStudent = maxResultsPerStudent,
        bindAddress = bindAddress ?? InternetAddress.anyIPv4,
        hubName = hubName ?? _hostName(),
        clock = clock ?? MonitoredClock.instance;

  static String _hostName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'teacher-pc';
    }
  }

  HttpServer? _server;
  HubState? _state;
  LanBroadcaster? _broadcaster;
  OfflinePackOwnerListener? _packListener;
  late OfflinePackageApi _api;
  final Map<String, Uint8List> _testJson = {};
  Uint8List? _diagnosticsJson;
  final Map<String, TokenBucket> _ipBuckets = {};
  int _inFlight = 0;
  final Map<String, int> _joinInFlight = {};

  /// Results one roster student may have in the pack: at least
  /// [HubLimits.maxResultsPerStudent], and twice the number of tests the pack
  /// carries (every diagnostic subject is a result of its own, plus retakes), so
  /// an honest student never meets it (F-2).
  int get resultsPerStudentCap =>
      _maxResultsPerStudent ??
      (2 * session.pack.tests.length > HubLimits.maxResultsPerStudent
          ? 2 * session.pack.tests.length
          : HubLimits.maxResultsPerStudent);

  bool get running => _server != null;
  HubState? get state => _state;

  /// The port actually bound (null when stopped).
  int? get port => _server?.port;

  /// True when [firstPort] was busy and a later one was used — the UI says so.
  bool get portWasFallback => port != null && port != firstPort;

  int _now() => clock.ticksMs;

  // ── lifecycle ──────────────────────────────────────────────────────────────

  Future<void> start({bool announce = true}) async {
    if (running) return;
    // The hub only exists on top of an OPEN, unlocked pack.
    if (!identical(OfflinePackSession.current, session)) {
      throw const HubStartException(HubStartError.notActive);
    }
    final pack = session.pack;

    _api = OfflinePackageApi(session);
    _testJson.clear();
    _diagnosticsJson = null;
    _ipBuckets.clear();
    // "Check budget -> append -> account" is one critical section (the
    // session's chainLock): parallel results must not each see room that only
    // one of them can have (S-001). The cached size is re-measured per run.
    session.chainUsage = null;

    final durations = <String, int>{};
    for (final t in pack.tests) {
      if (t['type'] != 'test') continue;
      final data = t['data'];
      final cat = t['catalog'];
      final m = (data is Map ? data['duration_minutes'] : null) ??
          (cat is Map ? cat['duration_minutes'] : null);
      if (m is num && m > 0) durations[t['key']?.toString() ?? ''] = m.toInt();
    }

    _state?.dispose();
    final st = HubState(
      packUuid: pack.packUuid,
      schoolId: pack.schoolId,
      schoolCode: pack.schoolCode,
      hubName: hubName,
      groups: pack.groups,
      students: pack.students,
      // The pack's own keys, plus the closed list of built-in runner keys
      // (asset_test_keys.dart). Anything else stays refused.
      allowedTestKeys: [
        for (final t in pack.tests)
          if ((t['key']?.toString() ?? '').isNotEmpty) t['key'].toString(),
        ...kAssetTestKeys,
      ],
      testDurationsMinutes: durations,
      ticks: _now,
      maxResultsPerIp: maxResultsPerIp,
      maxResultBytesPerIp: maxResultBytesPerIp,
    )..addListener(notifyListeners);
    _state = st;

    final handler =
        const Pipeline().addMiddleware(_guard).addHandler(_router().call);

    HttpServer? server;
    for (var prt = firstPort; prt <= lastPort; prt++) {
      try {
        server = await shelf_io.serve(handler, bindAddress, prt, shared: false);
        break;
      } on SocketException {
        continue; // taken: try the next one
      }
    }
    if (server == null) {
      st.dispose();
      _state = null;
      throw const HubStartException(HubStartError.portUnavailable);
    }
    server.idleTimeout = const Duration(seconds: 15);
    server.autoCompress = false;
    server.serverHeader = null; // no server/version banner
    _server = server;

    if (announce) {
      final label = pack.schoolCode;
      final b = broadcasterFactory?.call(hubName, server.port, label) ??
          LanBroadcaster(name: hubName, port: server.port, packLabel: label);
      _broadcaster = b;
      unawaited(b.start().catchError((Object e) {
        debugPrint('ShelfHub: announce failed (${e.runtimeType})');
      }));
    }

    // Closing the pack closes the hub (frames and tokens go with it).
    _packListener = OfflinePackOwnerListener(session, () => unawaited(stop()));
    ShelfHub.current = this;
    debugPrint('ShelfHub: listening on port ${server.port}');
    notifyListeners();
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    _packListener?.dispose();
    _packListener = null;
    final b = _broadcaster;
    _broadcaster = null;
    await b?.stop();
    _state?.clear(); // tokens + frames are gone before the socket closes
    _testJson.clear();
    _diagnosticsJson = null;
    _ipBuckets.clear();
    await server.close(force: true);
    debugPrint('ShelfHub: stopped');
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    _state?.dispose();
    _state = null;
    if (identical(current, this)) current = null;
    super.dispose();
  }

  // ── middleware / helpers ───────────────────────────────────────────────────

  Middleware get _guard => (Handler inner) => (Request req) async {
        try {
          return await inner(req);
        } on HubHttpError catch (e) {
          return _json(e.status, {'error': e.code, ...e.extra},
              headers: e.headers);
        } catch (e) {
          // Never echo anything about the failure to the peer.
          debugPrint('ShelfHub: request failed (${e.runtimeType})');
          return _json(500, {'error': 'internal'});
        }
      };

  static const Map<String, String> _baseHeaders = {
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  };

  static Response _json(int status, Object? body,
          {Map<String, String> headers = const {}}) =>
      Response(status, body: jsonEncode(body), headers: {
        ..._baseHeaders,
        'content-type': 'application/json; charset=utf-8',
        ...headers,
      });

  static Response _jsonBytes(Uint8List bytes) => Response.ok(bytes, headers: {
        ..._baseHeaders,
        'content-type': 'application/json; charset=utf-8',
      });

  static String _ipOf(Request r) {
    final info = r.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
  }

  /// Per-IP bucket for requests that are not (yet) authenticated.
  TokenBucket _bucketFor(String ip) {
    if (_ipBuckets.length > 2048) _ipBuckets.clear();
    return _ipBuckets.putIfAbsent(ip, () => TokenBucket(30, 1, _now()));
  }

  /// Reads at most [limit] bytes. A missing or oversized Content-Length is
  /// refused up front; the whole read has a deadline (slow-body protection).
  Future<Uint8List> _readBody(Request req, int limit, Duration timeout) {
    final len = req.contentLength;
    if (len == null) throw const HubHttpError(411, 'length_required');
    if (len > limit) throw const HubHttpError(413, 'too_large');
    final out = BytesBuilder(copy: false);
    final done = Completer<Uint8List>();
    var total = 0;
    late final StreamSubscription<List<int>> sub;
    final timer = Timer(timeout, () {
      sub.cancel();
      if (!done.isCompleted) {
        done.completeError(const HubHttpError(408, 'timeout'));
      }
    });
    sub = req.read().listen((chunk) {
      total += chunk.length;
      if (total > limit) {
        sub.cancel();
        timer.cancel();
        if (!done.isCompleted) {
          done.completeError(const HubHttpError(413, 'too_large'));
        }
        return;
      }
      out.add(chunk);
    }, onDone: () {
      timer.cancel();
      if (!done.isCompleted) done.complete(out.takeBytes());
    }, onError: (Object _) {
      timer.cancel();
      if (!done.isCompleted) {
        done.completeError(const HubHttpError(400, 'bad_request'));
      }
    }, cancelOnError: true);
    return done.future;
  }

  Future<Map<String, dynamic>> _readJsonMap(
      Request req, int limit, Duration timeout) async {
    final decoded = decodeJsonBounded(await _readBody(req, limit, timeout));
    if (decoded is! Map) throw const HubHttpError(400, 'bad_request');
    return Map<String, dynamic>.from(decoded);
  }

  /// Resolves the bearer token to its client, or refuses the request. A valid
  /// token marks the PC alive FIRST, before any limit can turn the request
  /// away (S-002).
  HubClient _authenticate(Request req) {
    final st = _state;
    if (st == null) throw const HubHttpError(503, 'busy');
    final header = req.headers['authorization'];
    HubClient? client;
    if (header != null &&
        header.length <= 128 &&
        header.startsWith('Bearer ')) {
      client = st.authenticate(header.substring(7).trim());
    }
    if (client == null) {
      // Unknown/forged tokens cost the sender its per-IP allowance.
      if (!_bucketFor(_ipOf(req)).take(_now())) {
        throw const HubHttpError(429, 'rate_limited',
            headers: {'retry-after': '1'});
      }
      throw const HubHttpError(401, 'unauthorized');
    }
    st.touch(client);
    if (!st.allowRequest(client)) {
      throw const HubHttpError(429, 'rate_limited',
          headers: {'retry-after': '1'});
    }
    return client;
  }

  /// Authenticated handler with concurrency limits: a token holds at most
  /// [HubLimits.maxConcurrentPerToken] requests and an address
  /// [HubLimits.maxConcurrentPerIp]; everything except [reserved] endpoints
  /// (tiny liveness traffic) also counts against the global [HubLimits.maxInFlight].
  Handler _auth(FutureOr<Response> Function(Request, HubClient) handler,
      {bool reserved = false}) {
    return (Request req) async {
      final c = _authenticate(req);
      final st = _state!;
      final ip = _ipOf(req);
      if (!st.tryEnter(c, ip)) {
        throw const HubHttpError(429, 'too_many_requests',
            headers: {'retry-after': '1'});
      }
      var counted = false;
      try {
        if (!reserved) {
          if (_inFlight >= HubLimits.maxInFlight) {
            throw const HubHttpError(503, 'busy');
          }
          _inFlight++;
          counted = true;
        }
        return await handler(req, c);
      } finally {
        st.leave(c, ip);
        if (counted) _inFlight--;
      }
    };
  }

  /// Counts the results this hub turns away (any refusal of a /result that
  /// carries a valid idempotency key, whatever the reason) for the teacher's
  /// screen; a key leaves the count once it is stored.
  Handler _countRefusals(Handler inner) => (Request req) async {
        final key = req.headers['idempotency-key'] ?? '';
        try {
          final resp = await inner(req);
          if (resp.statusCode == 200) _state?.noteResultStored(key);
          return resp;
        } on HubHttpError catch (e) {
          if (_idemRe.hasMatch(key) &&
              (e.status == 401 ||
                  e.status == 403 ||
                  e.status == 409 ||
                  e.status == 422 ||
                  e.status == 507)) {
            _state?.noteResultRefused(key);
          }
          rethrow;
        }
      };

  Router _router() {
    return Router()
      ..get('/health', (Request _) => _json(200, {'ok': true}))
      ..post('/join', _join)
      ..post('/keepalive', _auth(_keepalive, reserved: true))
      ..post('/leave', _auth(_leave, reserved: true))
      ..post('/ping', _auth(_ping, reserved: true))
      ..post('/frame', _auth(_frame))
      ..post('/result', _countRefusals(_auth(_result)))
      ..get('/groups', _auth(_groups))
      ..get('/students', _auth(_students))
      ..get('/catalog', _auth(_catalog))
      ..get('/test', _auth(_test))
      ..get('/diagnostics', _auth(_diagnostics))
      ..get('/packages', _auth(_packages))
      ..get('/package_questions', _auth(_packageQuestions))
      ..get('/media/<name>',
          (Request r, String name) => _auth((r, _) => _media(r, name))(r));
  }

  // ── join / liveness ────────────────────────────────────────────────────────

  static final RegExp _machineIdRe = RegExp(r'^[\x21-\x7e]{1,128}$');

  Future<Response> _join(Request req) async {
    final st = _state;
    if (st == null) throw const HubHttpError(503, 'busy');
    final ip = _ipOf(req);
    if (!_bucketFor(ip).take(_now())) {
      throw const HubHttpError(429, 'rate_limited',
          headers: {'retry-after': '2'});
    }
    // Slow-body joiners hold a slot for at most the (short) body deadline, and
    // one address can hold only a few.
    if ((_joinInFlight[ip] ?? 0) >= HubLimits.maxConcurrentJoinPerIp ||
        _inFlight >= HubLimits.maxInFlight) {
      throw const HubHttpError(503, 'busy');
    }
    _joinInFlight[ip] = (_joinInFlight[ip] ?? 0) + 1;
    _inFlight++;
    try {
      return await _joinInner(req, st, ip);
    } finally {
      _inFlight--;
      final n = (_joinInFlight[ip] ?? 1) - 1;
      if (n <= 0) {
        _joinInFlight.remove(ip);
      } else {
        _joinInFlight[ip] = n;
      }
    }
  }

  Future<Response> _joinInner(Request req, HubState st, String ip) async {
    final body =
        await _readJsonMap(req, HubLimits.joinBody, HubLimits.smallBodyTimeout);
    final code = body['code'];
    final machine = body['machine_id'];
    if (code is! String || code.length > 16) {
      throw const HubHttpError(400, 'bad_request');
    }
    if (machine is! String || !_machineIdRe.hasMatch(machine)) {
      throw const HubHttpError(400, 'bad_request');
    }
    final dn = body['device_name'];
    final deviceName = dn is String ? cleanDisplayText(dn) : '';

    // A PC that still holds a live token of this very machine is refreshing.
    final header = req.headers['authorization'];
    final held =
        (header != null && header.length <= 128 && header.startsWith('Bearer '))
            ? st.authenticate(header.substring(7).trim())
            : null;

    final r = st.join(
      ip: ip,
      code: code,
      machineId: machine,
      deviceName:
          deviceName.length > 64 ? deviceName.substring(0, 64) : deviceName,
      holdsValidToken: held != null && held.machineId == machine,
    );
    switch (r.outcome) {
      case JoinOutcome.badCode:
        throw const HubHttpError(401, 'bad_code');
      case JoinOutcome.blocked:
        throw HubHttpError(429, 'too_many_attempts',
            extra: {'retry_after': r.retryAfterSec},
            headers: {'retry-after': '${r.retryAfterSec}'});
      case JoinOutcome.full:
        throw const HubHttpError(503, 'hub_full');
      case JoinOutcome.locked:
        throw const HubHttpError(403, 'joins_locked');
      case JoinOutcome.ok:
        final pack = session.pack;
        return _json(200, {
          'token': r.client!.token,
          'hub_name': hubName,
          'pack_uuid': pack.packUuid,
          'school_id': pack.schoolId,
          'school_code': pack.schoolCode,
          'proctor_interval_ms': 3000,
        });
    }
  }

  Response _keepalive(Request req, HubClient c) {
    // Body (if any) is not read; Content-Length is still required and capped.
    final len = req.contentLength;
    if (len == null) throw const HubHttpError(411, 'length_required');
    if (len > HubLimits.keepaliveBody) {
      throw const HubHttpError(413, 'too_large');
    }
    return _json(200, {'ok': true}); // liveness was recorded on authentication
  }

  /// A PC leaves politely (disconnect / cancelled confirmation).
  Response _leave(Request req, HubClient c) {
    _state?.kick(c.id);
    return _json(200, {'ok': true});
  }

  // ── proctoring ─────────────────────────────────────────────────────────────

  Future<Response> _ping(Request req, HubClient c) async {
    final body =
        await _readJsonMap(req, HubLimits.pingBody, HubLimits.smallBodyTimeout);
    final input = PingInput.fromJson(body);
    return _json(200, _state!.ping(c, input));
  }

  static final RegExp _frameTypeRe = RegExp(r'^(keyframe|patch)$');

  static bool _frameTooLarge(int w, int h) =>
      w > HubLimits.maxFrameSide ||
      h > HubLimits.maxFrameSide ||
      w * h > HubLimits.maxFramePixels;

  int? _qInt(Map<String, String> q, String k, int min, int max) {
    final v = q[k];
    if (v == null || v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null || n < min || n > max) {
      throw const HubHttpError(400, 'bad_request');
    }
    return n;
  }

  Future<Response> _frame(Request req, HubClient c) async {
    final st = _state!;
    final q = req.url.queryParameters;
    final sessionId = q['session_id'] ?? '';
    if (sessionId.isEmpty || sessionId.length > 64) {
      throw const HubHttpError(400, 'bad_request');
    }
    final frameType = q['frame_type'] ?? 'keyframe';
    if (!_frameTypeRe.hasMatch(frameType)) {
      throw const HubHttpError(400, 'bad_request');
    }
    final focus = q['focus'] == 'true';
    final monitors = _qInt(q, 'monitor_count', 0, 32) ?? 1;
    final qIdx = _qInt(q, 'q_idx', 0, 100000);
    final total = _qInt(q, 'total', 0, 100000);

    // A frame is expensive (up to 512 KB to read, keep and later decode): it
    // costs several tokens (one was taken on authentication). S-007
    if (!st.allowRequest(c, cost: HubLimits.frameCost - 1)) {
      throw const HubHttpError(429, 'rate_limited',
          headers: {'retry-after': '1'});
    }
    final bytes =
        await _readBody(req, HubLimits.frameBody, HubLimits.frameBodyTimeout);
    // Only a real, small JPEG is ever stored or shown. A few hundred KB can
    // declare 10000x10000 pixels and cost hundreds of MB to decode on the
    // teacher's screen (S-006), so the size is checked WITHOUT decoding -- by
    // the same codec that would decode it (N-1: a hand-written header walker
    // alone is fooled by a second, fake SOF), then by the cheap walker too.
    if (bytes.length < 4 ||
        bytes[0] != 0xFF ||
        bytes[1] != 0xD8 ||
        bytes[2] != 0xFF) {
      throw const HubHttpError(400, 'bad_frame');
    }
    final header = jpegSize(bytes);
    if (header != null && _frameTooLarge(header.width, header.height)) {
      throw const HubHttpError(422, 'frame_too_large');
    }
    final codec = await codecFrameSize(bytes);
    if (codec == null || codec.width < 1 || codec.height < 1) {
      throw const HubHttpError(400, 'bad_frame');
    }
    if (_frameTooLarge(codec.width, codec.height)) {
      throw const HubHttpError(422, 'frame_too_large');
    }
    if (header == null || header.width < 1 || header.height < 1) {
      throw const HubHttpError(400, 'bad_frame');
    }
    return _json(
        200,
        st.acceptFrame(c,
            sessionId: sessionId,
            frameType: frameType,
            jpeg: bytes,
            focus: focus,
            monitorCount: monitors,
            questionIndex: qIdx,
            totalQuestions: total));
  }

  // ── results ────────────────────────────────────────────────────────────────

  static final RegExp _idemRe = RegExp(r'^[A-Za-z0-9:_.\-]{1,64}$');

  Future<Response> _result(Request req, HubClient c) async {
    final key = req.headers['idempotency-key'] ?? '';
    if (!_idemRe.hasMatch(key)) throw const HubHttpError(400, 'bad_request');

    final body = await _readJsonMap(
        req, HubLimits.resultBody, HubLimits.resultBodyTimeout);
    final payload = body['payload'];
    if (payload is! Map) throw const HubHttpError(400, 'bad_request');
    final payloadMap = Map<String, dynamic>.from(payload);

    final st = _state!;
    final reason = st.checkResult(payloadMap);
    if (reason != null) {
      throw HubHttpError(422, 'rejected', extra: {'reason': reason});
    }

    final incidents = sanitizeMetaList(body['incidents'],
        maxItems: HubLimits.maxClientIncidents,
        overflowType: 'incident_overflow');
    final flags = sanitizeMetaList(body['clock_flags'],
        maxItems: HubLimits.maxClientClockFlags,
        overflowType: 'clock_flags_overflow');
    final payloadJson = jsonEncode(payloadMap);
    final ip = _ipOf(req);
    final uuid = session.pack.packUuid;

    // Check -> append -> account is ONE critical section.
    return session.chainLock.run(() async {
      try {
        // A repeat of an already stored result is acknowledged again -- but
        // only if it IS the same result; a different body under the same key is
        // a client bug or an attack, never silently "acked" (S-011).
        final existing = await PackResultsDb.payloadOf(uuid, key);
        if (existing != null) {
          if (existing != payloadJson) {
            throw const HubHttpError(409, 'idempotency_conflict');
          }
          return _json(200, {'ok': true});
        }

        // The chain budget is kept in the unit the server enforces: bytes of
        // the DECRYPTED export JSON, measured by the exporter's own helpers.
        final usage =
            session.chainUsage ??= await PackResultsDb.chainUsage(uuid);

        // (No awaits from here to the append: the clock flags peeked for the
        // size are the ones drained for the entry.)
        final entryIncidents = [
          ...incidents,
          // Which PC the result came from (informational, authenticated by
          // the chain like every meta field).
          {'type': 'lan_client', 'machine_id': c.machineId},
        ];
        final hubFlags = clock.pendingFlags;
        final metaJson = PackResultsDb.metaJsonFor(
            key, entryIncidents, [...flags, ...hubFlags]);
        final entryBytes = exportEntryBytes(payloadJson, metaJson);
        final studentId = payloadMap['student_id'] as String;

        final quota = st.quotaProblem(ip, entryBytes);
        if (quota != null) throw HubHttpError(403, quota);
        final mine = usage.perStudent[studentId];
        if ((mine?.count ?? 0) >= resultsPerStudentCap ||
            (mine?.bytes ?? 0) + entryBytes > maxResultBytesPerStudent) {
          throw const HubHttpError(403, 'student_quota');
        }
        if (usage.count + 1 > maxPackEntries ||
            usage.bytes + entryBytes + _reserveFor(usage, st, studentId) >
                maxPackPlainBytes) {
          throw const HubHttpError(507, 'pack_full');
        }

        await PackResultsDb.append(
          packUuid: uuid,
          chainKey: session.pack.chainKey,
          idempotencyKey: key,
          payloadJson: payloadJson,
          incidents: entryIncidents,
          // The hub's own clock flags ride along: the hub stamps the chain.
          clockFlags: [...flags, ...clock.drainFlags()],
        );
        usage.add(studentId, entryBytes);
        st.quotaCommit(ip, entryBytes);
        st.resultStored(c, studentId);
        return _json(200, {'ok': true});
      } on HubHttpError {
        rethrow;
      } catch (_) {
        // Unknown outcome of the write: re-measure from the database next time.
        session.chainUsage = null;
        rethrow;
      }
    });
  }

  /// Room held back for roster students who have no result yet, so a hostile
  /// PC cannot fill the pack before the honest ones are done (N-2). The
  /// student whose result this is does not count against itself, and the
  /// reserve never exceeds half the budget (a huge roster must not make the
  /// hub refuse everything).
  int _reserveFor(ChainUsage usage, HubState st, String studentId) {
    final own = usage.perStudent.containsKey(studentId) ? 0 : 1;
    // Only students who have NOT delivered yet are waited for, and never more
    // than can be in the room at once: on a 250-student roster the reserve
    // must shrink as the class hands in, not stay pinned at its cap (F-1).
    final expected = st.rosterSize < HubLimits.maxClients
        ? st.rosterSize
        : HubLimits.maxClients;
    final waiting = expected - usage.studentsWithResults - own;
    if (waiting <= 0) return 0;
    final reserve = waiting * reservePerStudent;
    final cap = maxPackPlainBytes ~/ 2;
    return reserve > cap ? cap : reserve;
  }

  // ── content ────────────────────────────────────────────────────────────────

  Future<Response> _groups(Request req, HubClient c) async =>
      _json(200, await _api.fetchGroups(session.pack.schoolCode));

  Future<Response> _students(Request req, HubClient c) async {
    final gid = req.url.queryParameters['group_id'] ?? '';
    if (gid.isEmpty || gid.length > 64) {
      throw const HubHttpError(400, 'bad_request');
    }
    return _json(200, await _api.fetchStudents(gid));
  }

  Future<Response> _catalog(Request req, HubClient c) async {
    final gid = req.url.queryParameters['group_id'];
    return _json(200, await _api.fetchTestCatalog(groupId: gid));
  }

  Future<Response> _test(Request req, HubClient c) async {
    final key = req.url.queryParameters['key'] ?? '';
    if (key.isEmpty || key.length > 128) {
      throw const HubHttpError(400, 'bad_request');
    }
    final cached = _testJson[key];
    if (cached != null) return _jsonBytes(cached);
    final data = await _api.fetchTest(key);
    if (data == null) throw const HubHttpError(404, 'not_found');
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    _testJson[key] = bytes;
    return _jsonBytes(bytes);
  }

  /// Roster + diagnostic questions in one document: the diagnostic adapter
  /// works on a synchronous snapshot (see LanDiagnosticKioskApi).
  Response _diagnostics(Request req, HubClient c) {
    return _jsonBytes(
        _diagnosticsJson ??= Uint8List.fromList(utf8.encode(jsonEncode({
      'groups': session.pack.groups,
      'students': session.pack.students,
      'tests': [
        for (final t in session.testsOfType('diagnostic'))
          {'key': t['key'], 'data': t['data']}
      ],
    }))));
  }

  Response _packages(Request req, HubClient c) =>
      _json(200, _api.packageCatalog());

  Response _packageQuestions(Request req, HubClient c) {
    final q = req.url.queryParameters;
    final id = q['id'] ?? '';
    final variant = int.tryParse(q['variant'] ?? '');
    if (id.isEmpty || id.length > 96 || variant == null || variant < 0) {
      throw const HubHttpError(400, 'bad_request');
    }
    final t = session.testByKey('package:$id:v$variant');
    final data = t?['data'];
    final qs = data is Map ? data['questions'] : null;
    if (qs is! List) throw const HubHttpError(404, 'not_found');
    return _json(200, {'questions': qs});
  }

  // Same shape as the pack's own references (offline_media.dart) + svg.
  static final RegExp _mediaNameRe =
      RegExp(r'^[0-9a-f]{64}\.(jpg|jpeg|png|gif|webp|svg)$');
  static const Map<String, String> _mime = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'svg': 'image/svg+xml',
  };

  Future<Response> _media(Request req, String name) async {
    // Whitelist the WHOLE name: no separators, no dots but the extension's, so
    // the path cannot leave the media directory.
    if (!_mediaNameRe.hasMatch(name)) {
      throw const HubHttpError(404, 'not_found');
    }
    final file = File(p.join(session.mediaDir.path, name));
    if (!await file.exists()) throw const HubHttpError(404, 'not_found');
    final len = await file.length();
    if (len > HubLimits.maxMediaFile) {
      throw const HubHttpError(404, 'not_found');
    }
    final ext = name.substring(name.lastIndexOf('.') + 1);
    return Response.ok(file.openRead(), headers: {
      ..._baseHeaders,
      'content-type': _mime[ext] ?? 'application/octet-stream',
      'content-length': '$len',
    });
  }

  /// This machine's LAN IPv4 addresses, for the teacher to read out.
  Future<List<String>> localAddresses() async =>
      [for (final a in await localIPv4Addresses()) a.address];
}

/// Calls [onClosed] once [session] stops being the open pack session.
class OfflinePackOwnerListener {
  final OfflinePackSession session;
  final VoidCallback onClosed;
  late final VoidCallback _l;

  OfflinePackOwnerListener(this.session, this.onClosed) {
    _l = () {
      if (!identical(OfflinePackSession.notifier.value, session)) onClosed();
    };
    OfflinePackSession.notifier.addListener(_l);
  }

  void dispose() => OfflinePackSession.notifier.removeListener(_l);
}
