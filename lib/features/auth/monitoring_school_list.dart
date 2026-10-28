// lib/features/auth/monitoring_school_list.dart
//
// Pure merge of the monitoring school sources (extracted unchanged from the
// old login catalog bottom sheet): schools hanging off catalog tests'
// `schoolButtons` + the live `GET /tests/catalog/schools/` list.
import '../../core/services/test_catalog_service.dart';

class MonitoringSchoolRow {
  final String code;

  /// School UUID; '' when only an old (pre-schoolId) catalog entry knows it.
  final String id;
  final String label;

  /// First catalog entry carrying this school; null for schools known only
  /// from the live schools list.
  final CatalogEntry? entry;
  const MonitoringSchoolRow({
    required this.code,
    required this.id,
    required this.label,
    this.entry,
  });
}

/// Catalog schools first (numeric code order), then the schools only the live
/// list knows (in API order). One row per physical school: deduped by
/// schoolCode, falling back to schoolId only when one code maps to 2+ ids.
///
/// Why: `entry.schoolButtons` is frozen at the test's publish time (tests
/// published before the schoolId deploy have an empty id) while [schools] is
/// computed live with the id always set. Keying by "id if present else code"
/// would show the same school twice (seen after the 2026-09-07 deploy).
List<MonitoringSchoolRow> mergeMonitoringSchools(
  List<CatalogEntry> entries,
  List<Map<String, String>> schools, {
  required String Function(String code) fallbackLabel,
}) {
  final idsByCode = <String, Set<String>>{};
  void noteId(String code, String id) {
    if (id.isEmpty || code.isEmpty) return;
    idsByCode.putIfAbsent(code, () => {}).add(id);
  }

  for (final entry in entries) {
    for (final sb in entry.schoolButtons) {
      noteId(sb.schoolCode, sb.schoolId);
    }
  }
  for (final s in schools) {
    noteId(s['school_code'] ?? '', s['school_id'] ?? '');
  }

  String dedupeKey(String code, String id) {
    final ids = idsByCode[code];
    if (ids != null && ids.length > 1 && id.isNotEmpty) return id;
    return code;
  }

  final keyToLabel = <String, String>{};
  final keyToCode = <String, String>{};
  final keyToEntry = <String, CatalogEntry>{};
  for (final entry in entries) {
    for (final sb in entry.schoolButtons) {
      final key = dedupeKey(sb.schoolCode, sb.schoolId);
      keyToLabel[key] = sb.label;
      keyToCode[key] = sb.schoolCode;
      keyToEntry.putIfAbsent(key, () => entry);
    }
  }

  final keys = keyToEntry.keys.toList()
    ..sort((a, b) {
      // Sort by the human-readable numeric code even when the key is a UUID.
      final aCode = keyToCode[a] ?? a;
      final bCode = keyToCode[b] ?? b;
      final aNum = int.tryParse(aCode);
      final bNum = int.tryParse(bCode);
      if (aNum != null && bNum != null) return aNum.compareTo(bNum);
      return aCode.compareTo(bCode);
    });

  final out = <MonitoringSchoolRow>[];
  for (final key in keys) {
    final code = keyToCode[key] ?? key;
    final ids = idsByCode[code];
    // Exactly one known id (no collision), or the key is itself that id.
    final id = (ids != null && ids.length == 1)
        ? ids.first
        : (ids != null && ids.contains(key) ? key : '');
    out.add(
      MonitoringSchoolRow(
        code: code,
        id: id,
        label: keyToLabel[key] ?? fallbackLabel(code),
        entry: keyToEntry[key],
      ),
    );
  }

  final covered = keys.toSet();
  for (final s in schools) {
    final code = s['school_code'] ?? '';
    final id = s['school_id'] ?? '';
    if (covered.contains(dedupeKey(code, id))) continue;
    final label = s['label'] ?? '';
    out.add(
      MonitoringSchoolRow(
        code: code,
        id: id,
        label: label.isNotEmpty ? label : fallbackLabel(code),
      ),
    );
  }
  return out;
}
