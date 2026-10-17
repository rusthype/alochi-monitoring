// lib/core/local_server/lan_discovery.dart
//
// UDP discovery for the LAN hub (decision 4 of phase 3).
//
//  * [LanBroadcaster] (teacher PC): every 2 s, from EACH local IPv4 address,
//    sends `{"v":1,"name","ip","port","pack_label"}` to 255.255.255.255 and to
//    that address's directed broadcast. dart:io cannot report netmasks, so the
//    directed broadcast assumes a /24 (a.b.c.255); the limited broadcast
//    255.255.255.255 covers every other layout, and the clients' manual
//    IP:port entry is the final fallback.
//  * [LanDiscoveryListener] (student PC): collects those announcements.
//
// The announcement is public by design: it never contains the class code, a
// token, the pack PIN or the pack uuid. A listener also never trusts the
// `ip` field — it uses the datagram's real source address, so a forged
// announcement cannot point a student PC at a third machine.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

const int kLanDiscoveryPort = 8081;
const int kMaxAnnouncementBytes = 512;

/// Non-loopback, non-link-local IPv4 addresses of this machine.
Future<List<InternetAddress>> localIPv4Addresses() async {
  try {
    final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    return [
      for (final i in ifaces)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a
    ];
  } catch (e) {
    debugPrint('localIPv4Addresses failed: ${e.runtimeType}');
    return const [];
  }
}

/// One outgoing route: a local source address and where to aim at from it.
class BroadcastRoute {
  final InternetAddress local;
  final List<InternetAddress> targets;
  const BroadcastRoute(this.local, this.targets);
}

Future<List<BroadcastRoute>> defaultBroadcastRoutes() async {
  final routes = <BroadcastRoute>[];
  for (final a in await localIPv4Addresses()) {
    final o = a.rawAddress; // 4 bytes
    routes.add(BroadcastRoute(a, [
      InternetAddress('255.255.255.255'),
      InternetAddress('${o[0]}.${o[1]}.${o[2]}.255'),
    ]));
  }
  return routes;
}

/// The datagram payload. Kept tiny and secret-free on purpose.
Uint8List encodeAnnouncement({
  required String name,
  required String ip,
  required int port,
  required String packLabel,
}) =>
    Uint8List.fromList(utf8.encode(jsonEncode({
      'v': 1,
      'name': name,
      'ip': ip,
      'port': port,
      'pack_label': packLabel,
    })));

class LanBroadcaster {
  final String name;
  final int port;
  final String packLabel;
  final int discoveryPort;
  final Duration interval;
  final Future<List<BroadcastRoute>> Function() routes;

  LanBroadcaster({
    required this.name,
    required this.port,
    required this.packLabel,
    this.discoveryPort = kLanDiscoveryPort,
    this.interval = const Duration(seconds: 2),
    Future<List<BroadcastRoute>> Function()? routes,
  }) : routes = routes ?? defaultBroadcastRoutes;

  final Map<String, RawDatagramSocket> _sockets = {};
  Timer? _timer;
  bool _sending = false;
  bool _running = false;

  bool get running => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _tick();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    for (final s in _sockets.values) {
      s.close();
    }
    _sockets.clear();
  }

  Future<void> _tick() async {
    if (_sending || !_running) return;
    _sending = true;
    try {
      final rs = await routes();
      final live = rs.map((r) => r.local.address).toSet();
      // Drop sockets of interfaces that went away.
      for (final k in _sockets.keys.where((k) => !live.contains(k)).toList()) {
        _sockets.remove(k)?.close();
      }
      for (final r in rs) {
        try {
          final sock = _sockets[r.local.address] ??= await _bind(r.local);
          final data = encodeAnnouncement(
              name: name,
              ip: r.local.address,
              port: port,
              packLabel: packLabel);
          for (final t in r.targets) {
            sock.send(data, t, discoveryPort);
          }
        } catch (e) {
          // One broken adapter must not silence the others.
          _sockets.remove(r.local.address)?.close();
          debugPrint('LanBroadcaster: send failed (${e.runtimeType})');
        }
      }
    } finally {
      _sending = false;
    }
  }

  Future<RawDatagramSocket> _bind(InternetAddress local) async {
    final s = await RawDatagramSocket.bind(local, 0);
    s.broadcastEnabled = true;
    return s;
  }
}

