// lib/core/models/add_student.dart
//
// "Bola qo'shish" (add a missing child) — draft, result and error models plus
// the shared name validation. Contract: monitoring/students/add/ and
// diagnostic/kiosk/schools/<id>/students/add/ (both return 409
// `similar_students` with candidates before creating anything).
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../api/api_client.dart' show ApiException;

/// Prefix of a kiosk-local child id (== the `client_temp_id`). Offline (wave 2)
/// pack results and the local queue reuse the SAME id: the pack chain entry
/// carries `student_id: "new:<uuid>"` plus a `new_student` block, and the
/// online queue rewrites `student_id` to the server id once the queued
/// `add_student` item has been accepted (see LocalStudentsDb).
const String kNewStudentIdPrefix = 'new:';

bool isLocalNewStudentId(String id) => id.startsWith(kNewStudentIdPrefix);

/// Why a name was rejected by [validateStudentName]; the UI maps it to l10n.
enum StudentNameError { required, length, chars }

// Letters (Latin + Cyrillic + any unicode letter), space, hyphen and the
// apostrophe variants used in Uzbek (' ’ ʻ ʼ `). Mirrors the backend rule.
final RegExp _nameChars = RegExp(r"^[\p{L}ʻʼ'’‘`\- ]+$", unicode: true);

