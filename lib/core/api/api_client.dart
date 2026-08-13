// lib/core/api/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../models/test_catalog.dart';
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
        : trimmed.startsWith('http://')
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

  Future<dynamic> _get(String path,
      {Map<String, String> extraHeaders = const {}}) async {
    final resp = await _send(() => http.get(
          Uri.parse('$_base$path'),
          headers: {..._headers, ...extraHeaders},
        ));
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, _statusMessage(resp.statusCode));
    }
    return jsonDecode(utf8.decode(resp.bodyBytes));
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
    return compute(jsonDecode, utf8.decode(resp.bodyBytes));
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
    });
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

  Future<List<Map<String, dynamic>>> fetchGroups(String schoolCode) async {
    try {
      final resp = await _send(() => http.get(
            Uri.parse(
                '$_base/groups/?school=${Uri.encodeComponent(schoolCode)}'),
            headers: _headers,
          ));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data is! List) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (e) {
      debugPrint('fetchGroups error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchStudents(String groupId) async {
    try {
      final resp = await _send(() => http.get(
            Uri.parse(
                '$_base/groups/${Uri.encodeComponent(groupId)}/students/'),
            headers: _headers,
          ));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data is! List) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (e) {
      debugPrint('fetchStudents error: $e');
      rethrow;
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
  /// Xato holatida `permanent:true` (4xx, retry qilma) yoki `retryable:true` (5xx/network).
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
      // Natija saqlangandan keyin wrong answers yuklaymiz
      final wrongAnswers =
          await _fetchResultDetail(resp['id'] as String? ?? '');
      return {'synced': true, ...resp, 'wrong_answers': wrongAnswers};
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        return {'synced': true, 'xp_earned': 0, 'wrong_answers': <dynamic>[]};
      }
      if (e.statusCode == 429) {
        // Rate-limited, not rejected — a school-wide NAT IP can share the
        // monitoring_submit throttle across ~20-30 concurrently-finishing
        // students. Treating this as permanent (like a real 4xx payload
        // rejection) silently DROPPED the result from the offline queue
        // instead of retrying it (2026-07-21 fix).
        return {
          'synced': false,
          'retryable': true,
          'xp_earned': 0,
          'wrong_answers': <dynamic>[]
        };
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
  /// Katalogni yuklaydi — published testlar ro'yxati.
  /// `client=3` — bu app locked (vaqt-qulflangan) testlarni ham
  /// `locked_until` maydoni bilan qabul qiladi (pre-download uchun); eski
  /// parametrsiz javob xulqiga hech narsa qo'shilmaydi (backend kontrakti).
  /// client=3 = engine inline-reading fix bor (2026-07-14 Sprint 1: list
  /// ichidagi `type:"reading"` render bo'ladi va ball beradi) — min_client=3
  /// bilan belgilangan testlar (Tarix/Ona tili §5, ikkita matn) shu darajadan
  /// past clientlarga katalogda ko'rinmaydi (Sprint 3, katalog gating).
  /// Xato holatida [] qaytaradi, crash qilmaydi.
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
      {String? groupId, String? schoolCode, String? authToken}) async {
    try {
      final gid = (groupId != null && groupId.isNotEmpty)
          ? '&group_id=${Uri.encodeComponent(groupId)}'
          : '';
      final sc = (schoolCode != null && schoolCode.isNotEmpty)
          ? '&school_code=${Uri.encodeComponent(schoolCode)}'
          : '';
      final data = await _getCompute('/tests/catalog/?client=3$gid$sc',
          extraHeaders: (authToken != null && authToken.isNotEmpty)
              ? {'Authorization': 'Bearer $authToken'}
              : const {});
      if (data is! List) return [];
      if (data.isEmpty) return [];
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('fetchTestCatalog error: $e');
      return [];
    }
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
      {String? groupId, String? schoolCode, String? authToken}) async {
    try {
      final gid = (groupId != null && groupId.isNotEmpty)
          ? '&group_id=${Uri.encodeComponent(groupId)}'
          : '';
      final sc = (schoolCode != null && schoolCode.isNotEmpty)
          ? '&school_code=${Uri.encodeComponent(schoolCode)}'
          : '';
      final data = await _getCompute('/tests/$testKey/?client=3$gid$sc',
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
  /// statistika, so'nggi natijalar). Backend `student.code`ni FAQAT JWT'dan
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
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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

  /// Nashr qilingan testi bor barcha maktablar ro'yxati (kod+nom, kontentsiz).
  /// Anonim katalog (`fetchTestCatalog`, school_code'siz) faqat guruhsiz
  /// global testlarni ko'rsatadi — bu endpoint esa maktabni PIN oqimiga
  /// kirish nuqtasi sifatida ko'rsatish uchun, hatto o'sha maktabning barcha
  /// testlari guruhga bog'langan bo'lsa ham (2026-07-12).
  /// Xato holatida [] qaytaradi, crash qilmaydi.
  Future<List<Map<String, String>>> fetchCatalogSchools() async {
    try {
      final data = await _get('/tests/catalog/schools/');
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((e) => {
                'school_code': e['school_code']?.toString() ?? '',
                'label': e['label']?.toString() ?? '',
              })
          .where((e) => e['school_code']!.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('fetchCatalogSchools error: $e');
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

  /// Xato holatida `permanent:true` (4xx, retry qilma) yoki `retryable:true`
  /// (5xx/network) qaytaradi — submitResultFull bilan bir xil klassifikatsiya.
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
      if (resp.statusCode >= 400) {
        debugPrint('submitLocalResultFull non-2xx: ${resp.statusCode}');
        // 429 is a rate limit, not a payload rejection — must stay
        // retryable, same fix as submitResultFull above.
        final permanent = resp.statusCode != 429 && resp.statusCode < 500;
        return {'synced': false, 'permanent': permanent};
      }
      return {'synced': true};
    } on ApiException {
      // Network/timeout — always retryable, never permanent.
      return {'synced': false, 'permanent': false};
    } catch (e) {
      debugPrint('submitLocalResultFull error: $e');
      return {'synced': false, 'permanent': false};
    }
  }

  /// Offline navbatdagi (online + lokal) natijalarni qayta yuborishga urinadi.
  /// Qaytaradi: muvaffaqiyatli yuborilgan jami yozuvlar soni.
  Future<int> flushOfflineQueue() async {
    final online = await OfflineQueue.flush(
      (r, token) => submitResultFull(r, idempotencyToken: token),
    );
    final local = await OfflineQueue.flushLocal(_dispatchLocalQueueItem);
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
      if (resp.statusCode >= 400) {
        debugPrint('submitQuestionReport non-2xx: ${resp.statusCode}');
        // 429 is a rate limit, not a payload rejection — must stay
        // retryable, same fix as submitResultFull/submitLocalResultFull.
        final permanent = resp.statusCode != 429 && resp.statusCode < 500;
        return {'synced': false, 'permanent': permanent};
      }
      return {'synced': true};
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
    if (payload['_offlineKind'] == 'question_report') {
      final body = Map<String, dynamic>.from(payload)..remove('_offlineKind');
      return submitQuestionReport(body, token);
    }
    return submitLocalResultFull(payload, token);
  }
}

String newIdempotencyToken() => const Uuid().v4();

final api = MonitoringApi();
