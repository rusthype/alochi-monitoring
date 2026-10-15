import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/features/test/engine_host_screen.dart';

void main() {
  test(
      'same attempt (same testKey/studentId/started_at) -> same token, '
      'so a crash-replay dedupes instead of creating a second submission', () {
    final a = buildResultToken('mw1_b1_s42', 'A26-473', 1730000000000);
    final b = buildResultToken('mw1_b1_s42', 'A26-473', 1730000000000);
    expect(a, b);
  });

  test(
      'a genuinely different attempt (different started_at) -> different token',
      () {
    final a = buildResultToken('mw1_b1_s42', 'A26-473', 1730000000000);
    final b = buildResultToken('mw1_b1_s42', 'A26-473', 1730000999999);
    expect(a, isNot(b));
  });
}
