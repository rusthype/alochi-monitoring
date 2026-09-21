import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DiagnosticAnswerStore.openInMemory();
  });

  tearDown(() async => DiagnosticAnswerStore.reset());

  group('DiagnosticAnswerStore.saveAnswer', () {
    test('persists a new answer', () async {
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1',
        subject: 'math',
        questionIndex: 1,
        questionId: 'q1',
        selectedOption: 'B',
      );
      final rows = await DiagnosticAnswerStore.loadAll('att-1', subject: 'math');
      expect(rows, hasLength(1));
      expect(rows.first['selected_option'], 'B');
      expect(rows.first['synced'], 0);
    });

    test('re-answering the same question overwrites, not duplicates', () async {
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'math', questionIndex: 1,
        questionId: 'q1', selectedOption: 'B',
      );
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'math', questionIndex: 1,
        questionId: 'q1', selectedOption: 'C',
      );
      final rows = await DiagnosticAnswerStore.loadAll('att-1', subject: 'math');
      expect(rows, hasLength(1));
      expect(rows.first['selected_option'], 'C');
    });

    test('loadAll is scoped by subject', () async {
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'math', questionIndex: 1,
        questionId: 'm1', selectedOption: 'A',
      );
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'english', questionIndex: 1,
        questionId: 'e1', selectedOption: 'D',
      );
      final mathRows = await DiagnosticAnswerStore.loadAll('att-1', subject: 'math');
      final engRows = await DiagnosticAnswerStore.loadAll('att-1', subject: 'english');
      expect(mathRows, hasLength(1));
      expect(mathRows.first['selected_option'], 'A');
      expect(engRows, hasLength(1));
      expect(engRows.first['selected_option'], 'D');
    });
  });

  group('DiagnosticAnswerStore pending/sync tracking', () {
    test('pendingForAttempt returns only unsynced rows', () async {
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'math', questionIndex: 1,
        questionId: 'q1', selectedOption: 'A',
      );
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'math', questionIndex: 2,
        questionId: 'q2', selectedOption: 'B',
      );
      await DiagnosticAnswerStore.markSynced('att-1', ['q1']);
      final pending = await DiagnosticAnswerStore.pendingForAttempt('att-1');
      expect(pending, hasLength(1));
      expect(pending.first['question_id'], 'q2');
    });

    test('attemptsWithPending lists distinct attempt ids with unsynced rows', () async {
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'math', questionIndex: 1,
        questionId: 'q1', selectedOption: 'A',
      );
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-2', subject: 'math', questionIndex: 1,
        questionId: 'q1', selectedOption: 'A',
      );
      final attempts = await DiagnosticAnswerStore.attemptsWithPending();
      expect(attempts.toSet(), {'att-1', 'att-2'});
    });

    test('re-answering an already-synced question marks it unsynced again', () async {
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'math', questionIndex: 1,
        questionId: 'q1', selectedOption: 'A',
      );
      await DiagnosticAnswerStore.markSynced('att-1', ['q1']);
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'math', questionIndex: 1,
        questionId: 'q1', selectedOption: 'B',
      );
      final pending = await DiagnosticAnswerStore.pendingForAttempt('att-1');
      expect(pending, hasLength(1));
      expect(pending.first['selected_option'], 'B');
    });
  });

  group('DiagnosticAnswerStore.clearAttempt', () {
    test('removes every row for the attempt, both subjects', () async {
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'math', questionIndex: 1,
        questionId: 'q1', selectedOption: 'A',
      );
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'att-1', subject: 'english', questionIndex: 1,
        questionId: 'e1', selectedOption: 'B',
      );
      await DiagnosticAnswerStore.clearAttempt('att-1');
      expect(await DiagnosticAnswerStore.loadAll('att-1', subject: 'math'), isEmpty);
      expect(await DiagnosticAnswerStore.loadAll('att-1', subject: 'english'), isEmpty);
    });
  });
}
