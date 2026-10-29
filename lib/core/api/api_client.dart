// lib/core/api/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../diagnostics/error_log.dart';
import 'api_host.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../models/add_student.dart';
import '../models/test_catalog.dart';
import '../db/offline_queue.dart';
import '../db/local_students_db.dart';
import '../db/diagnostic_history_db.dart';
import '../services/server_clock.dart';
import '../sync/server_backoff.dart';
import '../../features/diagnostic/data/diagnostic_kiosk_api.dart'
    show diagnosticKioskApi;

/// Stable machine codes of [ApiException.code] for transport-level failures
/// (never shown to the student: the UI maps them through
/// `localizedApiError` in api_error_text.dart).
const String kApiTimeout = 'timeout';
const String kApiNetwork = 'network';
const String kApiTls = 'tls';

/// The body was not what the endpoint promises (captive-portal / proxy HTML,
/// truncated JSON). Always retryable, whatever the HTTP status says.
const String kApiBadResponse = 'bad_response';

/// true ONLY when the server definitively rejected a result payload, so
/// retrying can never help: 400 / 409 / 422. Everything else (401, 403, 404,
/// 408, 413, 429, 5xx, network, HTML bodies) is retryable - dropping a finished
/// exam on a transient proxy / deploy / auth glitch loses the student's work.
bool isPermanentResultRejection(int status, {String? code}) =>
    code != kApiBadResponse &&
    (status == 400 || status == 409 || status == 422);

/// A 409 on a result submit is ONLY an acknowledgement when the body says the
/// server already holds this result (`duplicate: true`, the legacy
/// `status: already_submitted`, or a receipt `id` / `result_id`) and carries no
/// `error`. Every other 409 (`max_attempts_exceeded`, an unknown body) is a
/// REJECTION: the result was not stored and must be kept, not acked.
bool isDuplicateConflict(Map<String, dynamic>? body) {
  if (body == null) return false;
  final err = body['error'];
  if (err is String && err.isNotEmpty) return false;
  return body['duplicate'] == true ||
      body['status'] == 'already_submitted' ||
      body['result_id'] != null ||
      _hasReceipt(body);
}

/// The machine reason of a rejected 409 body (`error`), else `conflict`.
String conflictReason(Map<String, dynamic>? body) {
  final err = body?['error'];
  return err is String && err.isNotEmpty ? err : 'conflict';
}

/// Short, secret-free reason a 400 / 422 rejected a RESULT payload. Machine
/// `error` / `code` first, then a truncated `detail` / `message`, then the
/// field names of a DRF validation error (never their values - they echo the
/// student's answers), else `http_<status>`. Tolerates absent / odd bodies.
String resultRejectionReason(int status, Map<String, dynamic>? body) {
  String? text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
  String cut(String v) => v.length > 80 ? v.substring(0, 80) : v;
  if (body != null) {
    final machine = text(body['error']) ?? text(body['code']);
    if (machine != null) return cut(machine);
    final detail = text(body['detail']) ?? text(body['message']);
    if (detail != null) return cut(detail);
    final fields = [
      for (final e in body.entries)
        if (e.value is List || e.value is Map) e.key
    ];
    if (fields.isNotEmpty) return cut('invalid:${fields.join(',')}');
  }
  return 'http_$status';
}

/// A direct (online) result submit that did not sync must still be kept - in
/// the queue - when the failure is retryable OR the server rejected it
/// (`rejected: true` -> the queue re-submits it once and holds it in
/// `rejected_results`). Only a non-result style permanent drop is discarded.
bool keepUnsyncedResult(Map<String, dynamic> reply) =>
    reply['synced'] != true &&
    (reply['permanent'] != true || reply['rejected'] == true);

bool _looksLikeHtml(http.Response r) {
  final ct = (r.headers['content-type'] ?? '').toLowerCase();
  if (ct.contains('text/html')) return true;
  final head = r.body.trimLeft();
  return head.startsWith('<');
}

/// A 2xx whose body is a JSON object - the only shape our server answers a
/// write with. A 3xx, a captive-portal / proxy HTML page or any other body is
/// NOT an acknowledgement, whatever the status says.
bool isJsonObjectReply(http.Response r) {
  if (r.statusCode < 200 || r.statusCode >= 300) return false;
  if (_looksLikeHtml(r)) return false;
  try {
    return jsonDecode(utf8.decode(r.bodyBytes)) is Map;
  } catch (_) {
    return false;
  }
}

/// [isJsonObjectReply] that also carries the server's receipt: `ok: true`, an
/// `id`, or `duplicate: true` (monitoring result / question-report shapes,
/// apps/monitoring/views.py).
bool isSubmitAck(http.Response r) {
  if (!isJsonObjectReply(r)) return false;
  final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
  return _hasReceipt(d);
}

bool _hasReceipt(Map d) =>
    d['ok'] == true || d['id'] != null || d['duplicate'] == true;

/// Seconds the server asked us to wait (`Retry-After` on 429 / 503), else null.
int? retryAfterSecondsOf(http.Response r) {
  if (r.statusCode != 429 && r.statusCode != 503) return null;
  DateTime? serverNow;
  try {
    final date = r.headers['date'];
    if (date != null) serverNow = HttpDate.parse(date);
  } catch (_) {}
  final d = ServerBackoff.parse(r.headers['retry-after'], now: serverNow);
  return d == null ? null : (d.inMilliseconds / 1000).ceil();
}

/// A failure of the connection or the server (network / timeout / TLS / HTML
/// page / 5xx / 408 / 429) - as opposed to the server answering "no" (401, 403,
/// 404 ...). Only these may be answered with a cached copy of the data.
bool isOfflineLikeError(Object e) {
  if (e is ApiException) {
    switch (e.code) {
      case kApiTimeout:
      case kApiNetwork:
      case kApiTls:
      case kApiBadResponse:
        return true;
    }
    final s = e.statusCode;
    return s == 0 || s == 408 || s == 429 || s >= 500;
  }
  // Anything that is not a server verdict (socket, timeout, parse ...).
  return true;
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  /// Machine-readable `code` from the error body (e.g. `stale_generation`),
  /// when the backend sends one — null otherwise.
  final String? code;

  /// The server's `Retry-After` (429 / 503), capped at 5 min.
  final Duration? retryAfter;

  /// The decoded JSON error body of a 4xx/5xx `_post` reply (null otherwise):
  /// lets a caller tell a 409 "already stored" from a 409 rejection.
  final Map<String, dynamic>? body;
  const ApiException(this.statusCode, this.message,
      {this.code, this.retryAfter, this.body});
  // UI da to'g'ridan-to'g'ri ko'rsatish uchun toString faqat tushunarli matnni qaytaradi.
  @override
  String toString() => message;
}

class MonitoringApi {
  /// True for the LAN client (hub-backed) api.
  bool get isLan => false;

