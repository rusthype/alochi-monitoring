import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonitoringApi.fixImageUrl', () {
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
