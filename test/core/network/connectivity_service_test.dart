import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pingWithRetry', () {
    test('transient failure then success on retry is NOT reported as offline',
        () async {
      var attempts = 0;

      final result = await pingWithRetry(
        () async {
          attempts += 1;
          return attempts == 2;
        },
        timeout: const Duration(seconds: 3),
        retryDelay: Duration.zero,
      );

      expect(result.ok, isTrue);
      expect(attempts, 2);
    });

    test('two consecutive failures reports offline', () async {
      var attempts = 0;

      final result = await pingWithRetry(
        () async {
          attempts += 1;
          return false;
        },
        timeout: const Duration(seconds: 3),
        retryDelay: Duration.zero,
      );

      expect(result.ok, isFalse);
      expect(attempts, 2);
    });

    test('first attempt success does not trigger a retry', () async {
      var attempts = 0;

      final result = await pingWithRetry(
        () async {
          attempts += 1;
          return true;
        },
        timeout: const Duration(seconds: 3),
        retryDelay: Duration.zero,
      );

      expect(result.ok, isTrue);
      expect(attempts, 1);
    });
  });
}