  // ponytail: one env var overrides the whole app's backend host; see
  // diagnostic_kiosk_api.dart which reads the same API_BASE_URL.
  static final String _host = normalizeApiHost(const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.alochi.org',
  ));
  static final String _base = '$_host/api/v1/monitoring';
  static final String _media = _host;

  /// Relative URL'ni absolute'ga o'giradi (rasm URL'lari uchun)
  static String fixImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    final trimmed = url.trim();
    final absolute = trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('//');
    // Force https only when running against the real (https) backend —
    // a developer-supplied plain-http API_BASE_URL override (local dev
    // server, no TLS) must be respected as-is, or every image request
    // hangs forever trying TLS against a plain-http port.
    final forceHttps = _host.startsWith('https://');
    final fullUrl = trimmed.startsWith('//')
        ? 'https:$trimmed'
        : (trimmed.startsWith('http://') && forceHttps)
            ? 'https://${trimmed.substring('http://'.length)}'
            : absolute
                ? trimmed
                : '$_media${trimmed.startsWith('/') ? trimmed : '/$trimmed'}';
    return _normalizeImageUrl(fullUrl);
  }

  static String _normalizeImageUrl(String url) {
    final queryIndex = url.indexOf('?');
    final fragmentIndex = url.indexOf('#');
    final splitIndexes = [queryIndex, fragmentIndex].where((i) => i >= 0);
    final splitIndex = splitIndexes.isEmpty
        ? -1
        : splitIndexes
            .reduce((value, element) => value < element ? value : element);
    final prefixAndPath = splitIndex == -1 ? url : url.substring(0, splitIndex);
    final suffix = splitIndex == -1 ? '' : url.substring(splitIndex);

    final schemeIndex = prefixAndPath.indexOf('://');
    if (schemeIndex == -1) return encodeUrlKeepingEscapes(url);

    final hostStart = schemeIndex + 3;
    final pathStart = prefixAndPath.indexOf('/', hostStart);
    if (pathStart == -1) return encodeUrlKeepingEscapes(url);

    final prefix = prefixAndPath.substring(0, pathStart);
    final path = prefixAndPath.substring(pathStart);
    final normalizedPath =
        path.split('/').where((segment) => segment.isNotEmpty).join('/');

    return encodeUrlKeepingEscapes(
      '$prefix/${normalizedPath.isEmpty ? '' : normalizedPath}$suffix',
    );
  }

  static bool _isHex(int c) =>
      (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x46) ||
      (c >= 0x61 && c <= 0x66);

  /// Like [Uri.encodeFull], but an existing `%XX` escape is left alone
  /// (`encodeFull('a%20b.png')` gives `a%2520b.png`, a different file).
  /// Spaces, Uzbek / Cyrillic letters and a stray `%` are still encoded.
  @visibleForTesting
  static String encodeUrlKeepingEscapes(String url) {
    final out = StringBuffer();
    final units = url.codeUnits;
    var i = 0;
    var plainStart = 0;
    void flush(int end) {
      if (end > plainStart) {
        out.write(Uri.encodeFull(url.substring(plainStart, end)));
      }
    }

    while (i < units.length) {
      if (units[i] == 0x25 &&
          i + 2 < units.length &&
          _isHex(units[i + 1]) &&
          _isHex(units[i + 2])) {
        flush(i);
        out.write(url.substring(i, i + 3));
        i += 3;
        plainStart = i;
      } else {
        i++;
      }
    }
    flush(units.length);
    return out.toString();
  }

  static const Duration _timeout = Duration(seconds: 20);
  String? _token;

  void setToken(String token) => _token = token;
  void clearToken() => _token = null;

  /// True once a login token is set (LAN/offline clients override their own
  /// endpoints and do not need one).
  bool get hasAuthToken => _token != null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<http.Response> _send(Future<http.Response> Function() req) async {
    // `message` is a debug string only; the UI shows text by `code`.
    try {
      final sent = Stopwatch()..start();
      final resp = await req().timeout(_timeout);
      // Time-lock checks use server time: learn the offset from any real
      // (non-portal) answer.
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          !_looksLikeHtml(resp)) {
        ServerClock.observe(resp.headers['date'],
            ageHeader: resp.headers['age'],
            roundTripMs: sent.elapsedMilliseconds);
      }
      return resp;
    } on TimeoutException catch (e) {
      ErrorLog.record(e, 'api');
      throw const ApiException(
          0, "Server javob bermayapti. Internetingizni tekshiring.",
          code: kApiTimeout);
    } on SocketException catch (e) {
      ErrorLog.record(e, 'api');
      throw const ApiException(0, "Internet aloqasi yo'q.", code: kApiNetwork);
    } on HandshakeException catch (e) {
      ErrorLog.record(e, 'api');
      throw const ApiException(0, "Tarmoq xatosi. Qayta urinib ko'ring.",
          code: kApiTls);
    } on TlsException catch (e) {
      ErrorLog.record(e, 'api');
      throw const ApiException(0, "Tarmoq xatosi. Qayta urinib ko'ring.",
          code: kApiTls);
    } on FormatException catch (e) {
      ErrorLog.record(e, 'api');
      throw const ApiException(0, "Noto'g'ri javob", code: kApiBadResponse);
    } on HttpException catch (e) {
      ErrorLog.record(e, 'api');
      throw const ApiException(0, "Tarmoq xatosi. Qayta urinib ko'ring.",
          code: kApiNetwork);
    } on http.ClientException catch (e) {
      ErrorLog.record(e, 'api');
      throw const ApiException(0, "Tarmoq xatosi. Qayta urinib ko'ring.",
          code: kApiNetwork);
    } on OSError catch (e) {
      ErrorLog.record(e, 'api');
      throw const ApiException(0, "Tarmoq xatosi. Qayta urinib ko'ring.",
          code: kApiNetwork);
    }
  }

  /// JSON body of [resp]; a non-JSON body (captive portal, proxy error page)
  /// becomes a retryable [kApiBadResponse] instead of a raw FormatException.
  dynamic _decode(http.Response resp) {
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      final wait = retryAfterSecondsOf(resp);
      throw ApiException(
          resp.statusCode,
          resp.statusCode >= 500 ? 'Server xatosi' : "Noto'g'ri javob",
          code: kApiBadResponse,
          retryAfter: wait == null ? null : Duration(seconds: wait));
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {Map<String, String> extraHeaders = const {}}) async {
    final resp = await _send(() => http.post(
          Uri.parse('$_base$path'),
          headers: {..._headers, ...extraHeaders},
          body: jsonEncode(body),
        ));
    final decoded = _decode(resp);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(resp.statusCode, "Noto'g'ri javob",
          code: kApiBadResponse);
    }
    final data = decoded;
    if (resp.statusCode >= 400) {
      final raw = data['detail'] ?? data['message'] ?? '';
      final msg = raw.toString().isNotEmpty
          ? raw.toString()
          : _statusMessage(resp.statusCode);
      final wait = retryAfterSecondsOf(resp);
      throw ApiException(resp.statusCode, msg,
          retryAfter: wait == null ? null : Duration(seconds: wait),
          body: data);
    }
    // 1xx / 3xx are never our server's answer to a write (portal redirect).
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(resp.statusCode, "Noto'g'ri javob",
          code: kApiBadResponse);
    }
    return data;
  }

  Future<dynamic> _get(String path,
      {Map<String, String> extraHeaders = const {}}) async {
    final resp = await _send(() => http.get(
          Uri.parse('$_base$path'),
          headers: {..._headers, ...extraHeaders},
        ));
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, _statusMessage(resp.statusCode));
    }
    return _decode(resp);
  }

  /// [_get] bilan bir xil, lekin katta javoblar (test katalog/kontent) uchun
  /// jsonDecode'ni alohida isolatda bajaradi — UI thread bloklanmaydi.
  Future<dynamic> _getCompute(String path,
      {Map<String, String> extraHeaders = const {}}) async {
    final resp = await _send(() => http.get(
          Uri.parse('$_base$path'),
          headers: {..._headers, ...extraHeaders},
        ));
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, _statusMessage(resp.statusCode));
    }
    try {
      return await compute(jsonDecode, utf8.decode(resp.bodyBytes));
    } on FormatException {
      throw ApiException(resp.statusCode, "Noto'g'ri javob",
          code: kApiBadResponse);
    }
  }

  String _statusMessage(int status) {
    if (status == 400) return "Login yoki parol noto'g'ri";
    if (status == 401) return 'Sessiya tugadi, qayta kiring';
    if (status == 403) return "Ruxsat yo'q";
    if (status == 404) return 'Topilmadi';
    if (status == 429) return "Ko'p urinish, biroz kuting";
    if (status >= 500) return 'Server xatosi, keyinroq urinib ko\'ring';
    return 'Xato: $status';
  }

  Future<StudentSession> login(String username, String password) async {
    final data = await _post(
        '/auth/login/', {'username': username, 'password': password});
    return StudentSession.fromJson(data);
  }

  Future<bool> ping() async {
    try {
      final data = await _get('/ping/') as Map<String, dynamic>;
      return data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Fallback health probe outside the /monitoring path prefix, with its own
  /// short timeout (ConnectivityService only calls this after its primary 2
  /// attempts already failed, so it must fail fast, not inherit the 20s
  /// client-wide _timeout).
  Future<bool> pingHealth(
      {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final resp =
          await http.get(Uri.parse('$_host/api/v1/health/')).timeout(timeout);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Exposes the configured API host (respects the API_BASE_URL dev override)
  /// for ConnectivityService's plain-DNS fallback check.
  static String get host => _host;

  /// Uploads one locally-queued crash report (see CrashReporterService).
  /// Best-effort, same posture as [proctorFrame]: any failure just means the
  /// file stays on disk for the next attempt — this must never throw.
  Future<bool> uploadCrashReport(String jsonBody) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_host/api/v1/monitoring/crash-report/'),
            headers: _headers,
            body: jsonBody,
          )
          .timeout(const Duration(seconds: 10));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Returns the decoded response body (contains `ok`, and optionally
  /// `conflict`/`terminated` flags — see HeartbeatService for how these are
  /// consumed). Throws [ApiException] on HTTP/network failure, same as
  /// every other `_post`-based call; callers that need offline-first
  /// degrade-on-failure behavior (HeartbeatService._ping) catch it there.
  Future<Map<String, dynamic>> sessionPing({
    required String sessionId,
    String schoolCode = '',
    String name = '',
    String variant = '',
    String testKey = '',
    String status = 'active',
    String? studentCode,
    int tabSwitchCount = 0,
    int? currentQuestionIndex,
    int? totalQuestions,
    List<int>? questionTimes,
    String? platform,
    String? appVersion,
    String? deviceName,
    Map<String, dynamic>? answers,
    int? elapsedSeconds,
    int? remainingSeconds,
    String? localIp,
    String? machineId,
    String? macAddress,
    List<String>? capabilities,
  }) async {
    return _post('/session/ping/', {
      'session_id': sessionId,
      'school_code': schoolCode,
      'name': name,
      'variant': variant,
      'test_key': testKey,
      'status': status,
      if (studentCode != null && studentCode.isNotEmpty)
        'student_code': studentCode,
      'tab_switch_count': tabSwitchCount,
      if (currentQuestionIndex != null)
        'current_question_index': currentQuestionIndex,
      if (totalQuestions != null) 'total_questions': totalQuestions,
      if (questionTimes != null) 'question_times': questionTimes,
      if (platform != null && platform.isNotEmpty) 'platform': platform,
      if (appVersion != null && appVersion.isNotEmpty)
        'app_version': appVersion,
      if (deviceName != null && deviceName.isNotEmpty)
        'device_name': deviceName,
      if (answers != null) 'answers': answers,
      if (elapsedSeconds != null) 'elapsed_seconds': elapsedSeconds,
      if (localIp != null && localIp.isNotEmpty) 'local_ip': localIp,
      if (machineId != null && machineId.isNotEmpty) 'machine_id': machineId,
      if (macAddress != null && macAddress.isNotEmpty)
        'mac_address': macAddress,
      if (capabilities != null && capabilities.isNotEmpty)
        'capabilities': capabilities,
    });
  }

  /// Server-side resume check for power-outage tolerance — the student's
  /// in-progress (finished=False) session for [testKey], if any. Used
  /// alongside AttemptStore's local resume so a student who loses power
  /// can resume on any PC, not just the one that crashed.
  ///
  /// Returns `{'exists': false}` shape on "no active session", same as the
  /// backend. Never throws for a plain "not found" — only network/HTTP
  /// failures propagate as [ApiException], same posture as every other
  /// `_get`-based call.
  Future<Map<String, dynamic>> sessionResume(String testKey) async {
    final data = await _get('/session/resume/$testKey/');
    return data as Map<String, dynamic>;
  }

  /// Uploads one live-proctoring screen frame (see ProctorService). Best
  /// effort, same posture as [uploadResultHtml] — a dropped frame must never
  /// interrupt the exam, so every failure path returns an empty map instead
  /// of throwing; the caller treats an empty map as "no panel action".
  Future<Map<String, dynamic>> proctorFrame({
    required String sessionId,
    required String token,
    required Uint8List jpeg,
    required bool focus,
    required int monitorCount,
    int? questionIndex,
    int? totalQuestions,
    String? questionText,
    String? selectedOptionText,
    String? frameType,
    int? x,
    int? y,
    int? w,
    int? h,
    int? streamEpoch,
    int? cursorX,
    int? cursorY,
    bool? cursorVisible,
    String? monitorsJson,
    int? monitorIndex,
  }) async {
    try {
      final req =
          http.MultipartRequest('POST', Uri.parse('$_base/proctor/frame/'))
            ..fields['session_id'] = sessionId
            ..fields['token'] = token
            ..fields['focus'] = focus.toString()
            ..fields['monitor_count'] = monitorCount.toString();
      if (monitorsJson != null) req.fields['monitors'] = monitorsJson;
      if (monitorIndex != null) {
        req.fields['monitor_index'] = monitorIndex.toString();
      }
      if (questionIndex != null) {
        req.fields['q_idx'] = questionIndex.toString();
      }
      if (totalQuestions != null) {
        req.fields['total'] = totalQuestions.toString();
      }
      if (questionText != null && questionText.isNotEmpty) {
        req.fields['q_text'] = questionText;
      }
      if (selectedOptionText != null && selectedOptionText.isNotEmpty) {
        req.fields['selected_option'] = selectedOptionText;
      }
      if (frameType != null) req.fields['frame_type'] = frameType;
      if (x != null) req.fields['x'] = x.toString();
      if (y != null) req.fields['y'] = y.toString();
      if (w != null) req.fields['w'] = w.toString();
      if (h != null) req.fields['h'] = h.toString();
      if (streamEpoch != null) {
        req.fields['stream_epoch'] = streamEpoch.toString();
      }
      if (cursorX != null) req.fields['cursor_x'] = cursorX.toString();
      if (cursorY != null) req.fields['cursor_y'] = cursorY.toString();
      if (cursorVisible != null) {
        req.fields['cursor_visible'] = cursorVisible.toString();
      }
      req.files
          .add(http.MultipartFile.fromBytes('frame', jpeg, filename: 'f.jpg'));
      final streamed = await req.send().timeout(const Duration(seconds: 5));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode == 200) {
        final decoded = jsonDecode(body);
        return decoded is Map<String, dynamic> ? decoded : {};
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> fetchDownloads(String schoolCode) async {
    try {
      final resp = await _send(() => http.get(
            Uri.parse(
                '$_base/downloads/?school=${Uri.encodeComponent(schoolCode)}'),
          ));
      if (resp.statusCode == 200) {
        final List<dynamic> data = jsonDecode(resp.body) as List<dynamic>;
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('fetchDownloads error: $e');
      return [];
    }
  }

  /// Throws [ApiException] on any failure (network, non-200, non-list body):
  /// an empty list means a school that REALLY has no groups, never an error.
  Future<List<Map<String, dynamic>>> fetchGroups(String schoolCode,
      {String? schoolId}) async {
    try {
      // school_id (School.number kolliziyasidan xoli) — berilsa, backend
      // ustunlik beradi (2026-09-07, /groups/?school= xuddi shu maktab-raqami
      // kolliziyasidan aziyat chekkan).
      final sid = (schoolId != null && schoolId.isNotEmpty)
          ? '&school_id=${Uri.encodeComponent(schoolId)}'
          : '';
      final resp = await _send(() => http.get(
            Uri.parse(
                '$_base/groups/?school=${Uri.encodeComponent(schoolCode)}$sid'),
            headers: _headers,
          ));
      return _rosterRows(resp);
    } catch (e) {
      debugPrint('fetchGroups error: $e');
      rethrow;
    }
  }

  /// Rows of a groups / students response. Non-200 and non-list bodies throw
  /// (the screens show a retry banner); only a real `[]` is "empty".
  List<Map<String, dynamic>> _rosterRows(http.Response resp) {
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, _statusMessage(resp.statusCode));
    }
    final data = _decode(resp);
    if (data is! List) {
      throw ApiException(resp.statusCode, "Noto'g'ri javob",
          code: kApiBadResponse);
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  /// [testKey] (optional) asks the backend to flag students who already took
  /// that test (`done`: bool per student). An older backend ignores the query
  /// and omits `done`/`code` — callers must treat both as optional.
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId,
      {String? testKey}) async {
    try {
      final q = (testKey == null || testKey.isEmpty)
          ? ''
          : '?test_key=${Uri.encodeQueryComponent(testKey)}';
      final resp = await _send(() => http.get(
            Uri.parse(
                '$_base/groups/${Uri.encodeComponent(groupId)}/students/$q'),
            headers: _headers,
          ));
      return _rosterRows(resp);
    } catch (e) {
      debugPrint('fetchStudents error: $e');
      rethrow;
    }
  }

  /// Proctor adds a child missing from [groupId]'s roster
  /// (POST monitoring/students/add/). School is derived server-side from the
  /// group. Idempotent on `draft.clientTempId`, so a retry after a lost
  /// response returns the same request. Throws [SimilarStudentsException]
  /// (409, nothing created) unless [confirmNew]; other failures are
  /// [ApiException] (`code`: invalid_name / invalid_group / pending_limit;
  /// statusCode 0 = no network, 404/405 = backend without the endpoint).
  Future<AddStudentResult> addStudent({
    required String groupId,
    required AddStudentDraft draft,
    bool confirmNew = false,
  }) async {
    final resp = await _send(() => http.post(
          Uri.parse('$_base/students/add/'),
          headers: _headers,
          body: jsonEncode({
            'group_id': groupId,
            ...draft.toJson(confirmNew: confirmNew),
          }),
        ));
    return parseAddStudentResponse(resp, diagnostic: false);
  }

  /// Replays a queued `_offlineKind: 'add_student'` row. Always sends
  /// `confirm_new: true`: the proctor already answered "new child" when the
  /// network was down, and the panel admin sees the server-side duplicate
  /// suggestion anyway. Same `{synced, permanent}` contract as the other
  /// replay helpers; only a 400 (bad name/group) or a boss-rejected child is permanent — 404/405 (old
  /// backend), 429, 5xx, a full pending quota and offline all keep retrying.
  Future<Map<String, dynamic>> submitQueuedAddStudent(
      Map<String, dynamic> payload) async {
    final tempId = (payload['client_temp_id'] ?? '').toString();
    try {
      final birth = DateTime.tryParse((payload['birth_date'] ?? '').toString());
      final result = await addStudent(
        groupId: (payload['group_id'] ?? '').toString(),
        confirmNew: true,
        draft: AddStudentDraft(
          firstName: (payload['first_name'] ?? '').toString(),
          lastName: (payload['last_name'] ?? '').toString(),
          birthDate: birth,
          parentFio: (payload['parent_fio'] ?? '').toString(),
          clientTempId: tempId,
          transferClaim: TransferClaim.tryParse(payload['transfer_claim']),
        ),
      );
      if (tempId.isNotEmpty) {
        await LocalStudentsDb.markSynced(tempId, result.id);
      }
      return {'synced': true};
    } on ApiException catch (e) {
      // 400 = bad name/group; a rejected child never becomes valid again.
      final permanent =
          e.statusCode == 400 || e.code == kAddStudentRejectedCode;
      if (permanent && tempId.isNotEmpty) {
        await LocalStudentsDb.remove(tempId);
      }
      return {'synced': false, 'permanent': permanent};
    } catch (e) {
      debugPrint('submitQueuedAddStudent error: $e');
      return {'synced': false, 'permanent': false};
    }
  }

  Future<String?> fetchGuestPin() async {
    try {
      final data = await _get('/pack/version/') as Map<String, dynamic>;
      return data['guest_pin'] as String?;
    } catch (e) {
      debugPrint('fetchGuestPin error: $e');
      return null;
    }
  }

  Future<List<TestCatalogEntry>> getTestCatalog() async {
    final data = await _get('/tests/catalog/') as List;
    return data
        .map((j) => TestCatalogEntry.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getTestDetail(String testKey) async {
    return await _get('/tests/$testKey/') as Map<String, dynamic>;
  }

  Future<List<TestPackage>> getPackages(int grade) async {
    final data = await _get('/packages/?grade=$grade') as List;
    return data.map((j) => TestPackage.fromJson(j)).toList();
  }

  Future<List<Question>> getQuestions(String packageId, int variant) async {
    final data = await _get('/packages/$packageId/questions/?variant=$variant')
        as Map<String, dynamic>;
    return (data['questions'] as List)
        .map((j) => Question.fromJson(j))
        .toList();
  }

  /// Natijani serverga yuboradi va XP/coins ma'lumotini qaytaradi.
  /// {synced: bool, xp_earned: int, coins_earned: int, total_xp: int, level: int}
  /// Xato holatida `permanent:true` (faqat 400/422 — retry foydasiz) yoki `retryable:true`
  /// (qolgan hamma narsa: 401/403/404/408/413/429, 5xx, HTML javob, tarmoq).
  /// [idempotencyToken] berilsa `Idempotency-Key` header qo'shiladi — flush retry dedup uchun.
  Future<Map<String, dynamic>> submitResultFull(TestResult result,
      {Map<String, dynamic>? detail, String? idempotencyToken}) async {
    try {
      final extraHeaders =
          idempotencyToken != null && idempotencyToken.isNotEmpty
              ? {'Idempotency-Key': idempotencyToken}
              : const <String, String>{};
      final resp = await _post('/results/', result.toJson(detail: detail),
          extraHeaders: extraHeaders);
      // Only the server's receipt (ok / id / duplicate) counts as synced.
      if (!_hasReceipt(resp)) {
        throw const ApiException(200, "Noto'g'ri javob", code: kApiBadResponse);
      }
      // Natija saqlangandan keyin wrong answers yuklaymiz
      final wrongAnswers =
          await _fetchResultDetail(resp['id']?.toString() ?? '');
      return {'synced': true, ...resp, 'wrong_answers': wrongAnswers};
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.code != kApiBadResponse) {
        if (isDuplicateConflict(e.body)) {
          return {
            'synced': true,
            'xp_earned': 0,
            'wrong_answers': <dynamic>[]
          };
        }
        // Rejected (attempt limit etc.): NOT stored. The queue keeps the row
        // in its terminal "rejected" state instead of acking or dropping it.
        return {
          'synced': false,
          'permanent': true,
          'rejected': true,
          'reject_reason': conflictReason(e.body),
          'xp_earned': 0,
          'wrong_answers': <dynamic>[]
        };
      }
      if (isPermanentResultRejection(e.statusCode, code: e.code)) {
        // Server definitively rejected the payload (400 / 422) - retrying
        // can never help, but the finished exam is HELD for the teacher
        // (OfflineQueue `rejected_results`), never silently dropped.
        return {
          'synced': false,
          'permanent': true,
          'rejected': true,
          'reject_reason': resultRejectionReason(e.statusCode, e.body),
          'xp_earned': 0,
          'wrong_answers': <dynamic>[]
        };
      }
      // Everything else (401/403/404/408/413/429, 5xx, HTML bodies, network)
      // is transient from the result's point of view - keep it queued.
      return {
        'synced': false,
        'retryable': true,
        if (e.retryAfter != null) 'retry_after_s': e.retryAfter!.inSeconds,
        'xp_earned': 0,
        'wrong_answers': <dynamic>[]
      };
    } catch (e) {
      debugPrint('submitResultFull unexpected error: $e');
      return {
        'synced': false,
        'retryable': true,
        'xp_earned': 0,
        'wrong_answers': <dynamic>[]
      };
    }
  }

  Future<List<dynamic>> _fetchResultDetail(String resultId) async {
    if (resultId.isEmpty) return [];
    try {
      final data = await _get('/my-results/$resultId/') as Map<String, dynamic>;
      return data['wrong_answers'] as List<dynamic>? ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> submitResult(TestResult result) async {
    final r = await submitResultFull(result);
    return r['synced'] as bool? ?? false;
  }

  /// Lokal/oflayn (login'siz) natijani guest endpointga yuboradi.
  /// Idempotency-Key header orqali token yuboradi — duplikat oldini olish uchun.
  /// Server DB ga saqlaydi VA Telegram ni server tomonda jo'natadi.
  /// HTTP 200 = durabl muvaffaqiyat (telegram_sent=false bo'lsa ham qayta yubormaymiz — dublikat oldini olish).
  /// Katalogni yuklaydi — published testlar ro'yxati.
  /// `client=3` — bu app locked (vaqt-qulflangan) testlarni ham
  /// `locked_until` maydoni bilan qabul qiladi (pre-download uchun); eski
  /// parametrsiz javob xulqiga hech narsa qo'shilmaydi (backend kontrakti).
  /// client=3 = engine inline-reading fix bor (2026-07-14 Sprint 1: list
  /// ichidagi `type:"reading"` render bo'ladi va ball beradi) — min_client=3
  /// bilan belgilangan testlar (Tarix/Ona tili §5, ikkita matn) shu darajadan
  /// past clientlarga katalogda ko'rinmaydi (Sprint 3, katalog gating).
  /// Xato (tarmoq, HTTP >=400, ro'yxat bo'lmagan javob) holatida TASHLAYDI —
  /// bo'sh ro'yxat faqat haqiqiy bo'sh katalogni bildiradi.
  ///
  /// `groupId` — berilsa, backend faqat shu guruhga bog'langan (yoki
  /// guruhsiz, ya'ni hammaga ochiq) testlarni qaytaradi (test↔guruh
  /// bog'lanishi, 2026-07-11). Berilmasa — hozirgidek maktab bo'yicha
  /// (orqaga moslik, eski app versiyalari uchun).
  ///
  /// `schoolCode` — berilsa, backend so'rovchi maktabni shu koddan aniqlaydi
  /// (anonim/token-siz oqimda auth token orqali aniqlanmaydi); maktabga
  /// bog'langan (school FK bor) testlar buni bermasa butunlay ko'rinmaydi.
  ///
  /// `authToken` — berilsa, `Authorization: Bearer <token>` header sifatida
  /// yuboriladi (o'quvchi self-login oqimi, MyTestsScreen). Backend bu holda
  /// `groupId`/`schoolCode`ni e'tiborsiz qoldirib, guruhni JWT orqali
  /// autentifikatsiya qilingan o'quvchining haqiqiy faol guruhidan aniqlaydi
  /// — shuning uchun bu oqimda `groupId` umuman yuborilmaydi (chaqiruvchi
  /// tomonda null qoldiriladi). Proctor oqimi (group_select_screen.dart)
  /// `authToken` bermaydi — xatti-harakati o'zgarishsiz (orqaga moslik).
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    final gid = (groupId != null && groupId.isNotEmpty)
        ? '&group_id=${Uri.encodeComponent(groupId)}'
        : '';
    final sc = (schoolCode != null && schoolCode.isNotEmpty)
        ? '&school_code=${Uri.encodeComponent(schoolCode)}'
        : '';
    // school_id (School.number kolliziyasidan xoli) — berilsa, backend
    // school_code'dan ustun qo'yadi (2026-09-07).
    final sid = (schoolId != null && schoolId.isNotEmpty)
        ? '&school_id=${Uri.encodeComponent(schoolId)}'
        : '';
    // Tarmoq/HTTP (>=400)/parse xatolari ATAYLAB tashlanadi: avval bu yerda
    // `return []` edi va TestCatalogService.refresh() uni "muvaffaqiyatli
    // bo'sh katalog" deb o'qib, butun yuklab olingan keshni tozalab yuborgan
    // (2026-10-28). Faqat haqiqiy 200 + ro'yxat natija qaytaradi.
    final data = await _getCompute('/tests/catalog/?client=3$gid$sc$sid',
        extraHeaders: (authToken != null && authToken.isNotEmpty)
            ? {'Authorization': 'Bearer $authToken'}
            : const {});
    if (data is! List) {
      throw const ApiException(200, 'Katalog javobi ro\'yxat emas');
    }
    if (data.isEmpty) return [];
    return data
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Bitta test JSON'ini yuklaydi. `client=3` — locked testni ham
  /// pre-download qilish uchun ruxsat beradi (UI darajasida qulflangan).
  /// client=3 = engine inline-reading fix bor — qarang fetchTestCatalog izohi.
  ///
  /// `groupId` — berilsa, backend guruhga scoped test uchun shu guruhga
  /// tegishli javobni qaytaradi; boshqa guruh test_key bilan urinsa 403/404
  /// (S-001 xavfsizlik chegarasi, 2026-07-11). Guruhsiz maktab holatida
  /// berilmaydi — orqaga moslik saqlanadi.
  ///
  /// `schoolCode` — berilsa, backend so'rovchi maktabni shu koddan aniqlaydi;
  /// maktabga bog'langan (school FK bor) test bermasa 404 qaytaradi.
  /// Xato holatida null qaytaradi, crash qilmaydi.
  ///
  /// `authToken` — qarang [fetchTestCatalog] izohi: berilsa Bearer header
  /// sifatida yuboriladi va backend `groupId`ni JWT'dagi o'quvchining faol
  /// guruhidan aniqlaydi (self-login oqimi). Proctor chaqiruvlari
  /// (group_select_screen.dart) bu param'ni bermaydi — o'zgarishsiz.
  Future<Map<String, dynamic>?> fetchTest(String testKey,
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    try {
      final gid = (groupId != null && groupId.isNotEmpty)
          ? '&group_id=${Uri.encodeComponent(groupId)}'
          : '';
      final sc = (schoolCode != null && schoolCode.isNotEmpty)
          ? '&school_code=${Uri.encodeComponent(schoolCode)}'
          : '';
      final sid = (schoolId != null && schoolId.isNotEmpty)
          ? '&school_id=${Uri.encodeComponent(schoolId)}'
          : '';
      final data = await _getCompute('/tests/$testKey/?client=3$gid$sc$sid',
          extraHeaders: (authToken != null && authToken.isNotEmpty)
              ? {'Authorization': 'Bearer $authToken'}
              : const {});
      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('fetchTest($testKey) error: $e');
      return null;
    }
  }

  /// GET /my-profile/ — self-login talaba uchun profil xulosasi (maktab nomi,
  /// statistika, so'nggi natijalar). `stats.average_time_seconds` — natija
  /// davomiyligi saqlangan barcha natijalar bo'yicha o'rtacha; hech qaysi
  /// natijada saqlanmagan bo'lsa `null` (eski natijalar uchun kutilgan
  /// holat). `recent_results[].id` — /results/<id>/breakdown/ chaqirig'i
  /// uchun kalit. Backend `student.code`ni FAQAT JWT'dan
  /// aniqlaydi (StudentProfileSummaryView) — bu yerda hech qanday id/kod
  /// yuborilmaydi. Token yo'q/xato bo'lsa 401 qaytaradi.
  ///
  /// Xato yoki tarmoq holatida `null` qaytaradi (fetchTest bilan bir xil
  /// naqsh) — chaqiruvchi buni "ma'lumot yo'q" deb talqin qilib, KPI/profil
  /// blokini butunlay yashirishi kerak, hech qachon nol/soxta qiymat bilan
  /// to'ldirmasligi kerak.
  Future<Map<String, dynamic>?> fetchMyProfile(
      {required String authToken}) async {
    if (authToken.isEmpty) return null;
    try {
      final data = await _get('/my-profile/',
          extraHeaders: {'Authorization': 'Bearer $authToken'});
      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('fetchMyProfile error: $e');
      return null;
    }
  }

  /// GET /messages/ — talaba uchun xabarlar ro'yxati (o'qituvchi/tizim
  /// yozuvlari + backend so'rov vaqtida sintez qiladigan
  /// test_assigned/test_reviewed yozuvlari), eng yangisi birinchi, 50 tagacha.
  /// Xato holatida `[]` qaytaradi (fetchCatalogSchools bilan bir xil naqsh) —
  /// chaqiruvchi buni bo'sh ro'yxat deb ko'rsatishi kerak, crash emas.
  Future<List<Map<String, dynamic>>> fetchMessages(
      {required String authToken}) async {
    if (authToken.isEmpty) return [];
    try {
      final data = await _get('/messages/',
          extraHeaders: {'Authorization': 'Bearer $authToken'});
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('fetchMessages error: $e');
      return [];
    }
  }

  /// PATCH /messages/<id>/read/ — xabarni o'qilgan deb belgilaydi. Faqat
  /// haqiqiy saqlangan yozuvlar (`type` teacher/system, UUID `id`) uchun
  /// chaqiriladi — sintez qilingan test_assigned/test_reviewed yozuvlar
  /// bazada mavjud emas va bu endpoint ularda 404 qaytaradi (chaqiruvchi
  /// oldindan filtrlaydi). Muvaffaqiyatsizlikda [ApiException] tashlaydi —
  /// UI optimistik yangilanishni shu asosda qaytarib oladi.
  Future<void> markMessageRead(
      {required String authToken, required String messageId}) async {
    final resp = await _send(() => http.patch(
          Uri.parse('$_base/messages/$messageId/read/'),
          headers: {..._headers, 'Authorization': 'Bearer $authToken'},
        ));
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, _statusMessage(resp.statusCode));
    }
  }

  /// GET /home-summary/ — "Главная" ekrani uchun: davomat%, streak, oxirgi
  /// natija, shoshilinch testlar, kelgusi dars (agar bo'lsa). Backend
  /// student.code'ni FAQAT JWT'dan aniqlaydi (HomeSummaryView) — hech qanday
  /// id/kod bu yerda yuborilmaydi. Javobdagi `next_lesson` kaliti FAQAT
  /// haqiqiy rejalashtirilgan dars mavjud bo'lsagina keladi (butunlay
  /// yo'q — null emas) — chaqiruvchi buni `containsKey('next_lesson')`
  /// bilan tekshirishi kerak, xuddi [fetchMyProfile]dagi "hech qachon soxta
  /// ma'lumot bilan to'ldirmaslik" konventsiyasi.
  ///
  /// Xato yoki tarmoq holatida `null` qaytaradi — chaqiruvchi butun
  /// ekranni "yuklab bo'lmadi" holatiga o'tkazadi.
  ///
  /// Javobda endi ixtiyoriy `week_progress` kaliti ham bo'lishi mumkin
  /// ({assigned, completed, in_progress, remaining}) — faqat talabaning
  /// faol guruhi bo'lsa keladi, bo'lmasa butunlay yo'q (null emas).
  Future<Map<String, dynamic>?> fetchHomeSummary(
      {required String authToken}) async {
    if (authToken.isEmpty) return null;
    try {
      final data = await _get('/home-summary/',
          extraHeaders: {'Authorization': 'Bearer $authToken'});
      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('fetchHomeSummary error: $e');
      return null;
    }
  }

  /// GET /results/<uuid:result_id>/breakdown/ — bitta natijaning bob/topic/
  /// unit/part yig'indisi + (mavjud bo'lsa) savol-savol tafsiloti
  /// (ResultBreakdownView). `resultId` — RecentResult.id (MonitoringResult
  /// UUID'i).
  ///
  /// 404 backendda IKKI holatda ham qaytadi: natija boshqa talabaniki
  /// (S-003 ownership) YOKI natijaning umuman breakdown ma'lumoti yo'q
  /// (juda eski/legacy submission) — bu ikkisi ataylab farqlanmaydi.
  /// Bu yerda `null` qaytariladi — chaqiruvchi buni "bu natija uchun
  /// batafsil ma'lumot yo'q" deb ko'rsatishi kerak, XATO emas (kutilgan,
  /// keng tarqalgan javob, ayniqsa eski natijalar uchun).
  ///
  /// Tarmoq/server xatosida [ApiException] tashlaydi (fetchMyProfile'dan
  /// farqli — bu yerda 404 allaqachon "ma'lumot yo'q"ni ifodalagani uchun,
  /// haqiqiy xatoni chaqiruvchidan yashirmaslik kerak).
  Future<ResultBreakdown?> fetchResultBreakdown(String resultId,
      {required String authToken}) async {
    if (authToken.isEmpty || resultId.isEmpty) return null;
    final resp = await _send(() => http.get(
          Uri.parse(
              '$_base/results/${Uri.encodeComponent(resultId)}/breakdown/'),
          headers: {..._headers, 'Authorization': 'Bearer $authToken'},
        ));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, _statusMessage(resp.statusCode));
    }
    final data = _decode(resp);
    if (data is! Map) return null;
    return ResultBreakdown.fromJson(Map<String, dynamic>.from(data));
  }

  /// Nashr qilingan testi bor barcha maktablar ro'yxati (kod+nom, kontentsiz).
  /// Anonim katalog (`fetchTestCatalog`, school_code'siz) faqat guruhsiz
  /// global testlarni ko'rsatadi — bu endpoint esa maktabni PIN oqimiga
  /// kirish nuqtasi sifatida ko'rsatish uchun, hatto o'sha maktabning barcha
  /// testlari guruhga bog'langan bo'lsa ham (2026-07-12).
  /// Xato holatida [] qaytaradi, crash qilmaydi — `strict: true` bo'lsa
  /// xatoni tashlaydi (maktab tanlash ekrani "bo'sh" bilan "yuklanmadi"ni
  /// farqlashi uchun).
  Future<List<Map<String, String>>> fetchCatalogSchools(
      {bool strict = false}) async {
    try {
      final data = await _get('/tests/catalog/schools/');
      if (data is! List) {
        throw const ApiException(200, "Noto'g'ri javob", code: kApiBadResponse);
      }
      return data
          .whereType<Map>()
          .map((e) => {
                'school_code': e['school_code']?.toString() ?? '',
                'label': e['label']?.toString() ?? '',
                'school_id': e['school_id']?.toString() ?? '',
              })
          .where((e) => e['school_code']!.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('fetchCatalogSchools error: $e');
      if (strict) rethrow;
      return [];
    }
  }

  /// AI xulosa (TZ §10.4): per-topic natijani yuboradi, tahlil qaytaradi.
  /// {summary, strengths[], weaknesses[], recommendations[], focus_14day[]}.
  /// Offline yoki AI mavjud bo'lmasa null (UI kartani ko'rsatmaydi).
  Future<Map<String, dynamic>?> fetchAiSummary({
    required int grade,
    required int totalPct,
    required List<Map<String, dynamic>> topics,
    String? studentFirstName,
  }) async {
    try {
      return await _post('/result/ai-summary/', {
        'grade': grade,
        'total_pct': totalPct,
        'topics': topics,
        if (studentFirstName != null && studentFirstName.isNotEmpty)
          'student_first_name': studentFirstName,
      });
    } catch (e) {
      debugPrint('fetchAiSummary error: $e');
      return null;
    }
  }

  /// Uploads the app's own generated result HTML (per-topic breakdown, SVG
  /// diagrams, real AI summary) so the parent/teacher Telegram report can
  /// forward this exact file instead of an older-format one built server-side.
  ///
  /// Returns:
  ///   true  — HTML muvaffaqiyatli yuklandi (200 OK)
  ///   false — natija DB ga hali yetmagan (404) — caller qayta urinishi kerak
  ///
  /// Throws [ApiException] / [SocketException] faqat tarmoq xatosida —
  /// caller retry qilmasligi kerak.
  Future<bool> uploadResultHtml(String clientToken, String htmlString) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_base/result/pdf/$clientToken/'),
    )..files.add(http.MultipartFile.fromBytes('file', utf8.encode(htmlString),
        filename: 'result.html'));
    try {
      final streamed = await req.send().timeout(_timeout);
      if (streamed.statusCode == 200) return true;
      if (streamed.statusCode == 404) return false; // natija hali yo'q — retry
      debugPrint('uploadResultHtml unexpected status: ${streamed.statusCode}');
      return false;
    } on TimeoutException {
      throw const ApiException(0, "HTML yuklash vaqti tugadi.");
    } on SocketException {
      throw const ApiException(0, "Internet aloqasi yo'q.");
    }
  }

  /// Xato holatida `permanent:true` (faqat 400/409/422) yoki `retryable:true`
  /// (qolgan hamma narsa) qaytaradi — submitResultFull bilan bir xil
  /// klassifikatsiya ([isPermanentResultRejection]).
  ///
  /// NOTE: `_send()` only ever throws ApiException for network/timeout
  /// failures (always statusCode 0) — real HTTP status codes come back as a
  /// normal Response, so the 4xx/5xx split MUST happen on `resp.statusCode`
  /// directly, not in an `on ApiException catch` block.
  Future<Map<String, dynamic>> submitLocalResultFull(
      Map<String, dynamic> payload, String token) async {
    try {
      final resp = await _send(() => http.post(
            Uri.parse('$_base/result/'),
            headers: {..._headers, 'Idempotency-Key': token},
            body: jsonEncode(payload),
          ));
      return _submitVerdict(resp, 'submitLocalResultFull',
          holdRejected: true);
    } on ApiException {
      // Network/timeout — always retryable, never permanent.
      return {'synced': false, 'permanent': false};
    } catch (e) {
      debugPrint('submitLocalResultFull error: $e');
      return {'synced': false, 'permanent': false};
    }
  }

  /// `{synced, permanent[, retry_after_s]}` for a write answered with [resp].
  /// Synced ONLY for [isSubmitAck]; a 3xx / portal HTML / odd 2xx body is
  /// retryable; 4xx-5xx split by [_permanentReply]; 429 / 503 hand the
  /// server's Retry-After to the sync scheduler.
  ///
  /// [holdRejected] (result payloads only): a 409 is split into "already
  /// stored" (synced) and a rejection; a 400 / 422 is a rejection
  /// (`rejected: true` - the queue keeps it in `rejected_results`).
  Map<String, dynamic> _submitVerdict(http.Response resp, String what,
      {bool holdRejected = false}) {
    if (resp.statusCode >= 400) {
      debugPrint('$what non-2xx: ${resp.statusCode}');
      if (holdRejected &&
          (resp.statusCode == 409 ||
              resp.statusCode == 400 ||
              resp.statusCode == 422) &&
          !_looksLikeHtml(resp)) {
        var body = <String, dynamic>{};
        try {
          final d = jsonDecode(utf8.decode(resp.bodyBytes));
          if (d is Map) body = Map<String, dynamic>.from(d);
        } catch (_) {}
        if (resp.statusCode == 409) {
          if (isDuplicateConflict(body)) return {'synced': true};
          return {
            'synced': false,
            'permanent': true,
            'rejected': true,
            'reject_reason': conflictReason(body),
          };
        }
        // 400 / 422 on a result payload: held too, never dropped.
        return {
          'synced': false,
          'permanent': true,
          'rejected': true,
          'reject_reason': resultRejectionReason(resp.statusCode, body),
        };
      }
      final wait = retryAfterSecondsOf(resp);
      return {
        'synced': false,
        'permanent': _permanentReply(resp),
        if (wait != null) 'retry_after_s': wait,
      };
    }
    if (!isSubmitAck(resp)) {
      debugPrint('$what: ${resp.statusCode} without a receipt, keeping queued');
      return {'synced': false, 'permanent': false};
    }
    return {'synced': true};
  }

  /// Permanent only for a real 400/409/422 from OUR server - an HTML error
  /// page (proxy / captive portal) with the same status is not a verdict.
  bool _permanentReply(http.Response resp) => isPermanentResultRejection(
      resp.statusCode,
      code: _looksLikeHtml(resp) ? kApiBadResponse : null);

  /// Offline navbatdagi (online + lokal) natijalarni qayta yuborishga urinadi.
  /// Qaytaradi: muvaffaqiyatli yuborilgan jami yozuvlar soni.
  Future<int> flushOfflineQueue() async {
    // Whoever calls this decided to flush now (SyncService gates the automatic
    // ticks on the server's Retry-After itself); a fresh answer re-arms it.
    ServerBackoff.clear();
    final online = await OfflineQueue.flush(
      (r, token) => submitResultFull(r, idempotencyToken: token),
    );
    // The server just asked us to wait: the local queue would only hit the
    // same 429 / 503.
    final local = ServerBackoff.active
        ? 0
        : await OfflineQueue.flushLocal(_dispatchLocalQueueItem);
    await OfflineQueue.purgeStale();
    return online + local;
  }

  /// POSTs a single offline-queued "flag a problem with this question"
  /// report (question_report_sheet.dart). Same best-effort posture and
  /// permanent/retryable classification as [submitLocalResultFull] — never
  /// throws to the caller, since [OfflineQueue.flushLocal] expects a
  /// `{'synced': bool, 'permanent': bool}` map back, not an exception.
  Future<Map<String, dynamic>> submitQuestionReport(
      Map<String, dynamic> payload, String token) async {
    try {
      final resp = await _send(() => http.post(
            Uri.parse('$_base/question-report/'),
            headers: {..._headers, 'Idempotency-Key': token},
            body: jsonEncode(payload),
          ));
      return _submitVerdict(resp, 'submitQuestionReport');
    } on ApiException {
      // Network/timeout — always retryable, never permanent.
      return {'synced': false, 'permanent': false};
    } catch (e) {
      debugPrint('submitQuestionReport error: $e');
      return {'synced': false, 'permanent': false};
    }
  }

  /// Routes a `local_queue` row to the right endpoint. Every pre-existing
  /// caller of [OfflineQueue.enqueueLocal] (engine_host_screen.dart,
  /// unit1_runner.dart, interhouse_result_screen.dart, combined_runner.dart,
  /// local_result_screen.dart) enqueues a full TestResult payload bound for
  /// `/result/` and carries no `_offlineKind` key — that stays the default
  /// so rows already sitting in the queue (or enqueued by unmodified call
  /// sites) keep flushing exactly as before this feature. Only rows tagged
  /// `_offlineKind: 'question_report'` (question_report_sheet.dart) are
  /// routed to `/question-report/` instead; the tag itself is stripped
  /// before either payload leaves the device.
  Future<Map<String, dynamic>> _dispatchLocalQueueItem(
      Map<String, dynamic> payload, String token) async {
    if (payload['_offlineKind'] == 'add_student') {
      // Queued "Bola qo'shish" (the network was down); flushed in created-ASC
      // order, i.e. BEFORE any result the child produced meanwhile.
      return submitQueuedAddStudent(payload);
    }
    if (payload['_offlineKind'] == 'question_report') {
      final body = Map<String, dynamic>.from(payload)..remove('_offlineKind');
      return submitQuestionReport(body, token);
    }
    if (payload['_offlineKind'] == 'diagnostic_finish') {
      final answerKey = payload['_offline_answer_key'];
      final subject =
          (answerKey is Map ? answerKey['subject'] : null)?.toString() ?? '';
      // `_offline_answer_key` is a LOCAL-ONLY self-scoring aid (see
      // DiagnosticExportService) — it must never leave the device. Stripped
      // here, at this single central replay choke point, the same way
      // `_offlineKind` itself already is. `subject` is read out of it BEFORE
      // stripping so submitFinishOffline can still recover the real score
      // via kiosk/peek/ if this retry turns out to already be finished.
      final body = Map<String, dynamic>.from(payload)
        ..remove('_offlineKind')
        ..remove('_offline_answer_key');
      final result = await diagnosticKioskApi.submitFinishOffline(body, token,
          subject: subject);
      // Single central replay choke point (both the background auto-flush
      // and any manual "flush now" trigger route through here) — flip the
      // matching diagnostic_history row to 'sent' and backfill its scores,
      // instead of duplicating this at every call site.
      if (result['synced'] == true) {
        final attemptId = (body['attempt_id'] ?? '').toString();
        if (attemptId.isNotEmpty) {
          unawaited(DiagnosticHistoryDb.markSent(
            attemptId: attemptId,
            mathScore: (result['score_math'] as num?)?.toInt(),
            englishScore: (result['score_english'] as num?)?.toInt(),
          ));
        }
      }
      return result;
    }
    // A result produced for a child that was added offline carries the temp
    // id (`new:<uuid>` == client_temp_id). Once the queued add has been
    // accepted, point the result at the real server id; until then (or if the
    // add was dropped) it goes up as-is = an unknown student, exactly as it
    // did before this feature.
    final sid = (payload['student_id'] ?? '').toString();
    if (isLocalNewStudentId(sid)) {
      try {
        final real = await LocalStudentsDb.serverIdFor(sid);
        if (real != null) {
          return submitLocalResultFull({...payload, 'student_id': real}, token);
        }
      } catch (e) {
        debugPrint('flush: temp student id lookup failed: $e');
      }
    }
    return submitLocalResultFull(payload, token);
  }
}

String newIdempotencyToken() => const Uuid().v4();

/// The app-wide API. NOT `final`: opening an offline USB pack swaps in an
/// `OfflinePackageApi` (core/offline/offline_package_api.dart) and closing it
/// restores the online client. Always read through this top-level name — never
/// cache the instance in a field (see TestCatalogService.dynamic).
MonitoringApi api = MonitoringApi();

/// The real client while an offline pack / LAN session has swapped [api]
/// (parked by `OfflinePackSession` / `LanClientSession`, null otherwise).
MonitoringApi? parkedOnlineApi;

/// The client that talks to the REAL server regardless of an open offline
/// session. Use it for "is the server reachable" probes; everything else must
/// keep going through [api] so pack/LAN mode keeps working.
MonitoringApi get onlineApi => parkedOnlineApi ?? api;
