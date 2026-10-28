// TestCatalogService.refresh() must never wipe the downloaded-test cache on an
// empty / partial / failed / FILTERED catalog response (2026-10-28 field
// incident). A cached test is only pruned when an UNFILTERED catalog that
// previously listed it stops listing it on 2 distinct calendar days.
import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends MonitoringApi {
  Object? next; // List<Map<String,dynamic>> to return, or an Object to throw
  final List<String> filtersSeen = [];
  @override
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    filtersSeen.add('$groupId|$schoolCode|$schoolId');
    final n = next;
    if (n is List<Map<String, dynamic>>) return n;
    throw n ?? StateError('unset');
  }

  @override
  Future<Map<String, dynamic>?> fetchTest(String testKey,
          {String? groupId,
          String? schoolCode,
          String? schoolId,
          String? authToken}) async =>
      {
        'title': testKey,
        'grade': 1,
        'version': 1,
        'parts': ['Math'],
        'variants': {
          '1': {
            'Math': [
              {'q': 'x'}
            ]
          }
        },
      };
}

Map<String, dynamic> _item(String key) =>
    {'test_key': key, 'title': key, 'grade': 1, 'version': 1};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeApi api;
  late TestCatalogService svc;
  var day = DateTime(2026, 10, 28, 9);

  setUp(() async {
    day = DateTime(2026, 10, 28, 9);
    TestCatalogService.clock = () => day;
    SharedPreferences.setMockInitialValues({});
    TestCache.enterMemoryMode(); // in-memory, no sqlite
    await TestCache.upsert('a', 'a', 1, 1, '{}');
    await TestCache.upsert('b', 'b', 1, 1, '{}');
    api = _FakeApi();
    svc = TestCatalogService(api);
  });

  tearDown(() {
    TestCache.exitMemoryMode();
    TestCatalogService.clock = DateTime.now;
  });

  Future<Set<String>> cachedKeys() async =>
      (await TestCache.all()).map((r) => r['test_key'] as String).toSet();

  /// a and b were both listed by an unfiltered request once.
  Future<void> listedOnce() async {
    api.next = [_item('a'), _item('b')];
    await svc.refresh();
  }

  void nextDay() => day = day.add(const Duration(days: 1));

  test('empty catalog deletes nothing, however often it repeats', () async {
    await listedOnce();
    api.next = <Map<String, dynamic>>[];
    for (var i = 0; i < 4; i++) {
      nextDay();
      await svc.refresh();
    }
    expect(await cachedKeys(), {'a', 'b'});
  });

  test('absent test: not deleted on the same day however often, deleted on '
      'the 2nd distinct day', () async {
    await listedOnce();
    api.next = [_item('a')];
    for (var i = 0; i < 5; i++) {
      await svc.refresh(); // all on day 1
    }
    expect(await cachedKeys(), {'a', 'b'});
    nextDay();
    await svc.refresh();
    expect(await cachedKeys(), {'a'});
  });

  test('reappearing test resets its counter', () async {
    await listedOnce();
    api.next = [_item('a')];
    await svc.refresh(); // b missed on day 1
    nextDay();
    api.next = [_item('a'), _item('b')];
    await svc.refresh(); // b back -> counter reset
    nextDay();
    api.next = [_item('a')];
    await svc.refresh(); // b missed once again, not twice
    expect(await cachedKeys(), {'a', 'b'});
    nextDay();
    await svc.refresh();
    expect(await cachedKeys(), {'a'});
  });

  test('a school/group-filtered refresh NEVER prunes', () async {
    await listedOnce();
    api.next = [_item('a')];
    for (var i = 0; i < 4; i++) {
      nextDay();
      await svc.refresh(groupId: 'g1');
      await svc.refresh(schoolCode: '39');
      await svc.refresh(schoolId: 'uuid-1');
    }
    expect(await cachedKeys(), {'a', 'b'});
    expect(api.filtersSeen.last, 'null|null|uuid-1');
  });

  test('a test downloaded for a school/group is never pruned by an '
      'unfiltered refresh (it hides it)', () async {
    expect(await svc.download('c', groupId: 'g1', schoolCode: '39'), isTrue);
    expect(await svc.download('d', schoolCode: '39'), isTrue);
    api.next = [_item('a')];
    for (var i = 0; i < 4; i++) {
      nextDay();
      await svc.refresh();
    }
    expect(await cachedKeys(), containsAll(['c', 'd', 'a']));
  });

  test('a test downloaded WITHOUT filters counts as unfiltered-listed',
      () async {
    expect(await svc.download('e'), isTrue);
    api.next = [_item('a')];
    await svc.refresh();
    nextDay();
    await svc.refresh();
    expect(await cachedKeys(), isNot(contains('e')));
  });

  test('test with a saved attempt is never pruned', () async {
    await listedOnce();
    await AttemptStore.save('b', {'variant': 1, 'answers': {}});
    api.next = [_item('a')];
    for (var i = 0; i < 4; i++) {
      nextDay();
      await svc.refresh();
    }
    expect(await cachedKeys(), {'a', 'b'});
  });

  test('failed fetch returns cached entries and deletes nothing', () async {
    await listedOnce();
    api.next = const ApiException(500, 'boom');
    nextDay();
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
