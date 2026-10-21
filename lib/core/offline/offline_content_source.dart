// lib/core/offline/offline_content_source.dart
//
// What the offline diagnostic adapter needs from "the place the pack content
// lives": the open `.alochipack` itself (USB mode, [OfflinePackSession]) or the
// teacher's hub (LAN mode, LanClientSession). One narrow interface keeps the
// two modes from drifting apart.
import '../models/add_student.dart';

abstract class OfflineContentSource {
  String get packUuid;
  String get schoolId;
  String get schoolCode;
  List<Map<String, dynamic>> get groups;
  List<Map<String, dynamic>> get students;

  /// Children a proctor added on THIS computer ("Bola qo'shish"): roster-shaped
  /// rows (`id` = `new:<uuid>`, `group_id`, `first_name`, `last_name`,
  /// `pending: true`, ...). They are never part of [students] (the pack roster
  /// is fixed/signed). LAN clients have none.
  List<Map<String, dynamic>> get localStudents;

  /// Adds a child to the open pack (USB mode only); throws
  /// [SimilarStudentsException] ("Bu shumi?") unless [confirmNew].
  Future<AddStudentResult> addLocalStudent({
    required String groupId,
    required AddStudentDraft draft,
    bool confirmNew = false,
    String language = '',
  });
  List<Map<String, dynamic>> testsOfType(String type);

  /// 1-based ordinal that makes the idempotency key of a repeat attempt unique
  /// (`<keyPrefix><ordinal>`); must not repeat for a genuine retake.
  Future<int> nextAttemptOrdinal(String keyPrefix);

  /// Whether at least one result whose idempotency key starts with
  /// [keyPrefix] is already stored (exported or not). Drives the roster's
  /// "done" marker; a source without a local chain answers false.
  Future<bool> hasAttempt(String keyPrefix);

  /// Stores one finished result (chain row in USB mode, hub outbox in LAN).
  Future<void> recordResult(Map<String, dynamic> payload, {String? token});

  /// Makes sure every image referenced by [data] can be read from disk before
  /// the content is shown. A no-op when the images are already local.
  Future<void> prepareMedia(Object? data);
}
