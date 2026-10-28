import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/auth/monitoring_school_list.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogEntry entry(String key, List<SchoolButton> buttons) => CatalogEntry(
      testKey: key,
      title: key,
      grade: 1,
      version: 1,
      status: CatalogStatus.notDownloaded,
      schoolButtons: buttons,
    );

SchoolButton btn(String code, {String id = '', String label = ''}) =>
    SchoolButton(
      pin: '',
      label: label.isEmpty ? 'L$code' : label,
      schoolCode: code,
      schoolId: id,
      randomVariant: false,
    );

Map<String, String> live(String code, String id, [String label = '']) =>
    {'school_code': code, 'school_id': id, 'label': label};

List<MonitoringSchoolRow> merge(
  List<CatalogEntry> e,
  List<Map<String, String>> s,
) =>
    mergeMonitoringSchools(e, s, fallbackLabel: (c) => 'Maktab $c');

void main() {
  test('empty sources -> empty list', () {
    expect(merge([], []), isEmpty);
    expect(merge([entry('t', [])], []), isEmpty); // tests without schools
  });

  test('catalog schools sorted numerically, first entry kept', () {
    final e1 = entry('a', [btn('10'), btn('2')]);
    final e2 = entry('b', [btn('2')]);
    final rows = merge([e1, e2], []);
    expect(rows.map((r) => r.code), ['2', '10']);
    expect(rows.first.entry, same(e1));
  });

  test('old catalog (no id) + live list = ONE card, id taken from live', () {
    final rows = merge(
      [
        entry('a', [btn('39')]),
      ],
      [live('39', 'uuid-39')],
    );
    expect(rows, hasLength(1));
    expect(rows.single.id, 'uuid-39');
    expect(rows.single.entry, isNotNull);
  });

  test('same code, two ids -> two cards keyed by id', () {
    final rows = merge(
      [
        entry('a', [btn('39', id: 'u1', label: 'A')]),
      ],
      [live('39', 'u1'), live('39', 'u2', 'B')],
    );
    expect(rows.map((r) => r.id), ['u1', 'u2']);
    expect(rows.map((r) => r.label), ['A', 'B']);
    expect(rows.first.entry, isNotNull);
    expect(rows.last.entry, isNull);
  });

  test('live-only schools come after catalog ones, fallback label used', () {
    final rows = merge(
      [
        entry('a', [btn('50')]),
      ],
      [live('7', 'u7'), live('9', 'u9', 'Nine')],
    );
    expect(rows.map((r) => r.code), ['50', '7', '9']);
    expect(rows[1].label, 'Maktab 7');
    expect(rows[2].label, 'Nine');
    expect(rows[1].entry, isNull);
  });
}
