import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_export_schools.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> row(String attempt, String school, {String? schoolId}) => {
      'attempt_id': attempt,
      'school': school,
      'school_id': schoolId,
    };

final schools = <Map<String, dynamic>>[
  {'school_id': 'A', 'school_name': '56-maktab', 'school_number': '56', 'kiosk_pin': '1111'},
  {'school_id': 'B', 'school_name': '12-maktab', 'school_number': '12', 'kiosk_pin': ''},
];

void main() {
  test('rows with a school_id group by it, names come from the cached list',
      () {
    final g = groupExportSchools([
      row('1', 'whatever', schoolId: 'A'),
      row('2', '12-maktab', schoolId: 'B'),
      row('3', '56-maktab', schoolId: 'A'),
    ], schools);
    expect(g.unresolvedCount, 0);
    expect(g.resolved.map((s) => s.id), ['A', 'B']);
    expect(g.resolved.first.name, '56-maktab');
    expect(g.resolved.first.records.map((r) => r['attempt_id']), ['1', '3']);
  });

  test('rows without a school_id are unresolved, even on an exact name match',
      () {
    final g = groupExportSchools([
      row('1', '56-maktab', schoolId: 'A'),
      row('2', '  56-MAKTAB '),
      row('3', 'Boshqa maktab'),
      row('4', ''),
      row('5', 'dup'),
    ], [
      ...schools,
      {'school_id': 'C', 'school_name': 'Dup'},
    ]);
    expect(g.resolved.single.id, 'A');
    expect(g.resolved.single.records, hasLength(1));
    expect(g.unresolvedCount, 4);
  });

  test('PIN rule: pin_required wins, else kiosk_pin, unknown school needs PIN',
      () {
    final g = groupExportSchools([
      row('1', 'x', schoolId: 'A'),
      row('2', 'x', schoolId: 'B'),
      row('3', 'x', schoolId: 'Z'),
      row('4', 'x', schoolId: 'P'),
      row('5', 'x', schoolId: 'Q'),
    ], [
      ...schools,
      {'school_id': 'P', 'school_name': 'p', 'pin_required': false, 'kiosk_pin': '9'},
      {'school_id': 'Q', 'school_name': 'q', 'pin_required': true, 'kiosk_pin': ''},
    ]);
    bool need(String id) => g.resolved.firstWhere((s) => s.id == id).pinRequired;
    expect(need('A'), isTrue);
    expect(need('B'), isFalse);
    expect(need('Z'), isTrue, reason: 'not in the cache: cannot prove no PIN');
    expect(need('P'), isFalse);
    expect(need('Q'), isTrue);
    expect(g.resolved.firstWhere((s) => s.id == 'A').legacyPin, '1111');
    expect(g.resolved.firstWhere((s) => s.id == 'Z').legacyPin, '');
  });

  test('fileLabel prefers the school number, else the name', () {
    final g = groupExportSchools([
      row('1', 'x', schoolId: 'A'),
      row('2', 'Bir / Ikki: maktab', schoolId: 'N'),
    ], [
      ...schools,
      {'school_id': 'N', 'school_name': 'Bir / Ikki: maktab'},
    ]);
    expect(g.resolved.first.fileLabel, '56');
    expect(g.resolved.last.fileLabel, 'Bir / Ikki: maktab');
  });
}
