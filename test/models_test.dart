import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/models/models.dart';

void main() {
  group('WrongAnswer.fromJson', () {
    test('parses a complete payload', () {
      final wa = WrongAnswer.fromJson({
        'position': 3,
        'subject': 'Math',
        'prompt': '2+2=?',
        'student_answer': '5',
        'correct_answer': '4',
        'student_text': '5',
        'correct_text': '4',
        'image': null,
      });
      expect(wa.position, 3);
      expect(wa.subject, 'Math');
    });

    test('falls back safely when fields are missing or wrong-typed', () {
      final wa = WrongAnswer.fromJson({'subject': 'Math'});
      expect(wa.position, 0);
      expect(wa.subject, 'Math');
      expect(wa.prompt, '');
      expect(wa.studentAnswer, '');
      expect(wa.correctAnswer, '');
    });
  });

  group('TestResult.toJson', () {
    test('includes duration_seconds when set', () {
      const result = TestResult(
        packageId: 'pkg-1',
        variant: 1,
        mathScore: 0,
        engScore: 0,
        totalPct: 0,
        answers: {},
        deviceId: 'test-device',
        durationSeconds: 754,
      );
      expect(result.toJson()['duration_seconds'], 754);
    });

    test('omits duration_seconds when null', () {
      const result = TestResult(
        packageId: 'pkg-1',
        variant: 1,
        mathScore: 0,
        engScore: 0,
        totalPct: 0,
        answers: {},
        deviceId: 'test-device',
      );
      expect(result.toJson().containsKey('duration_seconds'), false);
    });
  });
}
