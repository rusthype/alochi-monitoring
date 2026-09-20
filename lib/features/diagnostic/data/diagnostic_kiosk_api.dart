// lib/features/diagnostic/data/diagnostic_kiosk_api.dart
//
// Standalone HTTP client for the anonymous kiosk diagnostic flow
// (`/api/v1/diagnostic/...`). Kept separate from `MonitoringApi`
// (core/api/api_client.dart) because that class's `_base`/`_get`/`_post`
// helpers are hardcoded to `/api/v1/monitoring` with no override point —
// this is a small parallel client, isolated from the live-exam/session
// flow on purpose.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../core/api/api_client.dart' show ApiException;
import '../../../core/db/diagnostic_kiosk_cache.dart';

/// Parses one row of `GET kiosk/schools/<id>/classes/` — extracted as a
/// top-level function (rather than inline in `listClasses`) so the new
/// `has_web_test`/`web_test_key` fields are unit-testable without a network
/// mock, same rationale as `compareClassLabels` in
/// diagnostic_class_select_screen.dart.
Map<String, dynamic> parseDiagnosticClassRow(dynamic e) {
  if (e is Map) {
    return {
      'class_label': (e['class_label'] ?? '').toString(),
      'language': (e['language'] ?? 'uz').toString().toLowerCase(),
      'has_web_test': e['has_web_test'] == true,
      'web_test_key': (e['web_test_key'] ?? '').toString(),
    };
  }
  return {
    'class_label': e.toString(),
    'language': 'uz',
    'has_web_test': false,
    'web_test_key': '',
  };
}

/// Classifies a non-2xx `kiosk/finish/` response for `OfflineQueue.flushLocal`'s
/// `{synced, permanent}` contract — extracted as a top-level function so the
/// classification rule is unit-testable without mocking HTTP.
///
/// 2026-09-17 incident (Maktab 56): the old rule treated EVERY non-429 4xx as
/// "permanent" — `OfflineQueue.flushLocal` deletes a "permanent" row
/// immediately, with no further retry. A genuinely transient/unexpected 400
/// (server bug, a guard we don't know about yet, a momentary state race)
/// then silently destroyed a student's real, already-answered English test
/// with no trace anywhere. Only "allaqachon yakunlangan" is safe to treat as
/// permanent — it means this exact attempt+subject already finished
/// successfully (e.g. an earlier retry of this same queued row got through),
/// so dropping it loses nothing. Every other 400 now stays queued and keeps
/// retrying (bounded by OfflineQueue's existing 10-attempt/7-day cap, see
/// purgeStale) instead of vanishing on the first failure.
Map<String, dynamic> classifyFinishOfflineResponse(
    int statusCode, String body) {
  String detail = '';
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) detail = (decoded['detail'] ?? '').toString();
  } catch (_) {
    // Non-JSON body — fall through with detail='', treated as retryable below.
  }
  final isAlreadyFinished = detail.contains('allaqachon yakunlangan');
  final permanent = statusCode != 429 && isAlreadyFinished;
  return {'synced': isAlreadyFinished, 'permanent': permanent};
}

/// Merges a best-effort `kiosk/peek/` recovery result into an
/// already-decided [classified] `{synced, permanent}` verdict — pure and
/// unit-testable on its own so `submitFinishOffline`'s score-recovery logic
/// (see its doc comment) doesn't need an HTTP mock. [peekResult] is `null`
/// when the peek call itself failed/threw (best-effort — never a new
/// failure mode) or wasn't attempted; either that or a peek that didn't
/// come back `finished: true` leaves [classified] unchanged.
Map<String, dynamic> withRecoveredScore(
    Map<String, dynamic> classified, Map<String, dynamic>? peekResult) {
  if (peekResult == null || peekResult['finished'] != true) return classified;
  return {
    ...classified,
    'score_math': peekResult['score_math'],
    'score_english': peekResult['score_english'],
  };
}

