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
  })  : bindAddress = bindAddress ?? InternetAddress.anyIPv4,
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
      allowedTestKeys: [
        for (final t in pack.tests)
          if ((t['key']?.toString() ?? '').isNotEmpty) t['key'].toString()
      ],
      testDurationsMinutes: durations,
      ticks: _now,
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
        if (_inFlight >= HubLimits.maxInFlight) {
          return _json(503, {'error': 'busy'});
        }
        _inFlight++;
        try {
          return await inner(req);
        } on HubHttpError catch (e) {
          return _json(e.status, {'error': e.code, ...e.extra},
              headers: e.headers);
        } catch (e) {
          // Never echo anything about the failure to the peer.
          debugPrint('ShelfHub: request failed (${e.runtimeType})');
          return _json(500, {'error': 'internal'});
        } finally {
          _inFlight--;
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
  Future<Uint8List> _readBody(Request req, int limit) {
    final len = req.contentLength;
    if (len == null) throw const HubHttpError(411, 'length_required');
    if (len > limit) throw const HubHttpError(413, 'too_large');
    final out = BytesBuilder(copy: false);
    final done = Completer<Uint8List>();
    var total = 0;
    late final StreamSubscription<List<int>> sub;
    final timer = Timer(HubLimits.bodyTimeout, () {
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

  Future<Map<String, dynamic>> _readJsonMap(Request req, int limit) async {
    final decoded = decodeJsonBounded(await _readBody(req, limit));
    if (decoded is! Map) throw const HubHttpError(400, 'bad_request');
    return Map<String, dynamic>.from(decoded);
  }

  /// Resolves the bearer token to its client, or refuses the request.
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
    if (!st.allowRequest(client)) {
      throw const HubHttpError(429, 'rate_limited',
          headers: {'retry-after': '1'});
    }
    return client;
  }

  Handler _auth(FutureOr<Response> Function(Request, HubClient) handler) =>
      (Request req) => handler(req, _authenticate(req));

  Router _router() {
    return Router()
      ..get('/health', (Request _) => _json(200, {'ok': true}))
      ..post('/join', _join)
      ..post('/keepalive', _auth(_keepalive))
      ..post('/ping', _auth(_ping))
      ..post('/frame', _auth(_frame))
      ..post('/result', _auth(_result))
      ..get('/groups', _auth(_groups))
      ..get('/students', _auth(_students))
      ..get('/catalog', _auth(_catalog))
      ..get('/test', _auth(_test))
      ..get('/diagnostics', _auth(_diagnostics))
      ..get('/packages', _auth(_packages))
      ..get('/package_questions', _auth(_packageQuestions))
      ..get('/media/<name>', (Request r, String name) {
        _authenticate(r);
        return _media(r, name);
      });
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
    final body = await _readJsonMap(req, HubLimits.joinBody);
    final code = body['code'];
    final machine = body['machine_id'];
    if (code is! String || code.length > 16) {
      throw const HubHttpError(400, 'bad_request');
    }
    if (machine is! String || !_machineIdRe.hasMatch(machine)) {
      throw const HubHttpError(400, 'bad_request');
    }
    final dn = body['device_name'];
    final deviceName = dn is String
        ? String.fromCharCodes(dn.codeUnits.where((c) => c >= 0x20))
        : '';

    final r = st.join(
      ip: ip,
      code: code,
      machineId: machine,
      deviceName:
          deviceName.length > 64 ? deviceName.substring(0, 64) : deviceName,
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
    // Body (if any) is irrelevant; Content-Length is still required.
    if (req.contentLength == null) {
      throw const HubHttpError(411, 'length_required');
    }
    if (req.contentLength! > HubLimits.keepaliveBody) {
      throw const HubHttpError(413, 'too_large');
    }
    _state!.touch(c);
    return _json(200, {'ok': true});
  }

  // ── proctoring ─────────────────────────────────────────────────────────────

  Future<Response> _ping(Request req, HubClient c) async {
    final body = await _readJsonMap(req, HubLimits.pingBody);
    final input = PingInput.fromJson(body);
    return _json(200, _state!.ping(c, input));
  }

  static final RegExp _frameTypeRe = RegExp(r'^(keyframe|patch)$');

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

    final bytes = await _readBody(req, HubLimits.frameBody);
    // Only a real JPEG (SOI marker) is ever stored or shown.
    if (bytes.length < 4 ||
        bytes[0] != 0xFF ||
        bytes[1] != 0xD8 ||
        bytes[2] != 0xFF) {
      throw const HubHttpError(400, 'bad_request');
    }
    return _json(
        200,
        _state!.acceptFrame(c,
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

    final body = await _readJsonMap(req, HubLimits.resultBody);
    final payload = body['payload'];
    if (payload is! Map) throw const HubHttpError(400, 'bad_request');
    final payloadMap = Map<String, dynamic>.from(payload);

    final st = _state!;
    final reason = st.checkResult(payloadMap);
    if (reason != null) {
      throw HubHttpError(422, 'rejected', extra: {'reason': reason});
    }

    final pack = session.pack;
    // A repeat of an already stored result is just acknowledged again.
    if (!await PackResultsDb.hasKey(pack.packUuid, key)) {
      if (c.resultsAccepted >= HubLimits.maxResultsPerClient) {
        throw const HubHttpError(403, 'client_quota');
      }
      final stats = await PackResultsDb.stats(pack.packUuid);
      // stored bytes are base64 of ciphertext: ~3/4 of that is the plain size.
      final approxPlain = stats.storedBytes * 3 ~/ 4 + stats.count * 400;
      if (stats.count >= HubLimits.maxPackEntries ||
          approxPlain >= HubLimits.maxPackPlainBytes) {
        throw const HubHttpError(507, 'pack_full');
      }

      final incidents = sanitizeMetaList(body['incidents'],
          maxItems: HubLimits.maxClientIncidents,
          overflowType: 'incident_overflow');
      final flags = sanitizeMetaList(body['clock_flags'],
          maxItems: HubLimits.maxClientClockFlags,
          overflowType: 'clock_flags_overflow');
      await PackResultsDb.append(
        packUuid: pack.packUuid,
        chainKey: pack.chainKey,
        idempotencyKey: key,
        payloadJson: jsonEncode(payloadMap),
        incidents: [
          ...incidents,
          // Which PC the result came from (informational, authenticated by
          // the chain like every meta field).
          {'type': 'lan_client', 'machine_id': c.machineId},
        ],
        // The hub's own clock flags ride along: the hub stamps the chain.
        clockFlags: [...flags, ...clock.drainFlags()],
      );
      st.resultStored(c, payloadMap['student_id'] as String);
    }
    return _json(200, {'ok': true});
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
    if (len > 32 * 1024 * 1024) throw const HubHttpError(404, 'not_found');
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
