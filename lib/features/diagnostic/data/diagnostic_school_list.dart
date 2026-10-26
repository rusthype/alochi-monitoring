// lib/features/diagnostic/data/diagnostic_school_list.dart
//
// Pure helpers for the kiosk school picker: parsing a `kiosk/schools/` row
// (every post-2026-10 field is optional — an old backend/cache still works),
// numeric sorting, locale-aware short names, search and city grouping.
import 'package:flutter/widgets.dart' show Locale;
import '../../../core/utils/student_name_formatter.dart';

class DiagnosticSchool {
  final Map<String, dynamic> raw;
  final String id;
  final String name;
  final int? number;
  final String cityName;
  final String abbreviation;

  const DiagnosticSchool._(
    this.raw,
    this.id,
    this.name,
    this.number,
    this.cityName,
    this.abbreviation,
  );

  factory DiagnosticSchool.fromMap(Map<String, dynamic> m) {
    String s(String k) => (m[k] ?? '').toString().trim();
    return DiagnosticSchool._(
      m,
      s('school_id'),
      s('school_name'),
      int.tryParse(s('school_number')),
      s('city_name'),
      s('abbreviation'),
    );
  }
}

const _uz = Locale('uz');

/// Lowercase Latin form with unified apostrophes, so Cyrillic and Latin
/// input/data compare equal.
String normalizeSchoolText(String raw) => toDisplayScript(raw, _uz)
    .toLowerCase()
    .replaceAll(RegExp('[`’ʻʼ‘ʹ]'), "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Number ascending (null last), then name.
List<DiagnosticSchool> sortSchools(Iterable<DiagnosticSchool> schools) {
  final out = schools.toList();
  out.sort((a, b) {
    if (a.number != b.number) {
      if (a.number == null) return 1;
      if (b.number == null) return -1;
      return a.number!.compareTo(b.number!);
    }
    return normalizeSchoolText(a.name).compareTo(normalizeSchoolText(b.name));
  });
  return out;
}

final _boilerplate = <RegExp>[
  RegExp(r"umumiy o'rta ta'lim maktabi"),
  RegExp(r"ixtisoslashtirilgan maktab-internat(i)?"),
  RegExp(r'(hu|xu)zuridagi'),
  RegExp(r'\bqa\b'),
];

/// Name without the generic "umumiy o'rta ta'lim maktabi" /
/// "QA huzuridagi ixtisoslashtirilgan maktab-internat" boilerplate, in Latin.
/// Falls back to the full (Latin) name when nothing meaningful is left.
String stripSchoolBoilerplate(String name) {
  final latin = toDisplayScript(
    name,
    _uz,
  ).replaceAll(RegExp('[`’ʻʼ‘ʹ]'), "'").trim();
  var out = latin;
  for (final re in _boilerplate) {
    out = out.replaceAll(RegExp(re.pattern, caseSensitive: false), ' ');
  }
  out = out
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s\-–,.]+|[\s\-–,.]+$'), '');
  return out.isEmpty ? latin : out;
}

/// Short card title: abbreviation, else "{n}-maktab" via [numberLabel] when
/// the number is known, else the stripped name in the display script.
String shortSchoolName(
  DiagnosticSchool s,
  Locale locale,
  String Function(int number) numberLabel,
) {
  if (s.abbreviation.isNotEmpty) return toDisplayScript(s.abbreviation, locale);
  if (s.number != null) return numberLabel(s.number!);
  return toDisplayScript(stripSchoolBoilerplate(s.name), locale);
}

bool schoolMatchesQuery(DiagnosticSchool s, String query) {
  final q = normalizeSchoolText(query);
  if (q.isEmpty) return true;
  return (s.number?.toString().contains(q) ?? false) ||
      normalizeSchoolText(s.name).contains(q) ||
      normalizeSchoolText(s.abbreviation).contains(q);
}

/// Distinct non-empty city names, in first-seen order of [schools].
List<String> distinctCities(Iterable<DiagnosticSchool> schools) {
  final seen = <String>[];
  for (final s in schools) {
    if (s.cityName.isNotEmpty && !seen.contains(s.cityName)) {
      seen.add(s.cityName);
    }
  }
  return seen;
}
