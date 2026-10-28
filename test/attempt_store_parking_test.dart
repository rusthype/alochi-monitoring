// Audit E-08 / F30 / C6: a second student starting the same test on the same
// PC must not destroy the first student's unfinished or completed-but-unsent
// attempt; the first student gets it back on return.

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

  setUpAll(() async {
    await QueueCrypto.encryptPayload('{}');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('second student seeding the same test parks the first one\'s answers',
      () async {
    await AttemptStore.save('t1', _rec('A', answers: {'S/0': 2}));
    // Student B starts the same test: runner_dispatch seeds an empty record.
    await AttemptStore.save('t1', _rec('B'));

    // B owns the main slot ...
    expect((await AttemptStore.load('t1'))!['student_id'], 'B');
    expect(await AttemptStore.loadForStudent('t1', 'B'), isNotNull);
    // ... and A still gets their answers back.
    final a = await AttemptStore.loadForStudent('t1', 'A');
    expect(a, isNotNull);
    expect((a!['answers'] as Map)['S/0'], 2);
  });

  test('a completed-but-unsent record is parked too', () async {
    await AttemptStore.save('t2', _rec('A', completed: true));
    await AttemptStore.save('t2', _rec('B', answers: {'S/0': 1}));
    final a = await AttemptStore.loadForStudent('t2', 'A');
    expect(a!['completed'], isTrue);
  });

  test('A resuming takes the main slot back and parks B', () async {
    await AttemptStore.save('t3', _rec('A', answers: {'S/0': 1}));
    await AttemptStore.save('t3', _rec('B', answers: {'S/0': 3}));
    // A returns (loaded from the park) and the engine saves again.
    final a = await AttemptStore.loadForStudent('t3', 'A');
    await AttemptStore.save('t3', {
      ...a!,
      'answers': {'S/0': 1, 'S/1': 0}
    });

    expect((await AttemptStore.load('t3'))!['student_id'], 'A');
    final b = await AttemptStore.loadForStudent('t3', 'B');
    expect((b!['answers'] as Map)['S/0'], 3);
  });

  test(
      'an empty seeded record is not worth parking; clear leaves parked '
      'records of others', () async {
    await AttemptStore.save('t4', _rec('A')); // nothing typed
    await AttemptStore.save('t4', _rec('B', answers: {'S/0': 1}));
    expect(await AttemptStore.loadForStudent('t4', 'A'), isNull);

    await AttemptStore.save('t4', _rec('C', answers: {'S/0': 2}));
    await AttemptStore.clear('t4'); // C submitted
    expect(await AttemptStore.load('t4'), isNull);
    expect(await AttemptStore.loadForStudent('t4', 'B'), isNotNull);
  });

  test('re-saving by the owner is a plain overwrite', () async {
    await AttemptStore.save('t5', _rec('A', answers: {'S/0': 1}));
    await AttemptStore.save('t5', _rec('A', answers: {'S/0': 1, 'S/1': 1}));
    final a = await AttemptStore.loadForStudent('t5', 'A');
    expect((a!['answers'] as Map).length, 2);
  });
}
