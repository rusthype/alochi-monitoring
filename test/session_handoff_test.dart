import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/session/session_handoff.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_prefetch_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DiagnosticAnswerStore.openInMemory();
    DiagnosticPrefetchCache.instance.reset();
  });

  tearDown(() async {
    await DiagnosticAnswerStore.reset();
    DiagnosticPrefetchCache.instance.reset();
  });

  Future<void> answer(String q) => DiagnosticAnswerStore.saveAnswer(
        attemptId: 'a1',
        subject: 'math',
        questionIndex: 1,
        questionId: q,
        selectedOption: 'A',
      );

  test('clears attempt blob + prefetch; keeps UNSYNCED answers; idempotent',
      () async {
    await AttemptStore.save('diag_a1', {'x': 1});
    DiagnosticPrefetchCache.instance.peekCache['a1'] = {'math': {}};
    DiagnosticPrefetchCache.instance.peekCache['other'] = {'math': {}};
    await answer('synced-q');
    await DiagnosticAnswerStore.markSynced('a1', ['synced-q']);
    await answer('unsynced-q');

    await cleanSessionHandoff(attemptKey: 'diag_a1', attemptId: 'a1');
    await cleanSessionHandoff(attemptKey: 'diag_a1', attemptId: 'a1'); // again

    expect(await AttemptStore.load('diag_a1'), isNull);
    expect(
        DiagnosticPrefetchCache.instance.peekCache.containsKey('a1'), isFalse);
    // Other students' prefetch (offline readiness for the class) untouched.
    expect(DiagnosticPrefetchCache.instance.peekCache.containsKey('other'),
        isTrue);
    final left = await DiagnosticAnswerStore.loadAll('a1', subject: 'math');
    expect(left.map((r) => r['question_id']), ['unsynced-q']);
    expect(await DiagnosticAnswerStore.attemptsWithPending(), ['a1']);
  });
}
