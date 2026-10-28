// TestCatalogService.refresh() must never wipe the downloaded-test cache on an
// empty / partial / failed catalog response (2026-10-28 field incident).
import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends MonitoringApi {
  Object? next; // List<Map<String,dynamic>> to return, or an Object to throw
  @override
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    final n = next;
    if (n is List<Map<String, dynamic>>) return n;
    throw n ?? StateError('unset');
  }
}

Map<String, dynamic> _item(String key) =>
    {'test_key': key, 'title': key, 'grade': 1, 'version': 1};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeApi api;
  late TestCatalogService svc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestCache.enterMemoryMode(); // in-memory, no sqlite
    await TestCache.upsert('a', 'a', 1, 1, '{}');
    await TestCache.upsert('b', 'b', 1, 1, '{}');
    api = _FakeApi();
    svc = TestCatalogService(api);
  });

  tearDown(TestCache.exitMemoryMode);

  Future<Set<String>> cachedKeys() async =>
      (await TestCache.all()).map((r) => r['test_key'] as String).toSet();

  test('empty catalog deletes nothing, however often it repeats', () async {
    api.next = <Map<String, dynamic>>[];
    for (var i = 0; i < 4; i++) {
      await svc.refresh();
    }
    expect(await cachedKeys(), {'a', 'b'});
  });

  test('partial catalog: absent test is deleted only on the 2nd refresh',
      () async {
    api.next = [_item('a')];
    await svc.refresh();
    expect(await cachedKeys(), {'a', 'b'});
    await svc.refresh();
    expect(await cachedKeys(), {'a'});
  });

  test('reappearing test resets its counter', () async {
    api.next = [_item('a')];
    await svc.refresh(); // b missed once
    api.next = [_item('a'), _item('b')];
    await svc.refresh(); // b back -> counter reset
    api.next = [_item('a')];
    await svc.refresh(); // b missed once again, not twice
    expect(await cachedKeys(), {'a', 'b'});
    await svc.refresh();
    expect(await cachedKeys(), {'a'});
  });

  test('test with a saved attempt is never pruned', () async {
    await AttemptStore.save('b', {'variant': 1, 'answers': {}});
    api.next = [_item('a')];
    for (var i = 0; i < 4; i++) {
      await svc.refresh();
    }
    expect(await cachedKeys(), {'a', 'b'});
  });

  test('failed fetch returns cached entries and deletes nothing', () async {
    api.next = const ApiException(500, 'boom');
    final r = await svc.refresh();
    expect(r.map((e) => e.testKey).toSet(), {'a', 'b'});
    expect(r.every((e) => e.status == CatalogStatus.cachedOnly), isTrue);
    expect(await cachedKeys(), {'a', 'b'});
  });

  test('TestCache.pruneNotIn with empty keep-set is a no-op', () async {
    await TestCache.pruneNotIn({});
    expect(await cachedKeys(), {'a', 'b'});
  });
}
