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

  group('maxSetupExeVersion', () {
    test('picks the highest version among multiple accumulated assets', () {
      final assets = [
        {'name': 'AlochiMonitoring-1.0.0-Setup.exe'},
        {'name': 'AlochiMonitoring-1.0.45-Setup.exe'},
        {'name': 'AlochiMonitoring-1.0.20-Setup.exe'},
        {'name': 'alochi-monitoring-windows.zip'},
      ];
      expect(maxSetupExeVersion(assets), '1.0.45');
    });

    test('returns null when no matching asset exists', () {
      final assets = [
        {'name': 'alochi-monitoring-windows.zip'},
        {'name': 'alochi-monitoring.dmg'},
      ];
      expect(maxSetupExeVersion(assets), null);
    });

    test('returns null for an empty asset list', () {
      expect(maxSetupExeVersion(<dynamic>[]), null);
    });

    test('ignores malformed asset entries without crashing', () {
      final assets = [
        'not-a-map',
        {'name': 123},
        {'no_name_key': 'x'},
        {'name': 'AlochiMonitoring-1.0.44-Setup.exe'},
      ];
      expect(maxSetupExeVersion(assets), '1.0.44');
    });
  });
}
