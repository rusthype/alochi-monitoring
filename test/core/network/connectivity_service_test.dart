import 'dart:async';

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

    test(
        'does not hang when the retry wait is cancelled mid-flight '
        '(this is the real ConnectivityService.dispose() path)', () async {
      late void Function() cancelRetry;

      final future = pingWithRetry(
        () async => false, // always fails -> retry wait always kicks in
        timeout: const Duration(milliseconds: 50),
        // Long enough that if cancel() didn't actually unblock the wait,
        // the test below would time out and fail instead of hanging forever.
        retryDelay: const Duration(seconds: 30),
        delay: (d) {
          final gate = cancellableDelay(d);
          cancelRetry = gate.cancel;
          return gate.future;
        },
      );

      // Let the first attempt finish and the retry wait get scheduled.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      cancelRetry();

      await expectLater(
        future.timeout(const Duration(milliseconds: 500)),
        completes,
      );
    });
  });

  group('cancellableDelay', () {
    test('cancel() completes the future immediately, not the Timer',
        () async {
      final gate = cancellableDelay(const Duration(seconds: 30));
      var completed = false;
      unawaited(gate.future.then((_) => completed = true));

      gate.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(completed, isTrue);
    });

    test('calling cancel() twice is a no-op, does not throw', () async {
      final gate = cancellableDelay(const Duration(seconds: 30));
      gate.cancel();
      expect(gate.cancel, returnsNormally);
    });
  });
}