/// A hub heard on the network.
class DiscoveredHub {
  final String name;
  final String ip;
  final int port;
  final String packLabel;
  final DateTime seenAt;
  const DiscoveredHub({
    required this.name,
    required this.ip,
    required this.port,
    required this.packLabel,
    required this.seenAt,
  });

  String get address => '$ip:$port';
}

/// Parses one datagram; null for anything that is not a well-formed v1
/// announcement. [sender] is the real source address (see file header).
DiscoveredHub? parseAnnouncement(Uint8List data, InternetAddress sender,
    {DateTime? now}) {
  if (data.isEmpty || data.length > kMaxAnnouncementBytes) return null;
  if (sender.type != InternetAddressType.IPv4) return null;
  try {
    final j = jsonDecode(utf8.decode(data));
    if (j is! Map || j['v'] != 1) return null;
    final name = j['name'];
    final label = j['pack_label'];
    final port = j['port'];
    if (name is! String || label is! String || port is! int) return null;
    if (port < 1 || port > 65535 || name.length > 64 || label.length > 32) {
      return null;
    }
    String clean(String s) =>
        String.fromCharCodes(s.codeUnits.where((c) => c >= 0x20 && c != 0x7f));
    return DiscoveredHub(
      name: clean(name),
      ip: sender.address,
      port: port,
      packLabel: clean(label),
      seenAt: now ?? DateTime.now(),
    );
  } catch (_) {
    return null;
  }
}

class LanDiscoveryListener {
  final int port;
  final InternetAddress? bindAddress;
  final Duration ttl;

  LanDiscoveryListener({
    this.port = kLanDiscoveryPort,
    this.bindAddress,
    this.ttl = const Duration(seconds: 7),
  });

  /// Hubs heard within [ttl], newest information per address.
  final ValueNotifier<List<DiscoveredHub>> hubs =
      ValueNotifier<List<DiscoveredHub>>(const []);

  /// True when the UDP port could not be opened (firewall, port in use):
  /// the UI then points the user to manual IP:port entry.
  final ValueNotifier<bool> bindFailed = ValueNotifier<bool>(false);

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  Timer? _expiry;
  final Map<String, DiscoveredHub> _seen = {};
  static const int _maxHubs = 64;
  static const int _maxPerIp = 4;

  Future<void> start() async {
    if (_socket != null) return;
    try {
      final s = await RawDatagramSocket.bind(
          bindAddress ?? InternetAddress.anyIPv4, port,
          reuseAddress: true);
      _socket = s;
      _sub = s.listen((e) {
        if (e != RawSocketEvent.read) return;
        // Drain: one event can cover several queued datagrams.
        for (var i = 0; i < 16; i++) {
          final d = s.receive();
          if (d == null) break;
          final hub = parseAnnouncement(d.data, d.address);
          if (hub == null) continue;
          if (!_seen.containsKey(hub.address)) {
            // A flood of fake hubs must not grow the list without bound, and
            // one source address gets only a few entries: it cannot push the
            // real hub (another address) out by filling ports (S-008).
            if (_seen.length >= _maxHubs) continue;
            if (_seen.values.where((h) => h.ip == hub.ip).length >= _maxPerIp) {
              continue;
            }
          }
          _seen[hub.address] = hub;
          _publish();
        }
      });
      _expiry = Timer.periodic(const Duration(seconds: 1), (_) => _publish());
    } catch (e) {
      debugPrint('LanDiscoveryListener: bind failed (${e.runtimeType})');
      bindFailed.value = true;
    }
  }

  void _publish() {
    final cutoff = DateTime.now().subtract(ttl);
    _seen.removeWhere((_, h) => h.seenAt.isBefore(cutoff));
    final list = _seen.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    hubs.value = list;
  }

  Future<void> stop() async {
    _expiry?.cancel();
    _expiry = null;
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    _seen.clear();
    hubs.value = const [];
  }
}
