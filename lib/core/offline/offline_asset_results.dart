// lib/core/offline/offline_asset_results.dart
//
// Results of the built-in ("assets") runners in offline USB / LAN mode.
//
// Online they go to `local_queue` and wait for internet. In offline mode that
// queue must NOT be used: the class has no internet, so the results would never
// reach the offline export. Instead the finished result is written -- in the
// student's name, picked from the roster -- to the pack's HMAC chain (USB) or
// handed to the teacher's hub (LAN, via the encrypted outbox until it acks).
// The server stores them unverified: it does not know the assets answer key.
import 'asset_test_keys.dart';
import 'lan_client_session.dart';
import 'offline_content_source.dart';
import 'offline_session.dart';

/// True while a USB pack is open or the app is joined to a teacher's hub.
bool get isOfflineContentMode =>
    OfflinePackSession.isActive || LanClientSession.isActive;

/// The open pack (USB) or joined hub (LAN), or null in normal online mode.
OfflineContentSource? get offlineContentSource =>
    OfflinePackSession.current ?? LanClientSession.current;

/// A roster student picked for an assets run. Only `studentId` / `groupId` /
/// `groupName` reach the result; the names drive the runner's own screens.
class OfflineAssetStudent {
  final String studentId;
  final String groupId;
  final String groupName;
  final String firstName;
  final String lastName;

  const OfflineAssetStudent({
    required this.studentId,
    required this.groupId,
    required this.groupName,
    required this.firstName,
    required this.lastName,
  });

  /// Same split the roster flow uses (student_entry_screen.dart): the first
  /// word is the surname, the rest the given name.
  factory OfflineAssetStudent.fromRoster(
      Map<String, dynamic> student, Map<String, dynamic> group) {
    final parts =
        (student['name'] ?? '').toString().trim().split(RegExp(r'\s+'));
    return OfflineAssetStudent(
      studentId: student['id']?.toString() ?? '',
      groupId: (student['group_id'] ?? group['id'] ?? '').toString(),
      groupName: group['name']?.toString() ?? '',
      lastName: parts.isNotEmpty ? parts.first : '',
      firstName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
    );
  }
}

/// Stable code of a refused offline assets result (internal, log-only).
const String kOfflineStudentRequired = 'offline_student_required';
const String kOfflineUnknownAssetKey = 'offline_unknown_asset_key';
const String kOfflineNotActive = 'offline_not_active';

class OfflineAssetException implements Exception {
  final String code;
  const OfflineAssetException(this.code);
  @override
  String toString() => 'OfflineAssetException($code)';
}

/// The `/result/` body for an assets run in offline mode: [payload] (what the
/// runner builds for the online queue) plus the roster identity and a
/// namespaced `test_key`, set both at the top level and in `detail` (the server
/// and the hub check both). Pure -- no I/O.
Map<String, dynamic> offlineAssetBody({
  required Map<String, dynamic> payload,
  required String testKey,
  required OfflineAssetStudent? student,
  required String schoolCode,
}) {
  if (!kAssetTestKeys.contains(testKey)) {
    throw const OfflineAssetException(kOfflineUnknownAssetKey);
  }
  if (student == null || student.studentId.isEmpty) {
    // No identity, no result: an anonymous row would be refused by the server
    // (`student_invalid`) and the hub, i.e. silently lost.
    throw const OfflineAssetException(kOfflineStudentRequired);
  }
  final body = Map<String, dynamic>.from(payload)
    ..['student_id'] = student.studentId
    ..['group_name'] = student.groupName
    ..['school_code'] = schoolCode
    ..['test_key'] = testKey;
  if (student.groupId.isNotEmpty) body['group_id'] = student.groupId;
  final detail = body['detail'];
  body['detail'] = <String, dynamic>{
    if (detail is Map) ...Map<String, dynamic>.from(detail),
    'test_key': testKey,
  };
  return body;
}

/// Stores one finished assets run. USB: appended to the pack chain. LAN: put in
/// the outbox for the hub. Throws on failure -- the caller shows an honest
/// "not saved" state and retries with the SAME [payload] and [token] (the
/// idempotency key makes the retry safe).
Future<void> recordOfflineAssetResult({
  required Map<String, dynamic> payload,
  required String token,
  required String testKey,
  required OfflineAssetStudent? student,
}) async {
  final source = offlineContentSource;
  if (source == null) throw const OfflineAssetException(kOfflineNotActive);
  final body = offlineAssetBody(
    payload: payload,
    testKey: testKey,
    student: student,
    schoolCode: source.schoolCode,
  );
  await source.recordResult(body, token: token);
}
