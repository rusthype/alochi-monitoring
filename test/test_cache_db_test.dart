import 'package:alochi_monitoring/core/db/test_cache_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await TestCacheDb.openInMemory();
  });

  tearDownAll(() => TestCacheDb.reset());

  group('TestCacheDb', () {
    test('put then get returns the same data', () async {
      final data = {'test_key': 'abc', 'title': 'Test ABC', 'grade': 4};
      await TestCacheDb.put('abc', 3, data);
      final result = await TestCacheDb.get('abc');
      expect(result, isNotNull);
      expect(result!['title'], equals('Test ABC'));
      expect(result['grade'], equals(4));
    });

    test('cachedVersion returns the stored version', () async {
      await TestCacheDb.put('xyz', 7, {'title': 'XYZ'});
      expect(await TestCacheDb.cachedVersion('xyz'), equals(7));
    });

    test('get returns null for non-existent key', () async {
      expect(await TestCacheDb.get('no_such_key'), isNull);
    });

    test('put replaces existing entry', () async {
      await TestCacheDb.put('rep', 1, {'v': 1});
      await TestCacheDb.put('rep', 2, {'v': 2});
      final result = await TestCacheDb.get('rep');
      expect(result!['v'], equals(2));
      expect(await TestCacheDb.cachedVersion('rep'), equals(2));
    });
  });
}
