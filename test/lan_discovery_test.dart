// UDP discovery (phase 3, decision 4): the announcement is secret-free and
// a real loopback datagram makes it from broadcaster to listener.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/local_server/lan_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

Future<int> _freeUdpPort() async {
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  s.close();
  return port;
}

void main() {
  final loop = InternetAddress.loopbackIPv4;

  test('announcement has exactly the five public fields and no secrets', () {
    final bytes = encodeAnnouncement(
        name: 'Teacher PC', ip: '192.168.1.5', port: 8080, packLabel: '26');
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(j.keys.toSet(), {'v', 'name', 'ip', 'port', 'pack_label'});
    expect(j['v'], 1);
    final text = utf8.decode(bytes).toLowerCase();
    for (final secret in ['code', 'token', 'pin', 'uuid', 'secret', 'key']) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
    expect(bytes.length, lessThan(kMaxAnnouncementBytes));
  });

  test('parse: uses the datagram SOURCE address, not the advertised ip', () {
    final data = encodeAnnouncement(
        name: 'Hub', ip: '6.6.6.6', port: 8081, packLabel: '12');
    final hub = parseAnnouncement(data, InternetAddress('10.0.0.7'));
    expect(hub, isNotNull);
    expect(hub!.ip, '10.0.0.7'); // a forged ip cannot redirect students
    expect(hub.address, '10.0.0.7:8081');
    expect(hub.packLabel, '12');
  });

  test('parse rejects junk, wrong version, bad ports and oversize', () {
    final src = InternetAddress('10.0.0.7');
    Uint8List b(Object o) => Uint8List.fromList(utf8.encode(jsonEncode(o)));
    expect(parseAnnouncement(Uint8List(0), src), isNull);
    expect(parseAnnouncement(b('x'), src), isNull);
    expect(
        parseAnnouncement(
            b({'v': 2, 'name': 'a', 'port': 1, 'pack_label': ''}), src),
        isNull);
    expect(
        parseAnnouncement(
            b({'v': 1, 'name': 'a', 'port': 0, 'pack_label': ''}), src),
        isNull);
    expect(
        parseAnnouncement(
            b({'v': 1, 'name': 'a', 'port': 70000, 'pack_label': ''}), src),
        isNull);
    expect(
        parseAnnouncement(
            b({'v': 1, 'name': 5, 'port': 80, 'pack_label': ''}), src),
        isNull);
    expect(
        parseAnnouncement(
            b({'v': 1, 'name': 'n' * 65, 'port': 80, 'pack_label': ''}), src),
        isNull);
    expect(
        parseAnnouncement(Uint8List(kMaxAnnouncementBytes + 1), src), isNull);
    expect(
        parseAnnouncement(
            b({'v': 1, 'name': 'a', 'port': 80, 'pack_label': 'l'}),
            InternetAddress('::1')),
        isNull);
  });

  test('real UDP over loopback: broadcaster -> listener', () async {
    final port = await _freeUdpPort();
    final listener = LanDiscoveryListener(
        port: port, bindAddress: loop, ttl: const Duration(milliseconds: 600));
    await listener.start();
    addTearDown(listener.stop);
    expect(listener.bindFailed.value, isFalse);

    final b = LanBroadcaster(
      name: 'Loopback Hub',
      port: 8123,
      packLabel: '77',
      discoveryPort: port,
      interval: const Duration(milliseconds: 100),
      routes: () async => [
        BroadcastRoute(loop, [loop])
      ],
    );
    await b.start();
    addTearDown(b.stop);

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (listener.hubs.value.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(listener.hubs.value, hasLength(1));
    final hub = listener.hubs.value.single;
    expect(hub.name, 'Loopback Hub');
    expect(hub.address, '127.0.0.1:8123');
    expect(hub.packLabel, '77');

    // Stop announcing: the entry expires on its own.
    await b.stop();
    final gone = DateTime.now().add(const Duration(seconds: 5));
    while (listener.hubs.value.isNotEmpty && DateTime.now().isBefore(gone)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(listener.hubs.value, isEmpty);
  });

  test('a busy UDP port is reported, not thrown', () async {
    final taken = await RawDatagramSocket.bind(loop, 0, reuseAddress: false);
    addTearDown(taken.close);
    final l = LanDiscoveryListener(port: taken.port, bindAddress: loop);
    await l.start();
    addTearDown(l.stop);
    expect(l.bindFailed.value, isTrue);
  });
}
