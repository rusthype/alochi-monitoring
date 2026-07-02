import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/core/db/attempt_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AttemptStore.loadForStudent', () {
    test('returns null when no attempt is saved', () async {
      final result = await AttemptStore.loadForStudent('test-key', 'A26-473');
      expect(result, isNull);
    });

    test('returns the saved attempt when student_id matches', () async {
      await AttemptStore.save('test-key', {
        'variant': 2,
        'answers': {'Math/0': 'a'},
        'student_id': 'A26-473',
      });

      final result = await AttemptStore.loadForStudent('test-key', 'A26-473');

      expect(result, isNotNull);
      expect(result!['variant'], 2);
    });

    test(
        'returns null when a DIFFERENT student opens the same test — '
        'prevents cross-student answer leak on a shared kiosk', () async {
      await AttemptStore.save('test-key', {
        'variant': 2,
        'answers': {'Math/0': 'a'},
        'student_id': 'A26-473', // student A abandoned this attempt
      });

      // Student B now opens the same test on the same kiosk.
      final result = await AttemptStore.loadForStudent('test-key', 'B31-009');

      expect(result, isNull);
    });

    test(
        'returns null when studentId is empty — manual-entry students have '
        'no reliable identifier to match against, so never resume', () async {
      await AttemptStore.save('test-key', {
        'variant': 2,
        'answers': {'Math/0': 'a'},
        'student_id': '', // another manually-entered student, also empty id
      });

      final result = await AttemptStore.loadForStudent('test-key', '');

      expect(result, isNull);
    });
  });
}
