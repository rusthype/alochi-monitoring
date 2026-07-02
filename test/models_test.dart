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
}
