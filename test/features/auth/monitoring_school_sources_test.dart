import 'dart:convert';

import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/auth/monitoring_school_list.dart';
import 'package:alochi_monitoring/features/auth/school_pick_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, String> school(String code) =>
    {'school_code': code, 'label': '$code-maktab', 'school_id': 'id$code'};

// What TestCatalogService.refresh() returns offline: cached rows, no buttons.
CatalogEntry cachedOnly() => const CatalogEntry(
      testKey: 't1',
      title: 't1',
      grade: 1,
      version: 1,
      status: CatalogStatus.cachedOnly,
    );

Future<List<String>> saved() async {
  final raw = (await SharedPreferences.getInstance())
      .getString(kCachedMonitoringSchoolsKey);
  if (raw == null) return [];
  return [
    for (final m in jsonDecode(raw) as List) (m as Map)['school_code'] as String
  ];
}

Future<List<String>> shown(MonitoringSchoolSources src) async => [
      for (final r in mergeMonitoringSchools(src.entries, src.schools,
          fallbackLabel: (c) => c))
        r.code,
    ];

Never offline() => throw Exception('offline');

void main() {
  Future<MonitoringSchoolSources> load({
    required Future<List<CatalogEntry>> Function() entries,
    required Future<List<Map<String, String>>> Function() schools,
  }) =>
      loadMonitoringSchoolSources(fetchEntries: entries, fetchSchools: schools);

  test('live result wins over a stale saved list and replaces it', () async {
    SharedPreferences.setMockInitialValues({
      kCachedMonitoringSchoolsKey: jsonEncode([school('1'), school('2')]),
    });
    final src = await load(
      entries: () async => [],
      schools: () async => [school('1'), school('2'), school('3')],
    );
    expect(await shown(src), ['1', '2', '3']);
    expect(await saved(), ['1', '2', '3']);
  });

  test(
      'live failure shows the last saved list (offline, cached entries '
      'without schoolButtons)', () async {
    SharedPreferences.setMockInitialValues({});
    await load(
      entries: () async => [],
      schools: () async => [school('1'), school('2'), school('3')],
    );
    final src = await load(
      entries: () async => [cachedOnly()],
      schools: () async => offline(),
    );
    expect(await shown(src), ['1', '2', '3']);
    expect(await saved(), ['1', '2', '3']); // failure does not touch the copy
  });

  test('a school gone from the live response is gone from the saved copy',
      () async {
    SharedPreferences.setMockInitialValues({
      kCachedMonitoringSchoolsKey:
          jsonEncode([school('1'), school('2'), school('3')]),
    });
    final src = await load(
      entries: () async => [],
      schools: () async => [school('1'), school('3')],
    );
    expect(await shown(src), ['1', '3']);
    expect(await saved(), ['1', '3']);
    final offlineSrc = await load(
      entries: () async => offline(),
      schools: () async => offline(),
    );
    expect(await shown(offlineSrc), ['1', '3']);
  });

  test('empty successful live list is not refilled from the saved copy',
      () async {
    SharedPreferences.setMockInitialValues({
      kCachedMonitoringSchoolsKey: jsonEncode([school('1')]),
    });
    final src = await load(entries: () async => [], schools: () async => []);
    expect(await shown(src), isEmpty);
    expect(await saved(), isEmpty);
  });

  test('nothing saved and live fails -> still throws (error banner)', () async {
    SharedPreferences.setMockInitialValues({});
    await expectLater(
      load(entries: () async => [cachedOnly()], schools: () async => offline()),
      throwsException,
    );
  });

  test('corrupt saved prefs never break the load', () async {
    SharedPreferences.setMockInitialValues({kCachedMonitoringSchoolsKey: '{x'});
    await expectLater(
      load(entries: () async => [], schools: () async => offline()),
      throwsException,
    );
    final src = await load(
      entries: () async => [],
      schools: () async => [school('7')],
    );
    expect(await shown(src), ['7']);
    expect(await saved(), ['7']);
  });
}
