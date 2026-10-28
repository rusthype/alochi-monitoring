// The offline (cachedOnly) catalog is scoped like the online one: only the
// tests listed for the current group / school, with their last known time
// lock. Plus the per-group roster cache that backs the offline roster.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _blob = '{"title":"T","grade":5,"version":1,"parts":["Math"],'
    '"variants":{"1":{"Math":[{"type":"text_choice","q":"x","opts":["a","b"],"ans":0}]}}}';

class _Api extends MonitoringApi {
  Object? failWith;
  final Map<String, List<Map<String, dynamic>>> byGroup = {};
  List<Map<String, dynamic>> unfiltered = [];
  List<Map<String, dynamic>> bySchool = [];

  @override
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    final f = failWith;
    if (f != null) throw f;
    if (groupId != null && groupId.isNotEmpty) return byGroup[groupId] ?? [];
    if ((schoolCode ?? '').isNotEmpty || (schoolId ?? '').isNotEmpty) {
      return bySchool;
    }
    return unfiltered;
  }
}

Map<String, dynamic> _item(String key, {String? lockedUntil, String? until}) =>
    {
      'test_key': key,
      'title': key,
      'grade': 5,
      'version': 1,
      if (lockedUntil != null) 'locked_until': lockedUntil,
      if (until != null) 'available_until': until,
    };

