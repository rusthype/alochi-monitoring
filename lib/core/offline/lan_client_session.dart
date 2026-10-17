// lib/core/offline/lan_client_session.dart
//
// A student PC's connection to the teacher's LAN hub (phase 3).
//
// [LanClientSession.join] does the HTTP handshake only (class code ->
// bearer token) and has no global side effects. [activate] then flips the app
// into LAN mode exactly like OfflinePackSession.open does for a USB pack: the
// global `api` becomes a [LanClientApi], test content is kept in memory only,
// and images are served from a per-session folder. [close] undoes it.
//
// Results: [recordResult] puts the finished test into the encrypted
// `lan_outbox` table and a background loop POSTs it to the hub until the hub
// ACKs it (the row is deleted only then). A hub that is down or restarted loses
// nothing: rows simply wait for the next connection to a hub of the same pack.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../features/diagnostic/data/diagnostic_kiosk_api.dart';
import '../api/api_client.dart';
import '../db/lan_outbox_db.dart';
import '../db/test_cache.dart';
import '../local_server/hub_guard.dart' show HubLimits, packFingerprint;
import '../security/incident_log.dart';
import '../security/monitored_clock.dart';
import 'lan_client_api.dart';
import 'lan_diagnostic_api.dart';
import 'offline_content_source.dart';
import 'offline_crypto.dart';
import 'offline_errors.dart';
import 'offline_media.dart';
import 'offline_session.dart';

