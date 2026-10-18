// lib/core/offline/offline_content_source.dart
//
// What the offline diagnostic adapter needs from "the place the pack content
// lives": the open `.alochipack` itself (USB mode, [OfflinePackSession]) or the
// teacher's hub (LAN mode, LanClientSession). One narrow interface keeps the
// two modes from drifting apart.
abstract class OfflineContentSource {
  String get packUuid;
  String get schoolId;
  String get schoolCode;
  List<Map<String, dynamic>> get groups;
  List<Map<String, dynamic>> get students;
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
