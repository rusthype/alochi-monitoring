import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/core/db/diagnostic_kiosk_cache.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // DiagnosticKioskCache encrypts via QueueCrypto, which falls back to a
    // path_provider-backed key file when the OS keychain plugin has no test
    // implementation (see queue_crypto.dart) — mock it so that fallback
    // actually succeeds instead of leaving nothing persisted.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return Directory.systemTemp.path;
      }
      return null;
    });
  });

  group('DiagnosticKioskCache', () {
    test('returns null when nothing is cached yet', () async {
      final result = await DiagnosticKioskCache.load('schools');
      expect(result, isNull);
    });

    test('round-trips a saved list of rows', () async {
      final rows = [
        {'school_id': '1', 'school_name': '26-maktab'},
        {'school_id': '2', 'school_name': '5-maktab'},
      ];
      await DiagnosticKioskCache.save('schools', rows);

      final result = await DiagnosticKioskCache.load('schools');

      expect(result, isA<List>());
      expect((result as List).length, 2);
      expect(result[0]['school_name'], '26-maktab');
    });

    test('different cache keys do not collide', () async {
      await DiagnosticKioskCache.save('classes_1', [
        {'class_label': '4-A'}
      ]);
      await DiagnosticKioskCache.save('classes_2', [
        {'class_label': '5-B'}
      ]);

      final a = await DiagnosticKioskCache.load('classes_1');
      final b = await DiagnosticKioskCache.load('classes_2');

      expect((a as List).first['class_label'], '4-A');
      expect((b as List).first['class_label'], '5-B');
    });

    test('a newer save overwrites the older cached copy for the same key',
        () async {
      await DiagnosticKioskCache.save('schools', [
        {'school_id': '1'}
      ]);
      await DiagnosticKioskCache.save('schools', [
        {'school_id': '1'},
        {'school_id': '2'}
      ]);

      final result = await DiagnosticKioskCache.load('schools');

      expect((result as List).length, 2);
    });
  });
}
