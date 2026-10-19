// lib/core/offline/lan_client_api.dart
//
// `MonitoringApi` served by the teacher's LAN hub instead of the internet.
// Installed as the global `api` by LanClientSession.activate().
//
//  * Roster/catalog/test bodies come from the hub (`GET /groups`, ...). The
//    hub's pack has no answer key, and nothing is scored here or there.
//  * Results are written to the encrypted outbox (LanClientSession) and
//    delivered to the hub in the background until it acknowledges them.
//  * Pings and screen frames go to the hub, whose replies carry the teacher's
//    pause / extra-time / finish commands in the shape
//    HeartbeatService.reconcileProctorState already understands.
//  * Everything that would touch the internet (login, crash/report uploads,
//    online queue flush) is a no-op or an explicit "unsupported".
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../models/test_catalog.dart';
import '../security/incident_log.dart';
import 'lan_client_session.dart';
import 'offline_errors.dart';
import 'offline_package_api.dart';

class LanClientApi extends MonitoringApi {
  @override
  bool get isLan => true;

  final LanClientSession session;
  LanClientApi(this.session);

  static const ApiException _unsupported = ApiException(
      0, 'lan mode: operation not available',
      code: kOfflineUnsupported);

  // ── identity / health ──────────────────────────────────────────────────────

  @override
  Future<StudentSession> login(String username, String password) async =>
      throw _unsupported;

  /// "Is the network usable": here, "does the hub answer".
  @override
  Future<bool> ping() => session.health();

  @override
  Future<bool> pingHealth(
          {Duration timeout = const Duration(seconds: 2)}) async =>
      false;

  @override
  Future<bool> uploadCrashReport(String jsonBody) async => false;

  @override
  Future<bool> uploadResultHtml(String clientToken, String htmlString) async =>
      false;

  @override
  Future<Map<String, dynamic>?> fetchAiSummary({
    required int grade,
    required int totalPct,
    required List<Map<String, dynamic>> topics,
    String? studentFirstName,
  }) async =>
      null;

  @override
  Future<List<Map<String, dynamic>>> fetchDownloads(String schoolCode) async =>
      [];

  @override
  Future<String?> fetchGuestPin() async => null;

  /// Online queue rows (possibly another school's) must never be sent to a
  /// hub; they wait for the next online session. LAN results use the outbox.
  @override
  Future<int> flushOfflineQueue() => session.flushOutbox();

  // ── proctoring ─────────────────────────────────────────────────────────────

  @override
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
    // Same fields the online ping sends, minus the bulky `answers` (the hub
    // does not need them) plus a live incident count for the teacher.
    final body = <String, dynamic>{
      'session_id': sessionId,
      'name': name,
      'test_key': testKey,
      'status': status,
      if (studentCode != null && studentCode.isNotEmpty)
        'student_code': studentCode,
      'tab_switch_count': tabSwitchCount,
      if (currentQuestionIndex != null)
        'current_question_index': currentQuestionIndex,
      if (totalQuestions != null) 'total_questions': totalQuestions,
      if (elapsedSeconds != null) 'elapsed_seconds': elapsedSeconds,
      if (remainingSeconds != null) 'remaining_seconds': remainingSeconds,
      if (deviceName != null && deviceName.isNotEmpty)
        'device_name': deviceName,
      if (capabilities != null && capabilities.isNotEmpty)
        'capabilities': capabilities,
      'incident_count': IncidentLog.instance.snapshot.length,
    };
    final resp = await session.request('POST', '/ping',
        body: utf8.encode(jsonEncode(body)),
        headers: const {'content-type': 'application/json'},
        timeout: const Duration(seconds: 4));
    if (resp.statusCode != 200) return const <String, dynamic>{};
    final d = jsonDecode(utf8.decode(resp.bodyBytes));
    return d is Map ? Map<String, dynamic>.from(d) : const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> sessionResume(String testKey) async =>
      const <String, dynamic>{'exists': false};

