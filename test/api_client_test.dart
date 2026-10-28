import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonitoringApi.fixImageUrl', () {
    test('does not double-encode an already percent-encoded URL', () {
      expect(MonitoringApi.fixImageUrl('https://cdn.example.com/a%20b.png'),
          'https://cdn.example.com/a%20b.png');
      expect(
          MonitoringApi.fixImageUrl('/media/q/a%2Fb%D0%B0.png?x=a%20b'),
          'https://api.alochi.org/media/q/a%2Fb%D0%B0.png?x=a%20b');
    });

    test('encodes spaces and Uzbek / Cyrillic letters exactly once', () {
      expect(MonitoringApi.fixImageUrl('/media/savol rasm.png'),
          'https://api.alochi.org/media/savol%20rasm.png');
      expect(MonitoringApi.fixImageUrl('/media/o\u2018quvchi/ғ.png'),
          'https://api.alochi.org/media/o%E2%80%98quvchi/%D2%93.png');
      expect(MonitoringApi.fixImageUrl('/media/Расм 1.png'),
          'https://api.alochi.org/media/%D0%A0%D0%B0%D1%81%D0%BC%201.png');
      // Mixed: an encoded part next to a raw one.
      expect(MonitoringApi.fixImageUrl('/media/a%20б в.png'),
          'https://api.alochi.org/media/a%20%D0%B1%20%D0%B2.png');
    });

    test('a stray % that is not an escape is encoded', () {
      expect(MonitoringApi.fixImageUrl('/media/100%.png'),
          'https://api.alochi.org/media/100%25.png');
      expect(MonitoringApi.fixImageUrl('/media/5%zz.png'),
          'https://api.alochi.org/media/5%25zz.png');
    });

    test('is idempotent', () {
      for (final u in ['/media/Расм 1.png', '/media/a b.png', '/m/100%.png']) {
        final once = MonitoringApi.fixImageUrl(u);
        expect(MonitoringApi.fixImageUrl(once), once);
      }
    });

    test('returns an empty string for null or blank URLs', () {
      expect(MonitoringApi.fixImageUrl(null), isEmpty);
      expect(MonitoringApi.fixImageUrl('   '), isEmpty);
    });

    test('normalizes relative image URLs for app image widgets', () {
      expect(
        MonitoringApi.fixImageUrl('media/questions/image 1.png?size=large'),
        'https://api.alochi.org/media/questions/image%201.png?size=large',
      );
      expect(
        MonitoringApi.fixImageUrl('/media//questions///image.png'),
        'https://api.alochi.org/media/questions/image.png',
      );
    });

    test('keeps already absolute and protocol-relative URLs valid', () {
      expect(
        MonitoringApi.fixImageUrl(' https://cdn.example.com/a b.png?x=1 '),
        'https://cdn.example.com/a%20b.png?x=1',
      );
      expect(
        MonitoringApi.fixImageUrl('//cdn.example.com/media/a b.png'),
        'https://cdn.example.com/media/a%20b.png',
      );
    });
  });
}
