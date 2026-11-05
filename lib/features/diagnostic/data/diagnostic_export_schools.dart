// lib/features/diagnostic/data/diagnostic_export_schools.dart
//
// Splits the local diagnostic history by school for the per-school export. A
// PC's history can hold several schools, and a school's PIN must only ever
// unlock that school's rows, so a row is exportable only once it is tied to a
// school id: its own `school_id`. Old rows without one are "unresolved" and are
// never exported (two schools can share a name, so the name is never trusted).
class ExportSchool {
  final String id;
  final String name;
  final String number;
  final String legacyPin;
  final bool pinRequired;
  final List<Map<String, dynamic>> records = [];

  ExportSchool({
    required this.id,
    required this.name,
    this.number = '',
    this.legacyPin = '',
    this.pinRequired = true,
  });

  /// School number when known, else the name (sanitised when used in a file
  /// name by `DiagnosticExportService.saveZipUnique`).
  String get fileLabel => number.isNotEmpty ? number : name;
}

class ExportSchools {
  final List<ExportSchool> resolved;
  final int unresolvedCount;
  const ExportSchools(this.resolved, this.unresolvedCount);
}

String _norm(Object? v) =>
    (v ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

ExportSchools groupExportSchools(
  List<Map<String, dynamic>> records,
  List<Map<String, dynamic>> schools,
) {
  final byId = <String, Map<String, dynamic>>{};
  for (final s in schools) {
    final id = _norm(s['school_id']);
    if (id.isEmpty) continue;
    byId[id] = s;
  }

  final groups = <String, ExportSchool>{};
  var unresolved = 0;
  for (final r in records) {
    final key = _norm(r['school_id']);
    if (key.isEmpty) {
      unresolved++;
      continue;
    }
    groups.putIfAbsent(key, () {
      final s = byId[key];
      if (s == null) {
        // Not in the cache: cannot prove the school has no PIN, so require it.
        return ExportSchool(
          id: (r['school_id'] ?? key).toString().trim(),
          name: (r['school'] ?? '').toString(),
        );
      }
      final pin = (s['kiosk_pin'] ?? '').toString().trim();
      return ExportSchool(
        id: (s['school_id'] ?? '').toString().trim(),
        name: (s['school_name'] ?? r['school'] ?? '').toString(),
        number: (s['school_number'] ?? '').toString().trim(),
        legacyPin: pin,
        pinRequired:
            s['pin_required'] is bool ? s['pin_required'] as bool : pin.isNotEmpty,
      );
    }).records.add(r);
  }
  return ExportSchools(groups.values.toList(), unresolved);
}