class DiagnosticKioskApi {
  // Reads the same API_BASE_URL override as MonitoringApi (api_client.dart)
  // so one --dart-define configures the whole app's backend host.
  static const String _host = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.alochi.org',
  );
  static const String _base = '$_host/api/v1/diagnostic';
  static const Duration _timeout = Duration(seconds: 20);

  Future<http.Response> _send(Future<http.Response> Function() req) async {
    try {
      return await req().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
          0, "Server javob bermayapti. Internetingizni tekshiring.");
    } on SocketException {
      throw const ApiException(0, "Internet aloqasi yo'q.");
    } on HttpException {
      throw const ApiException(0, "Tarmoq xatosi. Qayta urinib ko'ring.");
    } on http.ClientException {
      throw const ApiException(0, "Tarmoq xatosi. Qayta urinib ko'ring.");
    }
  }

  String _statusMessage(int status) {
    if (status == 404) return 'Topilmadi';
    if (status == 429) return "Ko'p urinish, biroz kuting";
    if (status >= 500) return "Server xatosi, keyinroq urinib ko'ring";
    return 'Xato: $status';
  }

  Future<dynamic> _get(String path) async {
    final resp = await _send(() => http.get(Uri.parse('$_base$path')));
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, _statusMessage(resp.statusCode));
    }
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw const ApiException(0, "Noto'g'ri javob");
    }
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final resp = await _send(() => http.post(
          Uri.parse('$_base$path'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(resp.statusCode,
          resp.statusCode >= 500 ? 'Server xatosi' : "Noto'g'ri javob");
    }
    if (resp.statusCode >= 400) {
      final raw = data['detail'] ?? data['message'] ?? '';
      final msg = raw.toString().isNotEmpty
          ? raw.toString()
          : _statusMessage(resp.statusCode);
      throw ApiException(resp.statusCode, msg);
    }
    return data;
  }

  /// Tries the cache for [cacheKey] on a network failure ([e.statusCode] ==
  /// 0, per `_send`'s TimeoutException/SocketException/HttpException/
  /// ClientException mapping) — a real 4xx/5xx from a reachable server is
  /// never masked by stale data. Returns `(rows, fromCache: true)` on a hit,
  /// else rethrows so the caller's existing error UI still applies.
  Future<(List<Map<String, dynamic>>, bool)> _listWithCacheFallback(
    String cacheKey,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    try {
      final rows = await fetch();
      unawaited(DiagnosticKioskCache.save(cacheKey, rows));
      return (rows, false);
    } on ApiException catch (e) {
      if (e.statusCode != 0) rethrow;
      final cached = await DiagnosticKioskCache.load(cacheKey);
      if (cached is List) {
        return (cached.cast<Map<String, dynamic>>(), true);
      }
      rethrow;
    }
  }

  /// `(rows, fromCache)` — `rows`: `[{school_id, school_name,
  /// school_number, kiosk_pin}]`. `fromCache: true` means the live fetch
  /// failed (offline/timeout) and this is the last successfully-cached copy.
  Future<(List<Map<String, dynamic>>, bool)> listSchools() {
    return _listWithCacheFallback('schools', () async {
      final data = await _get('/kiosk/schools/');
      if (data is! List || data.isEmpty) return [];
      return data.cast<Map<String, dynamic>>();
    });
  }

  /// `(rows, fromCache)` — `rows`: `[{class_label, language}]`, defensively
  /// also accepting the old bare `["1-A", "1-B", ...]` shape (rolled-back/
  /// cached backend), defaulting `language` to `'uz'` in that case.
  Future<(List<Map<String, dynamic>>, bool)> listClasses(String schoolId) {
    return _listWithCacheFallback('classes_$schoolId', () async {
      final data = await _get('/kiosk/schools/$schoolId/classes/');
      if (data is! List || data.isEmpty) return [];
      return data.map(parseDiagnosticClassRow).toList();
    });
  }

  /// `(rows, fromCache)` — `rows`: `[{attempt_id, student_name, class_label,
  /// language}]` — never `parent_phone`.
  Future<(List<Map<String, dynamic>>, bool)> listStudents(
      String schoolId, String classLabel) {
    return _listWithCacheFallback('students_${schoolId}_$classLabel', () async {
      final query = Uri.encodeQueryComponent(classLabel);
      final data =
          await _get('/kiosk/schools/$schoolId/students/?class_label=$query');
      if (data is! List || data.isEmpty) return [];
      return data.cast<Map<String, dynamic>>();
    });
  }

  /// Delegates into the (fixed) CAT engine's start flow — loosely-typed
  /// response (first question + attempt_id + position info).
  Future<Map<String, dynamic>> startAttempt({
    required String attemptId,
    required String subject,
  }) {
    return _post('/kiosk/start/', {
      'attempt_id': attemptId,
      'subject': subject,
    });
  }

  /// Side-effect-free peek at a subject's package (2026-09 resilience
  /// backend) — never mutates attempt state, safe to call repeatedly and,
  /// unlike [startAttempt], exempt from the backend's subject-ordering guard
  /// (CATStartView.post 400s a real start-attempt call for subject N+1 until
  /// subject N is completed). Used to warm the diagnostic student-select
  /// screen's prefetch cache for EVERY subject the moment a student is
  /// tapped, including the first one. Returns `{'fixed_variant': false}`
  /// verbatim when the grade/subject isn't fixed-variant delivery — callers
  /// must check that field before trusting the rest of the shape (which
  /// otherwise mirrors a real start response: attempt_id, variant_number,
  /// total_questions, duration_minutes, remaining_seconds, questions, ...).
  Future<Map<String, dynamic>> peekSubject({
    required String attemptId,
    required String subject,
  }) {
    return _post('/kiosk/peek/', {
      'attempt_id': attemptId,
      'subject': subject,
    });
  }

  /// Reports the client's own locally-tracked "seconds actively spent on the
  /// current subject" (2026-09 resilience backend) — best-effort, the caller
  /// decides whether to swallow errors (see the runner screen's
  /// `_pingElapsed`, which does). The server keeps the max of what's already
  /// stored, so [elapsedSeconds] must always be the real running total, never
  /// a delta.
  Future<Map<String, dynamic>> pingElapsed({
    required String attemptId,
    required int elapsedSeconds,
  }) {
    return _post('/kiosk/ping/', {
      'attempt_id': attemptId,
      'elapsed_seconds': elapsedSeconds,
    });
  }

  /// `{exchange_code}` — starts the web-test bridge session for a class
  /// whose row had `has_web_test: true`. Per the S-003 fix, the backend no
  /// longer returns a raw JWT here (never wanted in a URL) — only an opaque
  /// exchange code that `student-web-test`'s frontend redeems for the real
  /// token itself. 404 (`{"detail": "Topilmadi"}`) covers every failure
  /// reason (wrong school/class, inactive session, unknown attempt)
  /// collapsed for security — never distinguished client-side.
  Future<String> webTestStart({
    required String attemptId,
    required String testKey,
  }) async {
    final result = await _post('/kiosk/web-test/start/', {
      'attempt_id': attemptId,
      'test_key': testKey,
    });
    return (result['exchange_code'] ?? '').toString();
  }

  /// `{subjects: [...], config: {...}}` — `language` is always appended;
  /// the backend tolerates/normalizes any value and never requires it.
  Future<Map<String, dynamic>> availableSubjects(int grade,
      {String language = 'uz'}) async {
    final data = await _get('/cat/subjects/?grade=$grade&language=$language');
    if (data is Map<String, dynamic>) return data;
    return const {};
  }

  /// Finishes a fixed-variant/full-package attempt in one shot — the local
  /// nav flow answers all questions client-side then submits the whole
  /// batch, instead of one `submitAnswer` round-trip per question.
  Future<Map<String, dynamic>> finishAttempt({
    required String attemptId,
    required List<Map<String, dynamic>> answers,
  }) {
    return _post('/kiosk/finish/', {
      'attempt_id': attemptId,
      'answers': answers,
    });
  }

  /// Retries a queued [finishAttempt] payload from `OfflineQueue.flushLocal`
  /// (`_offlineKind: 'diagnostic_finish'`, see api_client.dart's
  /// `_dispatchLocalQueueItem`) — returns the `{synced, permanent}` shape
  /// that contract expects instead of throwing, same posture as
  /// `MonitoringApi.submitQuestionReport`. On success, also passes through
  /// the response's nullable `score_math`/`score_english` fields so the
  /// caller can backfill `DiagnosticHistoryDb` at the single replay choke
  /// point instead of re-fetching them.
  ///
  /// When the retry hits the "already yakunlangan" 400 (this exact
  /// finish call already succeeded server-side before an earlier response
  /// was lost — see `classifyFinishOfflineResponse`'s doc comment), that
  /// 400 body carries no score data. [subject] (the finish call's subject,
  /// threaded through by `api_client.dart`'s `_dispatchLocalQueueItem` from
  /// the offline queue row's `_offline_answer_key`) lets this method make
  /// one best-effort recovery call to `kiosk/peek/` — which already returns
  /// the real `score_math`/`score_english` for a subject that's in
  /// `attempt.subjects_completed` (`KioskPeekView`, views_kiosk.py) — so the
  /// caller's `markSent()` backfills the real score instead of null. Purely
  /// best-effort: a failed peek falls back to today's no-score behavior,
  /// never turning a correct "stop retrying" verdict into a retry loop.
  Future<Map<String, dynamic>> submitFinishOffline(
      Map<String, dynamic> payload, String token,
      {String subject = ''}) async {
    try {
      final resp = await _send(() => http.post(
            Uri.parse('$_base/kiosk/finish/'),
            headers: {
              'Content-Type': 'application/json',
              'Idempotency-Key': token,
            },
            body: jsonEncode(payload),
          ));
      if (resp.statusCode >= 400) {
        final classified =
            classifyFinishOfflineResponse(resp.statusCode, resp.body);
        if (classified['synced'] == true && subject.isNotEmpty) {
          final attemptId = (payload['attempt_id'] ?? '').toString();
          if (attemptId.isNotEmpty) {
            Map<String, dynamic>? peek;
            try {
              peek = await peekSubject(attemptId: attemptId, subject: subject);
            } catch (_) {
              // Best-effort recovery only — see the doc comment above.
            }
            return withRecoveredScore(classified, peek);
          }
        }
        return classified;
      }
      Map<String, dynamic> data = const {};
      try {
        data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        // Non-JSON success body — still synced, just no score backfill.
      }
      return {
        'synced': true,
        'score_math': data['score_math'],
        'score_english': data['score_english'],
      };
    } on ApiException {
      return {'synced': false, 'permanent': false};
    } catch (e) {
      return {'synced': false, 'permanent': false};
    }
  }

  /// EXISTING, unmodified backend endpoint.
  Future<Map<String, dynamic>> submitAnswer({
    required String attemptId,
    required String questionId,
    required String selected,
  }) {
    return _post('/cat/answer/', {
      'attempt_id': attemptId,
      'question_id': questionId,
      'selected': selected,
    });
  }
}

final diagnosticKioskApi = DiagnosticKioskApi();
