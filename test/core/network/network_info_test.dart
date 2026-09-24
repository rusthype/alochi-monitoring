import 'dart:io';
import 'package:alochi_monitoring/core/network/network_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickBestLocalAddress', () {
    test('skips loopback and link-local, picks first real LAN address', () {
      final result = pickBestLocalAddress([
        InternetAddress('127.0.0.1'),
        InternetAddress('169.254.1.5'),
        InternetAddress('192.168.1.45'),
      ]);
      expect(result, '192.168.1.45');
    });

    test('returns null when nothing usable is present', () {
      final result = pickBestLocalAddress([InternetAddress('127.0.0.1')]);
      expect(result, isNull);
    });
  });
}
