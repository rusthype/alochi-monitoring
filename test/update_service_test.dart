// test/update_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/services/update_service.dart';

void main() {
  group('isNewerVersion', () {
    test('numeric comparison, not string comparison', () {
      expect(isNewerVersion('1.0.45', '1.0.44'), true);
      // String comparison would wrongly say "1.0.9" > "1.0.10" is false-negative
      // in the other direction too — this must be numeric.
      expect(isNewerVersion('1.0.9', '1.0.10'), false);
      expect(isNewerVersion('1.0.10', '1.0.9'), true);
    });

    test('equal versions are not "newer"', () {
      expect(isNewerVersion('1.0.44', '1.0.44'), false);
    });

    test('malformed version strings return false, never throw', () {
      expect(isNewerVersion('not-a-version', '1.0.44'), false);
      expect(isNewerVersion('1.0.45', 'not-a-version'), false);
      expect(isNewerVersion('', ''), false);
    });
  });
}
