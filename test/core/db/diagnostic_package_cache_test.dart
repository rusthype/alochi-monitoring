import 'package:alochi_monitoring/core/db/diagnostic_package_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DiagnosticPackageCache.openInMemory();
  });

  tearDownAll(() => DiagnosticPackageCache.reset());

  group('DiagnosticPackageCache', () {
    test('put then get returns the same data', () async {
      final data = {
        'subject': 'math',
        'questions': [1, 2, 3]
      };
      await DiagnosticPackageCache.put('att-1', 'math', data);
      final result = await DiagnosticPackageCache.get('att-1', 'math');
      expect(result, isNotNull);
      expect(result!['subject'], equals('math'));
      expect(result['questions'], equals([1, 2, 3]));
    });

    test('get returns null for non-existent key', () async {
      expect(
          await DiagnosticPackageCache.get('att-x', 'no_such_subject'), isNull);
    });

    test('put replaces an existing entry for the same attempt+subject',
        () async {
      await DiagnosticPackageCache.put('att-2', 'english', {'v': 1});
      await DiagnosticPackageCache.put('att-2', 'english', {'v': 2});
      final result = await DiagnosticPackageCache.get('att-2', 'english');
      expect(result!['v'], equals(2));
    });

    test('delete removes the entry', () async {
      await DiagnosticPackageCache.put('att-3', 'math', {'v': 1});
      await DiagnosticPackageCache.delete('att-3', 'math');
      expect(await DiagnosticPackageCache.get('att-3', 'math'), isNull);
    });

    test('different attempts with the same subject do not collide', () async {
      await DiagnosticPackageCache.put('att-4', 'math', {'v': 'a'});
      await DiagnosticPackageCache.put('att-5', 'math', {'v': 'b'});
      expect((await DiagnosticPackageCache.get('att-4', 'math'))!['v'], 'a');
      expect((await DiagnosticPackageCache.get('att-5', 'math'))!['v'], 'b');
    });

    test('putSubjectList/getSubjectList round-trip', () async {
      await DiagnosticPackageCache.putSubjectList('att-6', ['math', 'english']);
      final subjects = await DiagnosticPackageCache.getSubjectList('att-6');
      expect(subjects, ['math', 'english']);
    });

    test('getSubjectList returns null when never written', () async {
      expect(await DiagnosticPackageCache.getSubjectList('att-never'), isNull);
    });
  });
}
