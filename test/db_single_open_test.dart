// F34: concurrent first calls to the lazy `db` getters open the file ONCE.
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('single_open_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tmp.path);
    await OfflineQueue.resetForTest();
    await TestCache.resetForTest();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await OfflineQueue.resetForTest();
    await TestCache.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test('OfflineQueue.db: three racing first calls open once', () async {
    final before = OfflineQueue.changes.value;
    final dbs = await Future.wait(
        [OfflineQueue.db, OfflineQueue.db, OfflineQueue.db]);
    expect(dbs[1], same(dbs[0]));
    expect(dbs[2], same(dbs[0]));
    // `changes` is bumped once per real open.
    expect(OfflineQueue.changes.value, before + 1);
  });

  test('OfflineQueue.db: a failed open is not cached, the next call retries',
      () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
      if (calls++ == 0) throw PlatformException(code: 'no-dir');
      return tmp.path;
    });
    await expectLater(OfflineQueue.db, throwsA(anything));
    expect(await OfflineQueue.db, isNotNull);
  });

  test('TestCache: three racing first calls open once', () async {
    TestCache.pathOverride = p.join(tmp.path, 'tc.db');
    TestCache.opensForTest = 0;
    await Future.wait([TestCache.all(), TestCache.all(), TestCache.all()]);
    expect(TestCache.opensForTest, 1);
  });
}
