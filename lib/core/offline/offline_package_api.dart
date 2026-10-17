// lib/core/offline/offline_package_api.dart
//
// `MonitoringApi` served from the open `.alochipack` instead of the network.
// Installed as the global `api` by OfflinePackSession.open().
//
//  * Roster/catalog/test-body reads come from the pack (no answer key in it).
//  * There is no login: the roster picker (group -> student) is the identity,
//    and the student's `id` (UUID) is what rides in the result payload — the
//    server resolves identity by `Student.id`, not by the printed code.
//  * Result "submits" append to the pack's HMAC chain.
//  * Everything that would touch the network (pings, heartbeats, proctor
//    frames, crash/report uploads, queue flush) is a no-op, so nothing leaves
//    the machine and nothing hangs waiting for a timeout.
import 'dart:typed_data';

import '../api/api_client.dart';
import '../models/models.dart';
import '../models/test_catalog.dart';
import 'offline_errors.dart';
import 'offline_session.dart';

class OfflinePackageApi extends MonitoringApi {
  final OfflinePackSession session;
  OfflinePackageApi(this.session);

  /// Internal (English, log-only) text + stable `code`; the UI maps the code
  /// to a localized string (l10n.usbErrUnsupported).
  static const ApiException _offline = ApiException(
      0, 'offline pack mode: operation not available',
      code: kOfflineUnsupported);

  // ── identity / health: nothing to authenticate, nothing to ping ─────────────

  @override
  Future<StudentSession> login(String username, String password) async =>
      throw _offline;

  @override
  Future<bool> ping() async => false;

  @override
  Future<bool> pingHealth(
          {Duration timeout = const Duration(seconds: 2)}) async =>
      false;

  @override
  Future<bool> uploadCrashReport(String jsonBody) async => false;

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
    String? localIp,
    String? machineId,
    String? macAddress,
    List<String>? capabilities,
  }) async =>
      const <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> sessionResume(String testKey) async =>
      const <String, dynamic>{'exists': false};

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
  }) async =>
      const <String, dynamic>{};

  @override
  Future<bool> uploadResultHtml(String clientToken, String htmlString) async =>
      false;

  /// Pre-existing queued rows (from earlier ONLINE use) must never be drained
  /// into this pack: they may belong to another school and would poison the
  /// whole `.alochires`. They simply wait for the next online session.
  @override
  Future<int> flushOfflineQueue() async => 0;

  // ── roster ─────────────────────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> fetchGroups(String schoolCode,
      {String? schoolId}) async {
    final groups = session.pack.groups;
    if (groups.isEmpty) return [];
    return groups
        .map((g) => <String, dynamic>{
              'id': g['id']?.toString() ?? '',
              'name': g['name']?.toString() ?? '',
              'display': g['name']?.toString() ?? '',
              'grade': g['grade'],
            })
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId) async {
    final students = session.pack.students;
    if (students.isEmpty) return [];
    return students
        .where((s) => s['group_id']?.toString() == groupId)
        .map((s) => <String, dynamic>{
              // `id` (UUID) is what the engine sends as payload.student_id.
              // `student_code` is deliberately NOT set: the picker would
              // prefer it over `id` (student_entry_screen._startTest) and the
              // server looks students up by UUID.
              'id': s['id']?.toString() ?? '',
              'name': s['name']?.toString() ?? '',
              'code': s['code']?.toString() ?? '',
              'group_id': s['group_id']?.toString() ?? '',
            })
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchDownloads(String schoolCode) async =>
      [];

  @override
  Future<String?> fetchGuestPin() async => null;

  // ── tests ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _catalogItem(Map<String, dynamic> t) {
    final c = t['catalog'];
    return <String, dynamic>{
      if (c is Map) ...Map<String, dynamic>.from(c),
      'test_key': t['key']?.toString() ?? '',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    final tests = session.testsOfType('test');
    if (tests.isEmpty) return [];
    return tests.map(_catalogItem).where((item) {
      // group_ids empty = every group of the school (see offline_pack.py).
      final ids = item['group_ids'];
      if (groupId == null || groupId.isEmpty) return true;
      if (ids is! List || ids.isEmpty) return true;
      return ids.map((e) => e.toString()).contains(groupId);
    }).toList();
  }

  @override
  Future<Map<String, dynamic>?> fetchTest(String testKey,
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    final t = session.testByKey(testKey);
    final data = t?['data'];
    if (t == null || t['type'] != 'test' || data is! Map) return null;
    return Map<String, dynamic>.from(data);
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
      throw const ApiException(404, 'not found in pack',
          code: kOfflineNotFound);
    }
    return data;
  }

  // Legacy MonitoringPackage variants: key "package:<id>:v<variant>".
  static final RegExp _pkgKey = RegExp(r'^package:(.+):v(\d+)$');

  @override
  Future<List<TestPackage>> getPackages(int grade) async {
    final byId = <String, Map<String, dynamic>>{};
    final variants = <String, int>{};
    for (final t in session.testsOfType('package')) {
      final m = _pkgKey.firstMatch(t['key']?.toString() ?? '');
      if (m == null) continue;
      final id = m.group(1)!;
      variants[id] = (variants[id] ?? 0) + 1;
      final c = t['catalog'];
      byId.putIfAbsent(
          id,
          () => <String, dynamic>{
                if (c is Map) ...Map<String, dynamic>.from(c),
                'id': id,
              });
    }
    if (byId.isEmpty) return [];
    return byId.entries
        .map((e) => TestPackage.fromJson({
              ...e.value,
              'variant_count': variants[e.key] ?? 1,
            }))
        .where((p) => p.grade == grade)
        .toList();
  }

  @override
  Future<List<Question>> getQuestions(String packageId, int variant) async {
    final t = session.testByKey('package:$packageId:v$variant');
    final data = t?['data'];
    final qs = data is Map ? data['questions'] : null;
    if (qs is! List || qs.isEmpty) return [];
    return qs
        .whereType<Map>()
        .map((j) => Question.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  // ── results ────────────────────────────────────────────────────────────────

  /// Legacy package result: stored in the chain as-is. The server re-scores
  /// whatever it can resolve and marks the rest unverified.
  @override
  Future<Map<String, dynamic>> submitResultFull(TestResult result,
      {Map<String, dynamic>? detail, String? idempotencyToken}) async {
    try {
      await session.recordResult({
        ...result.toJson(detail: detail),
        'source': 'flutter',
        'school_code': session.pack.schoolCode,
        'test_key': 'package:${result.packageId}:v${result.variant}',
        'pct': result.totalPct,
      }, token: idempotencyToken);
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
        'error': e.toString(),
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
      return {'synced': false, 'permanent': false, 'error': e.toString()};
    }
  }
}