void main() {
  late Directory dir;
  late _Api api;
  late TestCatalogService svc;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestCatalogService.resetKnownMissingForTest();
    TestCache.exitMemoryMode();
    dir = Directory.systemTemp.createTempSync('catalog_scope_');
    TestCache.pathOverride = '${dir.path}/tc.db';
    api = _Api();
    svc = TestCatalogService(api);
  });
  tearDown(() async {
    await TestCache.resetForTest();
    dir.deleteSync(recursive: true);
  });

  Future<void> cache(String key) =>
      TestCache.upsert(key, key, 5, 1, _blob);

  Future<List<String>> offlineKeys(
      {String? groupId, String? schoolCode, String? schoolId}) async {
    api.failWith = const ApiException(0, 'down', code: kApiNetwork);
    final entries = await svc.refresh(
        groupId: groupId, schoolCode: schoolCode, schoolId: schoolId);
    return entries.map((e) => e.testKey).toList()..sort();
  }

  test('offline group catalog shows only the tests listed for that group',
      () async {
    await cache('A');
    await cache('B');
    api.byGroup['gA'] = [_item('A')];
    api.byGroup['gB'] = [_item('B')];
    await svc.refresh(groupId: 'gA', schoolCode: '1');
    await svc.refresh(groupId: 'gB', schoolCode: '1');

    expect(await offlineKeys(groupId: 'gA', schoolCode: '1'), ['A']);
    expect(await offlineKeys(groupId: 'gB', schoolCode: '1'), ['B']);
  });

  test('a group with nothing cached for it is an error, not "no tests"',
      () async {
    await cache('A');
    api.byGroup['gA'] = [_item('A')];
    await svc.refresh(groupId: 'gA', schoolCode: '1');
    expect(() => offlineKeys(groupId: 'gZ', schoolCode: '1'),
        throwsA(isA<ApiException>()));
  });

  test('a test listed without any filter is visible in every group offline',
      () async {
    await cache('G');
    api.unfiltered = [_item('G')];
    await svc.refresh();
    expect(await offlineKeys(groupId: 'gA', schoolCode: '1'), ['G']);
    expect(await offlineKeys(), ['G']);
  });

  test('school-only listing is shown for that school, not for a group',
      () async {
    await cache('S');
    await cache('Other');
    api.bySchool = [_item('S')];
    await svc.refresh(schoolCode: '7', schoolId: 'sid7');
    api.byGroup['gA'] = [_item('Other')];
    await svc.refresh(groupId: 'gA', schoolCode: '7');
    expect(await offlineKeys(schoolCode: '7', schoolId: 'sid7'), ['S']);
    expect(await offlineKeys(groupId: 'gA', schoolCode: '7'), ['Other']);
  });

  test('another school does not see it', () async {
    await cache('S');
    await cache('Other');
    api.bySchool = [_item('S')];
    await svc.refresh(schoolCode: '7', schoolId: 'sid7');
    api.bySchool = [_item('Other')];
    await svc.refresh(schoolCode: '8', schoolId: 'sid8');
    expect(await offlineKeys(schoolCode: '7', schoolId: 'sid7'), ['S']);
    expect(await offlineKeys(schoolCode: '8', schoolId: 'sid8'), ['Other']);
  });

  test('rows cached before scopes existed stay visible (cannot be proven wrong)',
      () async {
    await cache('Legacy');
    expect(await offlineKeys(groupId: 'gA', schoolCode: '1'), ['Legacy']);
  });

  test('re-downloading a test keeps its scopes and lock', () async {
    await cache('A');
    api.byGroup['gA'] = [
      _item('A', lockedUntil: '2031-01-01T10:00:00Z', until: '2031-01-01T12:00:00Z')
    ];
    await svc.refresh(groupId: 'gA', schoolCode: '1');
    await cache('A'); // upsert (replace) of a newer copy
    final entries = await (() async {
      api.failWith = const ApiException(0, 'down', code: kApiNetwork);
      return svc.refresh(groupId: 'gA', schoolCode: '1');
    })();
    expect(entries.single.testKey, 'A');
    expect(entries.single.lockedUntil, DateTime.utc(2031, 1, 1, 10));
    expect(entries.single.availableUntil, DateTime.utc(2031, 1, 1, 12));
  });

  test('offline entries carry the last known lock and feed lockedUntilFor',
      () async {
    await cache('Locked');
    api.byGroup['gA'] = [_item('Locked', lockedUntil: '2031-02-02T08:00:00Z')];
    await svc.refresh(groupId: 'gA', schoolCode: '1');

    final entries = await (() async {
      api.failWith = const ApiException(0, 'down', code: kApiNetwork);
      return svc.refresh(groupId: 'gA', schoolCode: '1');
    })();
    expect(entries.single.status, CatalogStatus.cachedOnly);
    expect(entries.single.lockedUntil, DateTime.utc(2031, 2, 2, 8));
    expect(TestCatalogService.lockedUntilFor('Locked'),
        DateTime.utc(2031, 2, 2, 8));
  });

  test('a lock removed on the server is forgotten at the next listing',
      () async {
    await cache('A');
    api.byGroup['gA'] = [_item('A', lockedUntil: '2031-02-02T08:00:00Z')];
    await svc.refresh(groupId: 'gA', schoolCode: '1');
    api.byGroup['gA'] = [_item('A')];
    await svc.refresh(groupId: 'gA', schoolCode: '1');
    api.failWith = const ApiException(0, 'down', code: kApiNetwork);
    final entries = await svc.refresh(groupId: 'gA', schoolCode: '1');
    expect(entries.single.lockedUntil, isNull);
  });

  group('roster cache', () {
    final rows = [
      {'id': 's1', 'name': 'Ali', 'student_code': 'S-1', 'done': true},
      {'id': 's2', 'name': 'Bobur', 'student_code': 'S-2', 'done': false},
    ];

    test('round trip keeps code and done for the same test', () async {
      await TestCache.putRoster('g1', 'T1', rows);
      final back = await TestCache.getRoster('g1', 'T1');
      expect(back, rows);
    });

    test('done belongs to one test: another test gets the roster without it',
        () async {
      await TestCache.putRoster('g1', 'T1', rows);
      final back = (await TestCache.getRoster('g1', 'T2'))!;
      expect(back.map((e) => e['student_code']), ['S-1', 'S-2']);
      expect(back.any((e) => e.containsKey('done')), isFalse);
    });

    test('an empty list never replaces a good one', () async {
      await TestCache.putRoster('g1', 'T1', rows);
      await TestCache.putRoster('g1', 'T1', const []);
      expect(await TestCache.getRoster('g1', 'T1'), rows);
    });

    test('unknown group is null', () async {
      expect(await TestCache.getRoster('nope', 'T1'), isNull);
    });
  });
}
