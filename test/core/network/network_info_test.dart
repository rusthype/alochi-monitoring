import 'dart:io';
import 'package:alochi_monitoring/core/network/network_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  linuxSeatIdTests();
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

// Linux seat id (clone-safe machine id). Pure helpers, run on any host.
void linuxSeatIdTests() {
  group('linuxSeatId', () {
    test('is 32 hex chars and differs from the raw machine-id', () {
      const raw = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
      final id = linuxSeatId(machineId: raw, mac: 'AA:BB:CC:00:00:01')!;
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(id, isNot(raw));
    });

    test('cloned image (same machine-id) on different NICs -> different seats',
        () {
      const raw = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
      final a = linuxSeatId(machineId: raw, mac: 'AA:BB:CC:00:00:01');
      final b = linuxSeatId(machineId: raw, mac: 'AA:BB:CC:00:00:02');
      expect(a, isNot(b));
    });

    test('stable for identical inputs; MAC case-insensitive', () {
      expect(linuxSeatId(machineId: 'x', mac: 'aa:bb:cc:dd:ee:ff'),
          linuxSeatId(machineId: 'x', mac: 'AA:BB:CC:DD:EE:FF'));
    });

    test('falls back to machine-id alone, then MAC alone, then null', () {
      expect(linuxSeatId(machineId: 'x'), isNotNull);
      expect(linuxSeatId(machineId: 'x'),
          isNot(linuxSeatId(machineId: 'x', mac: 'AA:BB:CC:DD:EE:FF')));
      expect(linuxSeatId(mac: 'AA:BB:CC:DD:EE:FF'), isNotNull);
      expect(linuxSeatId(), isNull);
      expect(linuxSeatId(machineId: '  ', mac: ''), isNull);
    });
  });

  group('linuxPrimaryMac', () {
    late Directory net;
    setUp(() => net = Directory.systemTemp.createTempSync('netdir'));
    tearDown(() => net.deleteSync(recursive: true));

    void nic(String name, String mac, {bool physical = true}) {
      final d = Directory('${net.path}/$name')..createSync();
      File('${d.path}/address').writeAsStringSync('$mac\n');
      if (physical) Directory('${d.path}/device').createSync();
    }

    test('skips virtual NICs and the all-zero MAC, sorted by name', () {
      nic('docker0', '02:42:00:00:00:01', physical: false);
      nic('enp3s0', '00:00:00:00:00:00');
      nic('enp4s0', 'aa:bb:cc:dd:ee:ff');
      nic('wlp2s0', '11:22:33:44:55:66');
      expect(linuxPrimaryMac(netDir: net.path), 'AA:BB:CC:DD:EE:FF');
    });

    test('null when nothing physical / directory missing', () {
      nic('lo', '00:00:00:00:00:00', physical: false);
      expect(linuxPrimaryMac(netDir: net.path), isNull);
      expect(linuxPrimaryMac(netDir: '${net.path}/nope'), isNull);
    });
  });
}
