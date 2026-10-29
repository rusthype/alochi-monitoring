// F33: concurrent readiness checks all wait for the ONE known-missing load.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/cache/test_image_store.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('concurrent gate checks see the persisted known-missing set', () async {
    const url = 'https://img.test/gone.png';
    SharedPreferences.setMockInitialValues({
      'known_missing_image_urls': [url],
    });
    TestCatalogService.resetKnownMissingForTest();
    final dir = Directory.systemTemp.createTempSync('km_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = TestImageStore(
        root: Directory('${dir.path}/test_images'),
        client: MockClient((r) async => http.Response('', 404)));
    await store.init();
    final svc = TestCatalogService(MonitoringApi(), store: store);
    final data = {
      'variants': {
        '1': {
          'S': [
            {'img': url}
          ]
        }
      }
    };

    // Both started before either load could finish.
    final results = await Future.wait([
      svc.testImagesComplete(data),
      svc.testImagesComplete(data),
      svc.testImagesComplete(data),
    ]);
    expect(results, [true, true, true]);
  });
}
