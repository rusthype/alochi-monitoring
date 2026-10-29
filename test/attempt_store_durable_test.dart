// Audit wave 2 #1: attempt records live in their own files with atomic
// writes (temp + flush + rename, previous good copy kept as .bak) instead of
// the single non-atomic shared_preferences.json a power cut can tear.

import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _rec(String student,
        {Map<String, dynamic>? answers, bool completed = false}) =>
    {
      'variant': 1,
      'answers': answers ?? <String, dynamic>{},
      if (completed) 'completed': true,
      'student_id': student,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    await QueueCrypto.encryptPayload('{}');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('attempt_store_');
    AttemptStore.useDirectoryForTest(tmp);
  });

  tearDown(() {
    AttemptStore.useDirectoryForTest(null);
    tmp.deleteSync(recursive: true);
  });

  List<File> files() => tmp.listSync().whereType<File>().toList();
  File mainFile(String testKey) => files()
      .firstWhere((f) => f.path.endsWith('.json') && f.path.contains(testKey));

  test('save/load round-trips through a file, not shared_preferences',
      () async {
    await AttemptStore.save('k1', _rec('A', answers: {'S/0': 2}));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('attempt_')), isEmpty);
    expect(files(), isNotEmpty);
    final back = await AttemptStore.load('k1');
    expect((back!['answers'] as Map)['S/0'], 2);
    // encrypted at rest like before
    expect(mainFile('k1').readAsStringSync(), startsWith('ENC1:'));
  });

  test('a torn (empty) main file falls back to the previous good copy',
      () async {
    await AttemptStore.save('k2', _rec('A', answers: {'S/0': 1}));
    await AttemptStore.save('k2', _rec('A', answers: {'S/0': 1, 'S/1': 2}));
    mainFile('k2').writeAsStringSync(''); // power cut left it empty
    final back = await AttemptStore.load('k2');
    expect(back, isNotNull);
    expect((back!['answers'] as Map).containsKey('S/0'), isTrue);
  });

  test('a garbage main file with no backup loads as null and saves still work',
      () async {
    await AttemptStore.save('k3', _rec('A', answers: {'S/0': 1}));
    for (final f in files().where((f) => !f.path.endsWith('.json'))) {
      f.deleteSync();
    }
    mainFile('k3').writeAsBytesSync(List<int>.filled(32, 0));
    expect(await AttemptStore.load('k3'), isNull);
    await AttemptStore.save('k3', _rec('A', answers: {'S/0': 3}));
    expect(((await AttemptStore.load('k3'))!['answers'] as Map)['S/0'], 3);
  });

  test('many unawaited saves end with the LAST one on disk', () async {
    for (var i = 0; i < 25; i++) {
      unawaited2(AttemptStore.save('k4', _rec('A', answers: {'S/0': i})));
    }
    await AttemptStore.save('k4', _rec('A', answers: {'S/0': 99}));
    expect(((await AttemptStore.load('k4'))!['answers'] as Map)['S/0'], 99);
    expect(files().where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  test('legacy record in shared_preferences is migrated lazily on first read',
      () async {
    // Produce a legacy blob with the old format through a prefs-only store.
    AttemptStore.useDirectoryForTest(null);
    await AttemptStore.save('k5', _rec('A', answers: {'S/0': 4}));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('attempt_k5'), isNotNull);

    AttemptStore.useDirectoryForTest(tmp);
    final back = await AttemptStore.load('k5');
    expect((back!['answers'] as Map)['S/0'], 4);
    expect(prefs.getString('attempt_k5'), isNull); // moved
    expect(files(), isNotEmpty);
    expect(await AttemptStore.load('k5'), isNotNull); // now from file
  });

  test('parking works with the file backend', () async {
    await AttemptStore.save('k6', _rec('A', answers: {'S/0': 2}));
    await AttemptStore.save('k6', _rec('B'));
    expect((await AttemptStore.load('k6'))!['student_id'], 'B');
    final a = await AttemptStore.loadForStudent('k6', 'A');
    expect((a!['answers'] as Map)['S/0'], 2);
  });

  test('listAll returns main and parked slots with their test keys', () async {
    await AttemptStore.save('k7', _rec('A', answers: {'S/0': 2}));
    await AttemptStore.save('k7', _rec('B', answers: {'S/0': 1}));
    await AttemptStore.save('other-key', _rec('C', answers: {'S/0': 1}));
    final all = await AttemptStore.listAll();
    expect(all.map((e) => e.testKey).toSet(), {'k7', 'other-key'});
    expect(all.where((e) => e.testKey == 'k7'), hasLength(2));
    expect(all.where((e) => e.isParked).single.record['student_id'], 'A');
  });

  test('clearEntry removes the main slot and its backup; clear does too',
      () async {
    await AttemptStore.save('k8', _rec('A', answers: {'S/0': 1}));
    await AttemptStore.save('k8', _rec('A', answers: {'S/0': 2}));
    await AttemptStore.clear('k8');
    expect(await AttemptStore.load('k8'), isNull);
    expect(files(), isEmpty);

    await AttemptStore.save('k9', _rec('A', answers: {'S/0': 1}));
    await AttemptStore.save('k9', _rec('B', answers: {'S/0': 1}));
    final parked =
        (await AttemptStore.listAll()).singleWhere((e) => e.isParked);
    await AttemptStore.clearEntry(parked);
    expect(await AttemptStore.loadForStudent('k9', 'A'), isNull);
    expect(await AttemptStore.loadForStudent('k9', 'B'), isNotNull);
  });

  test('keys with unsafe characters map to distinct safe file names', () async {
    await AttemptStore.save('a/b', _rec('A', answers: {'S/0': 1}));
    await AttemptStore.save('a_b', _rec('A', answers: {'S/0': 2}));
    expect(((await AttemptStore.load('a/b'))!['answers'] as Map)['S/0'], 1);
    expect(((await AttemptStore.load('a_b'))!['answers'] as Map)['S/0'], 2);
    final all = await AttemptStore.listAll();
    expect(all.map((e) => e.testKey).toSet(), {'a/b', 'a_b'});
  });

  group('wave 3', () {
    Future<void> writeRaw(String path, Map<String, dynamic> rec) async =>
        File(path).writeAsStringSync(
            await QueueCrypto.encryptPayload(jsonEncode(rec)));

    test('a crash between the two renames still loads the newest save',
        () async {
      await AttemptStore.save('k6', _rec('A', answers: {'S/0': 1}));
      await AttemptStore.save('k6', _rec('A', answers: {'S/0': 1, 'S/1': 2}));
      final main = mainFile('k6');
      // main -> .bak happened, tmp -> main did not: the newest copy (here the
      // `completed` marker) only exists as .tmp.
      main.renameSync('${main.path}.bak');
      await writeRaw('${main.path}.tmp',
          _rec('A', answers: {'S/0': 1, 'S/1': 2}, completed: true));

      final back = await AttemptStore.load('k6');
      expect(back!['completed'], isTrue);
      final all = await AttemptStore.listAll();
      expect(all.single.record['completed'], isTrue);
    });

    test('a torn .tmp is ignored in favour of the main file', () async {
      await AttemptStore.save('k7', _rec('A', answers: {'S/0': 5}));
      File('${mainFile('k7').path}.tmp').writeAsStringSync('ENC1:garbage');
      expect(((await AttemptStore.load('k7'))!['answers'] as Map)['S/0'], 5);
    });

    test('the displaced student\'s parked copy survives a failed main write',
        () async {
      await AttemptStore.save('k8', _rec('A', answers: {'S/0': 1}));
      await AttemptStore.save('k8', _rec('B', answers: {'S/0': 2})); // parks A
      // Block the temp file so the next main write throws.
      Directory('${tmp.path}/attempt_k8.json.tmp').createSync();
      await AttemptStore.save('k8', _rec('A', answers: {'S/0': 1, 'S/1': 1}));
      Directory('${tmp.path}/attempt_k8.json.tmp').deleteSync();

      final a = await AttemptStore.loadForStudent('k8', 'A');
      expect(a, isNotNull, reason: 'the only copy of A must not be deleted');
    });

    test('clearEntry keeps a record that changed since it was listed',
        () async {
      await AttemptStore.save('k9', _rec('A', answers: {'S/0': 1}));
      final listed = (await AttemptStore.listAll()).single;
      await AttemptStore.save('k9', _rec('A', answers: {'S/0': 1, 'S/1': 2}));
      await AttemptStore.clearEntry(listed);
      expect(((await AttemptStore.load('k9'))!['answers'] as Map).length, 2);

      final fresh = (await AttemptStore.listAll()).single;
      await AttemptStore.clearEntry(fresh);
      expect(await AttemptStore.load('k9'), isNull);
    });

    test(
        'a new attempt of the same student parks unsent answers of another '
        'test version instead of overwriting them', () async {
      await AttemptStore.save('k10', {
        ..._rec('A', answers: {'S/0': 1}),
        'attempt_id': 'old',
        'test_version': 1,
      });
      AttemptStore.useDirectoryForTest(
          tmp); // "restart": forget in-memory owner
      await AttemptStore.save('k10', {
        ..._rec('A', answers: {}),
        'attempt_id': 'new',
        'test_version': 2,
      });
      final all = await AttemptStore.listAll();
      expect(all, hasLength(2));
      final parked = all.singleWhere((e) => e.isParked);
      expect(parked.record['attempt_id'], 'old');
      expect(parked.record['answers'], {'S/0': 1});
      // The student's normal resume still finds the NEW attempt.
      expect((await AttemptStore.loadForStudent('k10', 'A'))!['attempt_id'],
          'new');
    });

    test('a transient legacy-migration failure is retried, not remembered',
        () async {
      final raw = await QueueCrypto.encryptPayload(
          jsonEncode(_rec('A', answers: {'S/0': 9})));
      SharedPreferences.setMockInitialValues({'attempt_k11': raw});
      final blocker = Directory('${tmp.path}/attempt_k11.json.tmp')
        ..createSync();
      expect(await AttemptStore.loadForStudent('k11', 'A'), isNull);
      blocker.deleteSync();
      final back = await AttemptStore.loadForStudent('k11', 'A');
      expect((back!['answers'] as Map)['S/0'], 9);
    });

    test(
        'F7: clear removes .tmp and .bak before the main file, so a cut '
        'part-way cannot resurrect the cleared record', () async {
      await AttemptStore.save('k12', _rec('A', answers: {'S/0': 1}));
      final path = mainFile('k12').path;
      File('$path.bak').writeAsStringSync('x');
      File('$path.tmp').writeAsStringSync('x');
      // Deleting the main path fails (it is a directory) - a stand-in for a
      // power cut right before the main delete: the rest must already be gone.
      File(path).deleteSync();
      Directory(path).createSync();
      await AttemptStore.clear('k12');
      expect(File('$path.tmp').existsSync(), isFalse);
      expect(File('$path.bak').existsSync(), isFalse);
    });
  });
}

void unawaited2(Future<void> f) {}
