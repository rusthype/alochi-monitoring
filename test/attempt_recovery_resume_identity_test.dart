// Audit wave 6 R3: the sweeper honours the hub's session-resume answer only
// when it is about the stored attempt's student.
import 'package:alochi_monitoring/core/services/attempt_recovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _resp({Object? code, Object? id = 'S-1'}) => {
      'exists': true,
      'variant': 2,
      'remaining_seconds': 600,
      if (id != null) 'student_id': id,
      if (code != null) 'student_code': code,
    };

const _rec = {'variant': 2, 'student_id': 'S-1'};

void main() {
  int? remaining(Map<String, dynamic> r) =>
      AttemptRecoveryService.remainingFromResume(r, _rec);

  test('student_code equal to the stored attempt: honoured', () {
    expect(remaining(_resp(code: 'S-1')), 600);
  });

  test('student_code of another student: ignored', () {
    expect(remaining(_resp(code: 'S-2')), isNull);
  });

  test('student_code alone (no student_id) of another student: ignored', () {
    expect(remaining(_resp(code: 'S-2', id: null)), isNull);
  });

  test('older backend without student_code keeps the old checks', () {
    expect(remaining(_resp()), 600);
    expect(remaining(_resp(id: 'S-2')), isNull);
    expect(remaining({..._resp(), 'variant': 3}), isNull);
    expect(remaining({..._resp(), 'exists': false}), isNull);
  });
}
