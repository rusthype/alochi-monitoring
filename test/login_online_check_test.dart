import 'package:alochi_monitoring/features/auth/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checkOnlineWithRetry retries failed pings and returns true', () async {
    var attempts = 0;

    final online = await checkOnlineWithRetry(
      () async {
        attempts += 1;
        return attempts == 3;
      },
      retryDelay: Duration.zero,
    );

    expect(online, isTrue);
    expect(attempts, 3);
  });

  test('checkOnlineWithRetry returns false after all attempts fail', () async {
    var attempts = 0;

    final online = await checkOnlineWithRetry(
      () async {
        attempts += 1;
        return false;
      },
      retryDelay: Duration.zero,
    );

    expect(online, isFalse);
    expect(attempts, 3);
  });
}
