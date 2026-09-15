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

class DiagnosticKioskApi {
  static const String _base = 'https://api.alochi.org/api/v1/diagnostic';
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

  /// `[{school_id, school_name, school_number, kiosk_pin}]`
  Future<List<Map<String, dynamic>>> listSchools() async {
    final data = await _get('/kiosk/schools/');
    if (data is! List || data.isEmpty) return [];
    return data.cast<Map<String, dynamic>>();
  }

  /// `[{class_label, language}]` — defensively also accepts the old bare
  /// `["1-A", "1-B", ...]` shape (rolled-back/cached backend), defaulting
  /// `language` to `'uz'` in that case.
  Future<List<Map<String, dynamic>>> listClasses(String schoolId) async {
    final data = await _get('/kiosk/schools/$schoolId/classes/');
    if (data is! List || data.isEmpty) return [];
    return data.map(parseDiagnosticClassRow).toList();
  }

  /// `[{attempt_id, student_name, class_label, language}]` — never
  /// `parent_phone`.
  Future<List<Map<String, dynamic>>> listStudents(
      String schoolId, String classLabel) async {
    final query = Uri.encodeQueryComponent(classLabel);
    final data =
        await _get('/kiosk/schools/$schoolId/students/?class_label=$query');
    if (data is! List || data.isEmpty) return [];
    return data.cast<Map<String, dynamic>>();
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
