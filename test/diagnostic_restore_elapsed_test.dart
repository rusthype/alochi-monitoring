import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_test_runner_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('elapsed-based: remaining = total - elapsed, ignores wall clock', () {
    final saved = {
      'total_seconds': 1800,
      'elapsed_seconds': 600,
      // A long-expired legacy deadline must be ignored when elapsed exists.
      'deadline_epoch_ms': 1000,
    };
    expect(diagnosticRestoredRemainingSeconds(saved), 1200);
  });

  test('server elapsed wins when larger than local', () {
    final saved = {'total_seconds': 1800, 'elapsed_seconds': 600};
    expect(diagnosticRestoredRemainingSeconds(saved, serverElapsedSeconds: 900),
        900);
    expect(diagnosticRestoredRemainingSeconds(saved, serverElapsedSeconds: 10),
        1200);
  });

  test('outage does not count: same result however late we restore', () {
    final saved = {'total_seconds': 600, 'elapsed_seconds': 100};
    expect(
        diagnosticRestoredRemainingSeconds(saved,
            now: DateTime.now().add(const Duration(hours: 5))),
        500);
  });

  test('expired -> <= 0', () {
    final saved = {'total_seconds': 600, 'elapsed_seconds': 600};
    expect(diagnosticRestoredRemainingSeconds(saved)! <= 0, isTrue);
  });

  test('legacy record without elapsed falls back to deadline_epoch_ms', () {
    final now = DateTime(2026, 1, 1, 12);
    final saved = {
      'deadline_epoch_ms':
          now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
    };
    expect(diagnosticRestoredRemainingSeconds(saved, now: now), 600);
  });

  test('no timer info at all -> null', () {
    expect(diagnosticRestoredRemainingSeconds({}), isNull);
  });
}
