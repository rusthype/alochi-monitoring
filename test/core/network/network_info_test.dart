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

  group('pickPrimaryMac', () {
    const ethernet = AdapterInfo(
      name: 'Ethernet',
      ifType: 6, // IANA ethernetCsmacd
      mac: 'AA:BB:CC:DD:EE:FF',
    );
    const wifi = AdapterInfo(
      name: 'Wi-Fi',
      ifType: 71, // IANA ieee80211
      mac: '11:22:33:44:55:66',
    );
    const hyperV = AdapterInfo(
      name: 'vEthernet (Default Switch)',
      ifType: 6,
      mac: '00:00:00:00:00:01',
    );
    const loopback = AdapterInfo(name: 'Loopback', ifType: 24, mac: '');

    test('matches the adapter holding the preferred name', () {
      final result =
          pickPrimaryMac([ethernet, wifi, hyperV, loopback], 'Wi-Fi');
      expect(result, '11:22:33:44:55:66');
    });

    test('skips virtual/Hyper-V adapters even when named as preferred', () {
      final result =
          pickPrimaryMac([ethernet, hyperV], 'vEthernet (Default Switch)');
      expect(result, 'AA:BB:CC:DD:EE:FF'); // falls back, hyperV excluded
    });

    test('falls back to first physical adapter when no name matches', () {
      final result = pickPrimaryMac([hyperV, ethernet, wifi], 'unknown');
      expect(result, 'AA:BB:CC:DD:EE:FF');
    });

    test('returns null when only virtual/loopback adapters exist', () {
      final result = pickPrimaryMac([hyperV, loopback], null);
      expect(result, isNull);
    });
  });
}
