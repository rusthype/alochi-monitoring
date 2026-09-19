import 'package:alochi_monitoring/core/db/diagnostic_history_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DiagnosticHistoryDb.openInMemory();
  });

  tearDown(() async => DiagnosticHistoryDb.reset());

  group('DiagnosticHistoryDb.upsert', () {
    test('inserts a new row keyed by attempt_id', () async {
      await DiagnosticHistoryDb.upsert(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        classLabel: '4-A',
        school: '56-maktab',
        status: 'pending',
      );
      final rows = await DiagnosticHistoryDb.getAll();
      expect(rows, hasLength(1));
      expect(rows.first['attempt_id'], equals('att-1'));
      expect(rows.first['status'], equals('pending'));
      expect(rows.first['math_score'], isNull);
      expect(rows.first['english_score'], isNull);
    });

    test(
        'a second upsert for the same attempt_id updates the row in place, '
        'not inserting a duplicate', () async {
      await DiagnosticHistoryDb.upsert(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        classLabel: '4-A',
        school: '56-maktab',
        status: 'pending',
      );
      await DiagnosticHistoryDb.upsert(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        classLabel: '4-A',
        school: '56-maktab',
        status: 'sent',
        mathScore: 87,
      );
      final rows = await DiagnosticHistoryDb.getAll();
      expect(rows, hasLength(1));
      expect(rows.first['status'], equals('sent'));
      expect(rows.first['math_score'], equals(87));
    });

    test(
        'a null score arg leaves an already-recorded score untouched — '
        'English finishing must not erase Math\'s score', () async {
      await DiagnosticHistoryDb.upsert(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        classLabel: '4-A',
        school: '56-maktab',
        status: 'sent',
        mathScore: 90,
      );
      await DiagnosticHistoryDb.upsert(
        attemptId: 'att-1',
        studentName: 'Aliyev Ali',
        classLabel: '4-A',
        school: '56-maktab',
        status: 'sent',
        englishScore: 75,
      );
      final rows = await DiagnosticHistoryDb.getAll();
      expect(rows.first['math_score'], equals(90));
      expect(rows.first['english_score'], equals(75));
    });
  });

  group('DiagnosticHistoryDb.markSent', () {
    test('flips status to sent and backfills scores', () async {
      await DiagnosticHistoryDb.upsert(
        attemptId: 'att-2',
        studentName: 'Valiyeva Vali',
        classLabel: '5-B',
        school: '12-maktab',
        status: 'pending',
      );
      await DiagnosticHistoryDb.markSent(
          attemptId: 'att-2', mathScore: 60, englishScore: 70);
      final rows = await DiagnosticHistoryDb.getAll();
      expect(rows.first['status'], equals('sent'));
      expect(rows.first['math_score'], equals(60));
      expect(rows.first['english_score'], equals(70));
    });

    test('is a no-op when the attempt_id has no row', () async {
      await DiagnosticHistoryDb.markSent(attemptId: 'no-such-attempt');
      final rows = await DiagnosticHistoryDb.getAll();
      expect(rows, isEmpty);
    });
  });

  group('one-day retention', () {
    Future<void> insertAt(String attemptId, DateTime when) async {
      final d = await DiagnosticHistoryDb.db;
      await d.insert('diagnostic_history', {
        'attempt_id': attemptId,
        'student_name': 'X',
        'class_label': '4-A',
        'school': 'S',
        'status': 'sent',
        'date_taken': when.millisecondsSinceEpoch,
      });
    }

    test('getAll excludes a row from yesterday and keeps a row from today',
        () async {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(minutes: 1));
      await insertAt('yesterday-att', yesterday);
      await insertAt('today-att', now);

      final rows = await DiagnosticHistoryDb.getAll();

      expect(rows.map((r) => r['attempt_id']), contains('today-att'));
      expect(
          rows.map((r) => r['attempt_id']), isNot(contains('yesterday-att')));
    });

    test('purgeOldEntries deletes yesterday\'s row, not today\'s', () async {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(minutes: 1));
      await insertAt('yesterday-att', yesterday);
      await insertAt('today-att', now);

      final deleted = await DiagnosticHistoryDb.purgeOldEntries();
      expect(deleted, equals(1));

      final d = await DiagnosticHistoryDb.db;
      final remaining = await d.query('diagnostic_history');
      expect(remaining, hasLength(1));
      expect(remaining.first['attempt_id'], equals('today-att'));
    });
  });

  test('getAll orders by date_taken descending', () async {
    await DiagnosticHistoryDb.upsert(
      attemptId: 'older',
      studentName: 'A',
      classLabel: '4-A',
      school: 'S',
      status: 'sent',
    );
    await Future.delayed(const Duration(milliseconds: 5));
    await DiagnosticHistoryDb.upsert(
      attemptId: 'newer',
      studentName: 'B',
      classLabel: '4-A',
      school: 'S',
      status: 'pending',
    );
    final rows = await DiagnosticHistoryDb.getAll();
    expect(rows.first['attempt_id'], equals('newer'));
    expect(rows.last['attempt_id'], equals('older'));
  });
}
