// lib/core/api/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../db/offline_queue.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  // UI da to'g'ridan-to'g'ri ko'rsatish uchun toString faqat tushunarli matnni qaytaradi.
  @override
  String toString() => message;
}

class MonitoringApi {
  static const String _base = 'https://api.alochi.org/api/v1/monitoring';
  static const String _media = 'https://api.alochi.org';

  /// Relative URL'ni absolute'ga o'giradi (rasm URL'lari uchun)
  static String fixImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    final trimmed = url.trim();
    final absolute = trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('//');
    final fullUrl = trimmed.startsWith('//')
        ? 'https:$trimmed'
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
    if (schemeIndex == -1) return Uri.encodeFull(url);

    final hostStart = schemeIndex + 3;
    final pathStart = prefixAndPath.indexOf('/', hostStart);
    if (pathStart == -1) return Uri.encodeFull(url);

    final prefix = prefixAndPath.substring(0, pathStart);
    final path = prefixAndPath.substring(pathStart);
    final normalizedPath =
        path.split('/').where((segment) => segment.isNotEmpty).join('/');

    return Uri.encodeFull(
      '$prefix/${normalizedPath.isEmpty ? '' : normalizedPath}$suffix',
    );
  }

  static const Duration _timeout = Duration(seconds: 20);
  String? _token;

  void setToken(String token) => _token = token;
  void clearToken() => _token = null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

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

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {Map<String, String> extraHeaders = const {}}) async {
    final resp = await _send(() => http.post(
          Uri.parse('$_base$path'),
          headers: {..._headers, ...extraHeaders},
          body: jsonEncode(body),
        ));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(resp.statusCode,
          resp.statusCode >= 500 ? 'Server xatosi' : 'Noto\'g\'ri javob');
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

  Future<dynamic> _get(String path) async {
    final resp = await _send(() => http.get(
          Uri.parse('$_base$path'),
          headers: _headers,
        ));
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, _statusMessage(resp.statusCode));
    }
    return jsonDecode(utf8.decode(resp.bodyBytes));
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

  Future<String?> fetchGuestPin() async {
    try {
      final data = await _get('/pack/version/') as Map<String, dynamic>;
      return data['guest_pin'] as String?;
    } catch (_) {
      return null;
    }
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
  /// Xato holatida `permanent:true` (4xx, retry qilma) yoki `retryable:true` (5xx/network).
  /// [idempotencyToken] berilsa `Idempotency-Key` header qo'shiladi — flush retry dedup uchun.
  Future<Map<String, dynamic>> submitResultFull(TestResult result,
      {Map<String, dynamic>? detail, String? idempotencyToken}) async {
    try {
      final extraHeaders =
          idempotencyToken != null && idempotencyToken.isNotEmpty
              ? {'Idempotency-Key': idempotencyToken}
              : const <String, String>{};
      final resp = await _post('/result/', result.toJson(detail: detail),
          extraHeaders: extraHeaders);
      // Natija saqlangandan keyin wrong answers yuklaymiz
      final wrongAnswers =
          await _fetchResultDetail(resp['id'] as String? ?? '');
      return {'synced': true, ...resp, 'wrong_answers': wrongAnswers};
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        return {'synced': true, 'xp_earned': 0, 'wrong_answers': <dynamic>[]};
      }
      if (e.statusCode >= 400 && e.statusCode < 500) {
        // Permanent client error — server rejected payload, retrying won't help
        return {
          'synced': false,
          'permanent': true,
          'xp_earned': 0,
          'wrong_answers': <dynamic>[]
        };
      }
      // 5xx or network error (statusCode == 0) — transient, retry via queue
      return {
        'synced': false,
        'retryable': true,
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
  /// Katalogni yuklaydi — faqat published testlar ro'yxati.
  /// Xato holatida [] qaytaradi, crash qilmaydi.
  Future<List<Map<String, dynamic>>> fetchTestCatalog() async {
    try {
      final data = await _get('/tests/catalog/');
      if (data is! List) return [];
      if (data.isEmpty) return [];
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('fetchTestCatalog error: $e');
      return [];
    }
  }

  /// Bitta test JSON'ini yuklaydi.
  /// Xato holatida null qaytaradi, crash qilmaydi.
  Future<Map<String, dynamic>?> fetchTest(String testKey) async {
    try {
      final data = await _get('/tests/$testKey/');
      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('fetchTest($testKey) error: $e');
      return null;
    }
  }

  Future<void> pingSession({
    required String sessionId,
    required String testKey,
    required String schoolCode,
    required String name,
    required int variant,
    required String status,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/session/ping/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'session_id': sessionId,
              'test_key': testKey,
              'school_code': schoolCode,
              'name': name,
              'variant': variant,
              'status': status,
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode >= 400) {
        debugPrint('pingSession ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('pingSession error: $e');
    }
  }

  Future<bool> submitLocalResult(
      Map<String, dynamic> payload, String token) async {
    try {
      final resp = await _send(() => http.post(
            Uri.parse('$_base/result/'),
            headers: {..._headers, 'Idempotency-Key': token},
            body: jsonEncode(payload),
          ));
      if (resp.statusCode == 409)
        return true; // idempotency match — already saved
      if (resp.statusCode >= 400) return false;
      return true;
    } on ApiException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Offline navbatdagi (online + lokal) natijalarni qayta yuborishga urinadi.
  /// Qaytaradi: muvaffaqiyatli yuborilgan jami yozuvlar soni.
  Future<int> flushOfflineQueue() async {
    final online = await OfflineQueue.flush(
      (r, token) => submitResultFull(r, idempotencyToken: token),
    );
    final local = await OfflineQueue.flushLocal(submitLocalResult);
    await OfflineQueue.purgeStale();
    return online + local;
  }
}

String newIdempotencyToken() => const Uuid().v4();

final api = MonitoringApi();