  /// Best effort like the online one: any failure is an empty map ("no panel
  /// action"). The JPEG travels as the raw body; the metadata as query fields
  /// (no multipart parser needed on the hub).
  @override
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
      final resp = await session.request('POST', '/frame',
          query: {
            'session_id': sessionId,
            'focus': focus.toString(),
            'monitor_count': monitorCount.toString(),
            if (monitorIndex != null)
              'monitor_index': monitorIndex.clamp(0, 31).toString(),
            'frame_type': frameType == 'patch' ? 'patch' : 'keyframe',
            if (questionIndex != null) 'q_idx': questionIndex.toString(),
            if (totalQuestions != null) 'total': totalQuestions.toString(),
          },
          body: jpeg,
          headers: const {'content-type': 'image/jpeg'},
          timeout: const Duration(seconds: 5));
      if (resp.statusCode != 200) return const <String, dynamic>{};
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      return d is Map
          ? Map<String, dynamic>.from(d)
          : const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  // ── roster ─────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _maps(Object? d) => d is List
      ? d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchGroups(String schoolCode,
      {String? schoolId}) async {
    return _maps(await session.getJson('/groups'));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId) async {
    return _maps(
        await session.getJson('/students', query: {'group_id': groupId}));
  }

  // ── tests ──────────────────────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    return _maps(await session.getJson('/catalog',
        query: {
          if (groupId != null && groupId.isNotEmpty) 'group_id': groupId,
        },
        inIsolate: true));
  }

  /// Test body + its images (pulled from the hub before returning, so the
  /// engine never paints a missing picture). Null on any failure, like the
  /// online fetch.
  @override
  Future<Map<String, dynamic>?> fetchTest(String testKey,
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    try {
      final d = await session.getJson('/test',
          query: {'key': testKey},
          timeout: const Duration(seconds: 30),
          inIsolate: true,
          maxBytes: kLanMaxBigJson);
      if (d is! Map) return null;
      final data = Map<String, dynamic>.from(d);
      await session.prepareMedia(data);
      return data;
    } catch (e) {
      debugPrint('LanClientApi.fetchTest failed (${e.runtimeType})');
      return null;
    }
  }

  @override
  Future<List<TestCatalogEntry>> getTestCatalog() async {
    final items = await fetchTestCatalog();
    if (items.isEmpty) return [];
    return items.map(TestCatalogEntry.fromJson).toList();
  }

  @override
  Future<Map<String, dynamic>> getTestDetail(String testKey) async {
    final data = await fetchTest(testKey);
    if (data == null) {
      throw const ApiException(404, 'not found on hub', code: kOfflineNotFound);
    }
    return data;
  }

  @override
  Future<List<TestPackage>> getPackages(int grade) async {
    final items = _maps(await session.getJson('/packages'));
    if (items.isEmpty) return [];
    return items
        .map(TestPackage.fromJson)
        .where((p) => p.grade == grade)
        .toList();
  }

  @override
  Future<List<Question>> getQuestions(String packageId, int variant) async {
    final Object? d;
    try {
      d = await session.getJson('/package_questions',
          query: {'id': packageId, 'variant': variant.toString()},
          maxBytes: kLanMaxBigJson);
    } on ApiException catch (e) {
      if (e.code == kOfflineNotFound) return []; // no such variant in the pack
      rethrow;
    }
    final qs = d is Map ? d['questions'] : null;
    if (qs is! List || qs.isEmpty) return [];
    return qs
        .whereType<Map>()
        .map((j) => Question.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  // ── results ────────────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> submitResultFull(TestResult result,
      {Map<String, dynamic>? detail, String? idempotencyToken}) async {
    try {
      await session.recordResult(
          OfflinePackageApi.legacyResultPayload(result, session.schoolCode,
              detail: detail),
          token: idempotencyToken);
      return {
        'synced': true,
        'offline_saved': true,
        'xp_earned': 0,
        'wrong_answers': <dynamic>[],
      };
    } catch (e) {
      // Surfaced, not swallowed: the caller must know the result was NOT kept.
      return {
        'synced': false,
        'retryable': true,
        'error': e.runtimeType.toString(),
        'xp_earned': 0,
        'wrong_answers': <dynamic>[],
      };
    }
  }

  @override
  Future<Map<String, dynamic>> submitLocalResultFull(
      Map<String, dynamic> payload, String token) async {
    try {
      await session.recordResult(payload, token: token);
      return {'synced': true, 'offline_saved': true};
    } catch (e) {
      return {
        'synced': false,
        'permanent': false,
        'error': e.runtimeType.toString()
      };
    }
  }
}
