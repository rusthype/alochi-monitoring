// lib/core/services/add_student_service.dart
//
// "Bola qo'shish" for the monitoring roster: try the server, and when it
// cannot be reached (or is an older backend without the endpoint) keep the
// child usable locally and flush later.
//
// Offline design (wave 1 = online client + this local queue; wave 2 = USB pack):
//  * the temp id is the `client_temp_id` (`new:<uuid>`), generated once per add
//    attempt, so the queued flush is idempotent server-side;
//  * the queued row is `local_queue` `_offlineKind: 'add_student'`, flushed by
//    MonitoringApi._dispatchLocalQueueItem BEFORE any result the child made
//    meanwhile (created ASC); that result carries `student_id: new:<uuid>`
//    and is re-pointed to the server id at flush time (LocalStudentsDb);
//  * wave-2 pack mode will reuse the same temp id as `student_id` in the pack
//    chain entry together with a `new_student` block (contract "Offline").
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../db/local_students_db.dart';
import '../db/offline_queue.dart';
import '../models/add_student.dart';

/// Failures that mean "the add endpoint is not reachable right now": no
/// network (0), an older backend without the route (404/405), a throttle or a
/// gateway/server outage. Everything else (400 invalid, 409 limit, ...) is a
/// real answer the proctor must see.
bool shouldQueueAddStudent(ApiException e) =>
    e.statusCode == 0 ||
    const {404, 405, 429, 502, 503, 504}.contains(e.statusCode);

Future<AddStudentResult> addStudentOrQueue({
  required String groupId,
  required AddStudentDraft draft,
  required bool confirmNew,
  int grade = 0,
  String language = '',
  MonitoringApi? apiOverride,
}) async {
  final client = apiOverride ?? api;
  try {
    return await client.addStudent(
        groupId: groupId, draft: draft, confirmNew: confirmNew);
  } on SimilarStudentsException {
    rethrow;
  } on ApiException catch (e) {
    if (!shouldQueueAddStudent(e)) rethrow;
    debugPrint('addStudent unreachable (${e.statusCode}), queueing locally');
    return queueAddStudentLocally(
        groupId: groupId, draft: draft, grade: grade, language: language);
  }
}

/// Stores the add in the encrypted local queue + the local roster table.
/// Throws if the local DB write fails (the proctor must not believe the child
/// was saved when it was not).
Future<AddStudentResult> queueAddStudentLocally({
  required String groupId,
  required AddStudentDraft draft,
  int grade = 0,
  String language = '',
}) async {
  await OfflineQueue.enqueueLocal({
    '_offlineKind': 'add_student',
    'group_id': groupId,
    'first_name': draft.firstName,
    'last_name': draft.lastName,
    if (draft.birthDate != null)
      'birth_date': draft.birthDate!.toIso8601String().substring(0, 10),
    if (draft.parentFio.isNotEmpty) 'parent_fio': draft.parentFio,
    'client_temp_id': draft.clientTempId,
  }, draft.clientTempId);
  await LocalStudentsDb.add(LocalStudent(
    tempId: draft.clientTempId,
    groupId: groupId,
    firstName: draft.firstName,
    lastName: draft.lastName,
    grade: grade,
    language: language,
  ));
  return AddStudentResult(
    id: draft.clientTempId,
    name: '${draft.lastName} ${draft.firstName}'.trim(),
    firstName: draft.firstName,
    lastName: draft.lastName,
    groupId: groupId,
    grade: grade,
    language: language,
    queuedLocally: true,
  );
}