/// Trim + collapse inner whitespace, the form that is validated and sent.
String normalizeStudentName(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Null when [raw] is a valid first/last name (2..60 chars after trim).
StudentNameError? validateStudentName(String raw) {
  final v = normalizeStudentName(raw);
  if (v.isEmpty) return StudentNameError.required;
  if (v.length < 2 || v.length > 60) return StudentNameError.length;
  if (!_nameChars.hasMatch(v)) return StudentNameError.chars;
  return null;
}

/// Optional parent F.I.O. is only length-capped (<= 120).
const int kParentFioMaxLength = 120;

String _dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// What the proctor typed. [clientTempId] is generated ONCE per add attempt
/// (dialog open) and reused by every retry, which makes the server call
/// idempotent on (school, client_temp_id).
class AddStudentDraft {
  final String firstName;
  final String lastName;
  final DateTime? birthDate;
  final String parentFio;
  final String clientTempId;

  const AddStudentDraft({
    required this.firstName,
    required this.lastName,
    required this.clientTempId,
    this.birthDate,
    this.parentFio = '',
  });

  static String newTempId() => '$kNewStudentIdPrefix${const Uuid().v4()}';

  /// Body fields shared by both endpoints (group / class fields are added by
  /// the caller).
  Map<String, dynamic> toJson({bool confirmNew = false}) => {
        'first_name': firstName,
        'last_name': lastName,
        if (birthDate != null) 'birth_date': _dateOnly(birthDate!),
        if (parentFio.isNotEmpty) 'parent_fio': parentFio,
        'client_temp_id': clientTempId,
        if (confirmNew) 'confirm_new': true,
      };
}

/// One "Bu shumi?" candidate (`similar_students` 409).
class SimilarStudent {
  final String id;
  final String name;
  final int grade;
  final String groupName;

  const SimilarStudent({
    required this.id,
    required this.name,
    this.grade = 0,
    this.groupName = '',
  });

  factory SimilarStudent.fromJson(Map<String, dynamic> j) => SimilarStudent(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        grade: (j['grade'] as num?)?.toInt() ?? 0,
        groupName: j['group_name']?.toString() ?? '',
      );
}

/// 409 `similar_students` — nothing was created; the UI asks "Bu shumi?".
class SimilarStudentsException extends ApiException {
  final List<SimilarStudent> candidates;
  const SimilarStudentsException(this.candidates)
      : super(409, 'similar_students', code: 'similar_students');
}

/// Successful add (online 200/201, or locally queued when the network failed).
class AddStudentResult {
  /// Monitoring: the student/request id (usable as `student_id`); locally
  /// queued: the temp id `new:<uuid>`. Diagnostic: the `attempt_id`.
  final String id;
  final String name;
  final String firstName;
  final String lastName;
  final String groupId;
  final int grade;
  final String language;
  final bool pending;

  /// True when the call could not reach the server and was put in the local
  /// queue (`_offlineKind: add_student`); [id] is then the temp id.
  final bool queuedLocally;

  /// Diagnostic only.
  final String classLabel;
  final String status;

  const AddStudentResult({
    required this.id,
    required this.name,
    this.firstName = '',
    this.lastName = '',
    this.groupId = '',
    this.grade = 0,
    this.language = '',
    this.pending = true,
    this.queuedLocally = false,
    this.classLabel = '',
    this.status = '',
  });

  factory AddStudentResult.fromMonitoringJson(Map<String, dynamic> j) {
    final first = j['first_name']?.toString() ?? '';
    final last = j['last_name']?.toString() ?? '';
    return AddStudentResult(
      id: j['id']?.toString() ?? '',
      name: (j['name']?.toString() ?? '').isNotEmpty
          ? j['name'].toString()
          : '$last $first'.trim(),
      firstName: first,
      lastName: last,
      groupId: j['group_id']?.toString() ?? '',
      grade: (j['grade'] as num?)?.toInt() ?? 0,
      language: j['language']?.toString() ?? '',
      pending: j['pending'] != false,
      status: j['status']?.toString() ?? 'pending',
    );
  }

  factory AddStudentResult.fromDiagnosticJson(Map<String, dynamic> j) =>
      AddStudentResult(
        id: j['attempt_id']?.toString() ?? '',
        name: j['student_name']?.toString() ?? '',
        classLabel: j['class_label']?.toString() ?? '',
        language: j['language']?.toString() ?? '',
        pending: j['pending'] != false,
        status: j['status']?.toString() ?? 'not_started',
      );

  /// A monitoring roster row (same keys `fetchStudents` rows use).
  Map<String, dynamic> toRosterRow() => {
        'id': id,
        'name': name,
        'first_name': firstName,
        'last_name': lastName,
        'grade': grade,
        'pending': pending,
        if (queuedLocally) 'local_pending': true,
      };

  /// A diagnostic roster row (`kiosk/schools/<id>/students/` shape).
  Map<String, dynamic> toDiagnosticRow() => {
        'attempt_id': id,
        'student_name': name,
        'class_label': classLabel,
        'language': language,
        'status': status.isEmpty ? 'not_started' : status,
        'pending': pending,
      };
}

/// Turns an add-endpoint HTTP response into a result or the right exception.
/// 409 `similar_students` -> [SimilarStudentsException]; every other 4xx/5xx ->
/// [ApiException] carrying the body `code` (`invalid_name`, `invalid_group`,
/// `pending_limit`, ...).
AddStudentResult parseAddStudentResponse(http.Response resp,
    {required bool diagnostic}) {
  Map<String, dynamic> data = const {};
  try {
    final d = jsonDecode(utf8.decode(resp.bodyBytes));
    if (d is Map) data = Map<String, dynamic>.from(d);
  } catch (_) {
    // Non-JSON body: handled by the status checks below.
  }
  if (resp.statusCode == 409 && data['code'] == 'similar_students') {
    final raw = data['candidates'];
    final list = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => SimilarStudent.fromJson(Map<String, dynamic>.from(e)))
            .where((c) => c.id.isNotEmpty)
            .toList()
        : <SimilarStudent>[];
    throw SimilarStudentsException(list);
  }
  if (resp.statusCode >= 400) {
    final raw = data['detail'] ?? data['message'] ?? '';
    final msg = raw.toString().isNotEmpty
        ? raw.toString()
        : (resp.statusCode >= 500
            ? 'Server xatosi'
            : 'Xato: ${resp.statusCode}');
    throw ApiException(resp.statusCode, msg, code: data['code']?.toString());
  }
  final result = diagnostic
      ? AddStudentResult.fromDiagnosticJson(data)
      : AddStudentResult.fromMonitoringJson(data);
  if (result.id.isEmpty) {
    throw ApiException(resp.statusCode, "Noto'g'ri javob");
  }
  return result;
}
