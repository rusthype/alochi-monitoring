// lib/core/offline/offline_new_student.dart
//
// Pure helpers for "Bola qo'shish" inside an offline pack (add-student wave 2).
//  * duplicate lookup against the pack roster (+ children already added here),
//    across ALL groups of the pack so a parallel class is caught;
//  * the chain entry's `new_student` block (contract "Offline (pack) path").
import '../models/add_student.dart';
import '../utils/student_name_formatter.dart';

/// Order- and script-insensitive name key tokens: Cyrillic -> Latin, lower
/// case, apostrophe variants dropped, sorted ("Valiyev Ali" == "Ali Valiyev").
List<String> studentNameTokens(String raw) {
  final latin = cyrillicToLatinUzbek(raw)
      .toLowerCase()
      .replaceAll(RegExp(r"[ʻʼ'’‘`]"), '');
  return latin.split(RegExp(r'[\s\-]+')).where((t) => t.isNotEmpty).toList()
    ..sort();
}

/// True when [typed] and [existing] name the same child: equal token sets, or
/// one is a subset of the other ("Ali Valiyev" vs "Valiyev Ali Karimovich").
/// This only drives the soft "Bu shumi?" prompt, so it errs on asking.
bool namesMatch(List<String> typed, List<String> existing) {
  if (typed.length < 2 || existing.length < 2) return false;
  final a = typed.toSet(), b = existing.toSet();
  return a.containsAll(b) || b.containsAll(a);
}

/// Grade of a pack group: explicit `grade`, else the leading digits of its name.
int gradeOfGroup(Map<String, dynamic> group) {
  final g = group['grade'];
  if (g is num) return g.toInt();
  final m = RegExp(r'^\s*(\d+)').firstMatch(group['name']?.toString() ?? '');
  return m == null ? 0 : int.parse(m.group(1)!);
}

/// "Bu shumi?" candidates for a child named [lastName] [firstName] among
/// [roster] (pack students + local children; every group).
List<SimilarStudent> similarInRoster({
  required List<Map<String, dynamic>> roster,
  required List<Map<String, dynamic>> groups,
  required String firstName,
  required String lastName,
}) {
  final typed = studentNameTokens('$lastName $firstName');
  final groupById = {
    for (final g in groups) g['id']?.toString() ?? '': g,
  };
  final out = <SimilarStudent>[];
  for (final s in roster) {
    final id = s['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    if (!namesMatch(typed, studentNameTokens(s['name']?.toString() ?? ''))) {
      continue;
    }
    final g = groupById[s['group_id']?.toString() ?? ''];
    out.add(SimilarStudent(
      id: id,
      name: s['name']?.toString() ?? '',
      grade: g == null ? 0 : gradeOfGroup(g),
      groupName: g?['name']?.toString() ?? '',
    ));
  }
  return out;
}

/// [payload] with the `new_student` block attached when its `student_id` is a
/// kiosk-local child found in [localRows] (rows of
/// `PackLocalStudent.toRosterRow`). Any other payload — a pack student, or one
/// that already carries the block — is returned as the SAME map, untouched.
Map<String, dynamic> attachNewStudent(
    Map<String, dynamic> payload, Iterable<Map<String, dynamic>> localRows) {
  final sid = payload['student_id'];
  if (sid is! String || !isLocalNewStudentId(sid)) return payload;
  if (payload.containsKey('new_student')) return payload;
  for (final r in localRows) {
    if (r['id']?.toString() != sid) continue;
    return {
      ...payload,
      'new_student': {
        'temp_id': sid,
        'first_name': r['first_name']?.toString() ?? '',
        'last_name': r['last_name']?.toString() ?? '',
        if ((r['birth_date']?.toString() ?? '').isNotEmpty)
          'birth_date': r['birth_date'].toString(),
        if ((r['parent_fio']?.toString() ?? '').isNotEmpty)
          'parent_fio': r['parent_fio'].toString(),
        'group_id': r['group_id']?.toString() ?? '',
        if (r['transfer_claim'] is Map) 'transfer_claim': r['transfer_claim'],
      },
    };
  }
  return payload;
}