/// "192.168.1.5:8080", "192.168.1.5" (port 8080) or "pc-name:8085"; null when
/// it is not a plausible host[:port]. A leading `http://` is tolerated.
({String host, int port})? parseHubAddress(String input,
    {int defaultPort = 8080}) {
  var t = input.trim();
  if (t.startsWith('http://')) t = t.substring(7);
  while (t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  if (t.isEmpty) return null;
  var host = t;
  var port = defaultPort;
  final i = t.lastIndexOf(':');
  if (i >= 0) {
    host = t.substring(0, i);
    final parsed = int.tryParse(t.substring(i + 1));
    if (parsed == null || parsed < 1 || parsed > 65535) return null;
    port = parsed;
  }
  if (!RegExp(r'^[A-Za-z0-9.\-]{1,253}$').hasMatch(host)) return null;
  return (host: host, port: port);
}

/// Response ceilings (S-009): a hub (or whatever answers on its address) must
/// not be able to make a student PC buffer without bound.
const int kLanMaxJson = 4 * 1024 * 1024;
const int kLanMaxBigJson = 32 * 1024 * 1024; // whole tests / diagnostics

/// Reads a streamed response but refuses to buffer more than [maxBytes]: a
/// declared Content-Length above it, or a body that grows past it, aborts.
Future<http.Response> readCapped(http.StreamedResponse r, int maxBytes) async {
  const tooLarge =
      ApiException(502, 'lan: response too large', code: kLanBadResponse);
  final declared = r.contentLength;
  if (declared != null && declared > maxBytes) {
    unawaited(r.stream.listen((_) {}).cancel());
    throw tooLarge;
  }
  final out = BytesBuilder(copy: false);
  await for (final chunk in r.stream) {
    out.add(chunk);
    if (out.length > maxBytes) throw tooLarge; // leaving the loop cancels it
  }
  return http.Response.bytes(out.takeBytes(), r.statusCode,
      headers: r.headers, request: r.request);
}

enum LanJoinError {
  badAddress,
  badCode,
  blocked,
  full,
  unreachable,
  badResponse,
  packActive,

  /// The teacher closed joining (everybody is in).
  joinsClosed,
}

class LanJoinException implements Exception {
  final LanJoinError code;
  final int retryAfterSec;
  const LanJoinException(this.code, {this.retryAfterSec = 0});
  @override
  String toString() => 'LanJoinException(${code.name})';
}

class LanClientSession implements OfflineContentSource {
  final Uri base;
  final String machineId;
  final String hubName;
  final String _packUuid;
  final String _schoolId;
  final String _schoolCode;
  final Directory mediaDir;
  final http.Client _http;
  final bool _ownsHttp;
  final String _token; // bearer secret: never logged

  LanClientSession._({
    required this.base,
    required String token,
    required this.machineId,
    required this.hubName,
    required String packUuid,
    required String schoolId,
    required String schoolCode,
    required this.mediaDir,
    required http.Client client,
    required bool ownsClient,
  })  : _token = token,
        _packUuid = packUuid,
        _schoolId = schoolId,
        _schoolCode = schoolCode,
        _http = client,
        _ownsHttp = ownsClient;

  /// True when [host]:[port] is exactly the address this session joined.
  bool isSameHub(String host, int port) =>
      base.port == port && base.host.toLowerCase() == host.toLowerCase();

  /// Short tag of the hub's pack, to compare with what the teacher reads out.
  String get fingerprint => packFingerprint(_packUuid);

  /// The active LAN session, or null.
  static LanClientSession? current;
  static final ValueNotifier<LanClientSession?> notifier =
      ValueNotifier<LanClientSession?>(null);
  static bool get isActive => current != null;

  /// Hub answered the last keepalive.
  final ValueNotifier<bool> connected = ValueNotifier<bool>(true);

  /// The hub rejected our token (restart / kicked): join again with the code.
  final ValueNotifier<bool> needsRejoin = ValueNotifier<bool>(false);

  /// Why the hub is not taking results right now (`pack_full` / `client_quota`),
  /// or null. The results stay queued and are retried slowly; the operator is
  /// told to ask the teacher (S-001).
  final ValueNotifier<String?> hold = ValueNotifier<String?>(null);
  int _holdUntilTicks = 0;
  static const int _holdRetryMs = 5 * 60 * 1000;

  /// Results of this pack still waiting for the hub's ack.
  final ValueNotifier<int> pending = ValueNotifier<int>(0);

  static const Duration _tick = Duration(seconds: 5);
  Timer? _timer;
  bool _closed = false;
  bool _flushing = false;

  static MonitoringApi? _onlineApi;
  static DiagnosticKioskApi? _onlineDiagnosticApi;

  // ── join ───────────────────────────────────────────────────────────────────

  static final RegExp _hostRe = RegExp(r'^[A-Za-z0-9.\-]{1,253}$');
  static String? _processId;
  static const String _machineKey = 'lan_machine_id_v1';
  static final RegExp _uuidRe = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// The id this installation presents to hubs: a random UUID made on first
  /// use and kept in the app's settings. Deliberately NOT the Windows
  /// MachineGuid -- that is shared by every PC cloned from one lab image, and
  /// readable by anyone with registry access (S-004). The hub additionally
  /// matches on the source address before treating two joins as the same PC.
  static Future<String> persistentMachineId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_machineKey);
      if (saved != null && _uuidRe.hasMatch(saved)) return saved;
      final id = const Uuid().v4();
      await prefs.setString(_machineKey, id);
      return id;
    } catch (e) {
      debugPrint(
          'LanClientSession: machine id not persisted (${e.runtimeType})');
      return _processId ??= 'proc-${const Uuid().v4()}';
    }
  }

  static String _defaultDeviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return '';
    }
  }

  /// Class code -> session token. No global state is touched (so it can run
  /// next to an open pack in tests); call [activate] on the result to enter
  /// LAN mode, which refuses while a USB pack is open.
  static Future<LanClientSession> join({
    required String host,
    required int port,
    required String code,
    http.Client? client,
    String? machineId,
    String? deviceName,
    Future<Directory> Function(String packUuid)? mediaDirFor,
    LanClientSession? replacing,
  }) async {
    final h = host.trim();
    if (!_hostRe.hasMatch(h) || port < 1 || port > 65535) {
      throw const LanJoinException(LanJoinError.badAddress);
    }
    final owns = client == null;
    final c = client ?? http.Client();
    final mid = machineId ?? await persistentMachineId();
    final base = Uri(scheme: 'http', host: h, port: port);

    http.Response resp;
    try {
      final req = http.Request('POST', base.replace(path: '/join'))
        ..headers['content-type'] = 'application/json'
        // A reply must never forward this request (and its bearer token).
        ..followRedirects = false
        // A PC re-joining while it still holds a live token says so: the hub
        // then lets it past the global failure gate and the join lock. The
        // token goes ONLY to the very host and port it was issued by -- never
        // to a hub that was merely picked or typed next (N-4).
        ..headers.addAll(replacing != null && replacing.isSameHub(h, port)
            ? {'authorization': 'Bearer ${replacing._token}'}
            : const {})
        ..body = jsonEncode({
          'code': code.trim(),
          'machine_id': mid,
          'device_name': deviceName ?? _defaultDeviceName(),
        });
      final streamed = await c.send(req).timeout(const Duration(seconds: 8));
      resp = await readCapped(streamed, 64 * 1024)
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      if (owns) c.close();
      throw const LanJoinException(LanJoinError.unreachable);
    } on SocketException {
      if (owns) c.close();
      throw const LanJoinException(LanJoinError.unreachable);
    } on http.ClientException {
      if (owns) c.close();
      throw const LanJoinException(LanJoinError.unreachable);
    } on ApiException {
      if (owns) c.close();
      throw const LanJoinException(LanJoinError.badResponse);
    }

    Map<String, dynamic>? body;
    try {
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      if (d is Map) body = Map<String, dynamic>.from(d);
    } catch (_) {}

    LanJoinException fail(LanJoinError e, {int retry = 0}) {
      if (owns) c.close();
      return LanJoinException(e, retryAfterSec: retry);
    }

    switch (resp.statusCode) {
      case 200:
        break;
      case 401:
        throw fail(LanJoinError.badCode);
      case 429:
        final ra = body?['retry_after'];
        throw fail(LanJoinError.blocked, retry: ra is int ? ra : 60);
      case 503:
        throw fail(LanJoinError.full);
      case 403:
        throw fail(body?['error'] == 'joins_locked'
            ? LanJoinError.joinsClosed
            : LanJoinError.badResponse);
      default:
        throw fail(LanJoinError.badResponse);
    }

    final token = body?['token'];
    final packUuid = body?['pack_uuid'];
    if (token is! String ||
        token.length < 16 ||
        token.length > 128 ||
        packUuid is! String ||
        !_uuidRe.hasMatch(packUuid)) {
      throw fail(LanJoinError.badResponse);
    }
    final dir = await (mediaDirFor ?? OfflinePackSession.mediaDirFor)(packUuid);
    return LanClientSession._(
      base: base,
      token: token,
      machineId: mid,
      hubName: (body?['hub_name'] ?? '').toString(),
      packUuid: packUuid,
      schoolId: (body?['school_id'] ?? '').toString(),
      schoolCode: (body?['school_code'] ?? '').toString(),
      mediaDir: dir,
      client: c,
      ownsClient: owns,
    );
  }

  // ── lifecycle ──────────────────────────────────────────────────────────────

  /// Enters LAN mode. Replaces an already active LAN session (re-join).
  Future<void> activate() async {
    if (OfflinePackSession.isActive) {
      throw const LanJoinException(LanJoinError.packActive);
    }
    current?._restoreOnline();
    _onlineApi = api;
    _onlineDiagnosticApi = diagnosticKioskApi;
    api = LanClientApi(this);
    diagnosticKioskApi = LanDiagnosticKioskApi(this);
    TestCache.enterMemoryMode();
    OfflineMedia.root = mediaDir;
    current = this;
    notifier.value = this;
    await OfflinePackSession.cleanupMedia(keepPackUuid: _packUuid);
    await _refreshPending();
    _timer = Timer.periodic(_tick, (_) => unawaited(_housekeeping()));
    unawaited(_housekeeping());
  }

  /// Leaves LAN mode: back to the online client, content and images dropped.
  /// Results not yet acknowledged stay in the outbox.
  void close() {
    if (!identical(current, this)) {
      _shutdown();
      return;
    }
    _restoreOnline();
    unawaited(OfflinePackSession.cleanupMedia());
  }

  void _restoreOnline() {
    if (!identical(current, this)) return;
    final online = _onlineApi;
    if (online != null) api = online;
    final onlineDiag = _onlineDiagnosticApi;
    if (onlineDiag != null) diagnosticKioskApi = onlineDiag;
    _onlineApi = null;
    _onlineDiagnosticApi = null;
    TestCache.exitMemoryMode();
    OfflineMedia.root = null;
    current = null;
    notifier.value = null;
    _shutdown();
  }

  void _shutdown() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    // Tell the hub we are gone (best effort), then drop the connection.
    final http_ = _http;
    final owns = _ownsHttp;
    http_
        .post(base.replace(path: '/leave'),
            headers: {'authorization': 'Bearer $_token'})
        .timeout(const Duration(seconds: 2))
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(() {
          if (owns) http_.close();
        });
  }

  // ── transport ──────────────────────────────────────────────────────────────

  /// Authenticated request. Network failures become `kLanUnreachable`, a 401
  /// becomes `kLanSessionExpired` (and flips [needsRejoin]); any other status
  /// is returned to the caller.
  Future<http.Response> request(
    String method,
    String path, {
    Map<String, String>? query,
    List<int>? body,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10),
    int maxBytes = kLanMaxJson,
  }) async {
    if (_closed) {
      throw const ApiException(0, 'lan: session closed',
          code: kLanSessionExpired);
    }
    final uri = base.replace(
        path: path,
        queryParameters: (query == null || query.isEmpty) ? null : query);
    final req = http.Request(method, uri)
      ..headers['authorization'] = 'Bearer $_token'
      ..headers.addAll(headers);
    if (body != null) req.bodyBytes = body;
    final http.Response resp;
    try {
      final streamed = await _http.send(req).timeout(timeout);
      resp = await readCapped(streamed, maxBytes).timeout(timeout);
    } on TimeoutException {
      connected.value = false;
      throw const ApiException(0, 'lan: hub unreachable',
          code: kLanUnreachable);
    } on SocketException {
      connected.value = false;
      throw const ApiException(0, 'lan: hub unreachable',
          code: kLanUnreachable);
    } on http.ClientException {
      connected.value = false;
      throw const ApiException(0, 'lan: hub unreachable',
          code: kLanUnreachable);
    }
    connected.value = true;
    if (resp.statusCode == 401) {
      needsRejoin.value = true;
      throw const ApiException(401, 'lan: session expired',
          code: kLanSessionExpired);
    }
    return resp;
  }

  /// GET that must succeed and return JSON.
  Future<Object?> getJson(String path,
      {Map<String, String>? query,
      Duration timeout = const Duration(seconds: 15),
      bool inIsolate = false,
      int maxBytes = kLanMaxJson}) async {
    final resp = await request('GET', path,
        query: query, timeout: timeout, maxBytes: maxBytes);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, 'lan: hub refused ($path)',
          code: resp.statusCode == 404 ? kOfflineNotFound : null);
    }
    final text = utf8.decode(resp.bodyBytes);
    return inIsolate ? compute(jsonDecode, text) : jsonDecode(text);
  }

  /// Unauthenticated reachability probe (drives the connectivity indicator).
  Future<bool> health() async {
    try {
      final resp = await _http
          .get(base.replace(path: '/health'))
          .timeout(const Duration(seconds: 2));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── background loop ────────────────────────────────────────────────────────

  Future<void> _housekeeping() async {
    if (_closed) return;
    try {
      await request('POST', '/keepalive',
          body: const [],
          headers: const {'content-type': 'application/json'},
          timeout: const Duration(seconds: 4));
    } on ApiException {
      return; // connected/needsRejoin already updated; retry next tick
    }
    await flushOutbox();
  }

  // ── results ────────────────────────────────────────────────────────────────

  static final RegExp _keyRe = RegExp(r'^[A-Za-z0-9:_.\-]{1,64}$');

  @override
  Future<void> recordResult(Map<String, dynamic> payload,
      {String? token}) async {
    var key = (token == null || token.isEmpty) ? newIdempotencyToken() : token;
    // The hub accepts only short URL-safe keys; anything else is hashed (still
    // deterministic, so a retry of the same result keeps the same key).
    if (!_keyRe.hasMatch(key)) {
      key = 'h:${OfflineCrypto.sha256Hex(utf8.encode(key)).substring(0, 40)}';
    }
    final envelope = jsonEncode({
      'payload': payload,
      // Proctoring metadata gathered since the last result rides along.
      'incidents': IncidentLog.instance.drain(),
      'clock_flags': MonitoredClock.instance.drainFlags(),
    });
    await LanOutboxDb.enqueue(
        packUuid: _packUuid, idempotencyKey: key, envelopeJson: envelope);
    await _refreshPending();
    unawaited(flushOutbox());
  }

  Future<void> _refreshPending() async {
    try {
      pending.value =
          (await LanOutboxDb.pending(_packUuid, limit: 1000)).length;
    } catch (e) {
      debugPrint('LanClientSession: outbox count failed (${e.runtimeType})');
    }
  }

  /// Sends pending results to the hub, oldest first, until one fails
  /// transiently (order is kept). Returns how many were acknowledged.
  Future<int> flushOutbox() async {
    if (_flushing || _closed) return 0;
    // The hub said it is full / this PC is over its quota: do not hammer it.
    if (hold.value != null &&
        MonitoredClock.instance.ticksMs < _holdUntilTicks) {
      return 0;
    }
    _flushing = true;
    var acked = 0;
    try {
      final rows = await LanOutboxDb.pending(_packUuid);
      for (final row in rows) {
        final http.Response resp;
        try {
          resp = await request('POST', '/result',
              body: utf8.encode(row.envelopeJson),
              headers: {
                'content-type': 'application/json',
                'idempotency-key': row.idempotencyKey,
              },
              timeout: const Duration(seconds: 15));
        } on ApiException {
          await LanOutboxDb.markAttempt(row.id);
          break; // hub down / token gone: keep everything, retry later
        }
        final s = resp.statusCode;
        if (s == 200) {
          await LanOutboxDb.ack(row.id);
          acked++;
          hold.value = null;
        } else if (s == 507 ||
            (s == 403 && _reasonOf(resp) == 'client_quota')) {
          // Not this result's fault and not permanent: the teacher can make
          // room (export + new pack run) or raise nothing -- either way the
          // result must survive. Keep it queued, retry slowly, show why.
          await LanOutboxDb.markAttempt(row.id);
          hold.value = _reasonOf(resp);
          _holdUntilTicks = MonitoredClock.instance.ticksMs + _holdRetryMs;
          break;
        } else if (s == 408 || s == 429 || s >= 500) {
          await LanOutboxDb.markAttempt(row.id);
          break;
        } else {
          // The hub refused this result for good. Keep it, flagged.
          await LanOutboxDb.markRejected(row.id, _reasonOf(resp));
        }
      }
    } catch (e) {
      debugPrint('LanClientSession.flushOutbox failed (${e.runtimeType})');
    } finally {
      _flushing = false;
    }
    await _refreshPending();
    return acked;
  }

  static String _reasonOf(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map) {
        final reason = d['reason'] ?? d['error'];
        if (reason is String && reason.isNotEmpty) return reason;
      }
    } catch (_) {}
    return 'http_${r.statusCode}';
  }

  // ── images ─────────────────────────────────────────────────────────────────

  static final RegExp _mediaRef =
      RegExp(r'^media/([0-9a-f]{64}\.(?:jpg|jpeg|png|gif|webp))$');

  /// Every `media/<sha256>.<ext>` string anywhere in [data].
  static Set<String> mediaNamesIn(Object? data) {
    final out = <String>{};
    final stack = <Object?>[data];
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      if (n is String) {
        final m = _mediaRef.firstMatch(n);
        if (m != null) out.add(m.group(1)!);
      } else if (n is Map) {
        stack.addAll(n.values);
      } else if (n is List) {
        stack.addAll(n);
      }
    }
    return out;
  }

  @override
  Future<void> prepareMedia(Object? data) => ensureMedia(mediaNamesIn(data));

  /// Downloads the images that are not on disk yet. Names are content hashes,
  /// so every download is verified against its own name. A 404 (the pack never
  /// had that file) is skipped; any other failure aborts so the caller can
  /// retry instead of showing a test with holes.
  Future<void> ensureMedia(Set<String> names) async {
    if (names.isEmpty) return;
    await mediaDir.create(recursive: true);
    final todo = <String>[];
    for (final n in names) {
      final f = File(p.join(mediaDir.path, n));
      if (!await f.exists() || await f.length() == 0) todo.add(n);
    }
    const parallel = 4;
    for (var i = 0; i < todo.length; i += parallel) {
      await Future.wait(todo.skip(i).take(parallel).map(_fetchMedia));
    }
  }

  Future<void> _fetchMedia(String name) async {
    http.Response resp;
    var attempt = 0;
    while (true) {
      resp = await request('GET', '/media/$name',
          timeout: const Duration(seconds: 20),
          maxBytes: HubLimits.maxMediaFile);
      // A burst of images at test start can empty the hub's per-PC allowance;
      // it refills within a second or two, so wait instead of failing the test.
      if (resp.statusCode != 429 || ++attempt >= 6) break;
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
    if (resp.statusCode == 404) return;
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, 'lan: media refused');
    }
    final bytes = resp.bodyBytes;
    if (OfflineCrypto.sha256Hex(bytes) != name.substring(0, 64)) {
      throw const ApiException(502, 'lan: media hash mismatch');
    }
    await File(p.join(mediaDir.path, name)).writeAsBytes(bytes, flush: true);
  }

  // ── diagnostic snapshot (OfflineContentSource) ─────────────────────────────

  List<Map<String, dynamic>> _groups = const [];
  List<Map<String, dynamic>> _students = const [];
  List<Map<String, dynamic>> _diagTests = const [];
  bool _snapshotLoaded = false;

  /// Roster + diagnostic questions, fetched once on first use (the diagnostic
  /// adapter reads them synchronously afterwards).
  Future<void> loadDiagnosticSnapshot() async {
    if (_snapshotLoaded) return;
    final d = await getJson('/diagnostics',
        timeout: const Duration(seconds: 30),
        inIsolate: true,
        maxBytes: kLanMaxBigJson);
    if (d is! Map) {
      throw const ApiException(502, 'lan: bad diagnostics snapshot');
    }
    List<Map<String, dynamic>> list(Object? v) => v is List
        ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : const [];
    _groups = list(d['groups']);
    _students = list(d['students']);
    _diagTests = [
      for (final t in list(d['tests']))
        {'type': 'diagnostic', 'key': t['key'], 'data': t['data']}
    ];
    _snapshotLoaded = true;
  }

  @override
  String get packUuid => _packUuid;
  @override
  String get schoolId => _schoolId;
  @override
  String get schoolCode => _schoolCode;
  @override
  List<Map<String, dynamic>> get groups => _groups;
  @override
  List<Map<String, dynamic>> get students => _students;

  @override
  List<Map<String, dynamic>> testsOfType(String type) =>
      type == 'diagnostic' ? _diagTests : const <Map<String, dynamic>>[];

  static int _lastOrdinal = 0;

  /// Unique per submission (the client keeps no chain to count rows in).
  @override
  Future<int> nextAttemptOrdinal(String keyPrefix) async {
    _lastOrdinal = max(_lastOrdinal + 1, MonitoredClock.instance.nowMs);
    return _lastOrdinal;
  }
}
