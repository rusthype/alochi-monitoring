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

  /// `["1-A", "1-B", ...]`
  Future<List<String>> listClasses(String schoolId) async {
    final data = await _get('/kiosk/schools/$schoolId/classes/');
    if (data is! List || data.isEmpty) return [];
    return data.map((e) => e.toString()).toList();
  }

  /// `[{attempt_id, student_name, class_label}]` — never `parent_phone`.
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

  /// EXISTING, unmodified backend endpoint — `{subjects: [...], config: {...}}`.
  Future<Map<String, dynamic>> availableSubjects(int grade) async {
    final data = await _get('/cat/subjects/?grade=$grade');
    if (data is Map<String, dynamic>) return data;
    return const {};
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
