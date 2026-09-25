import 'dart:io';

/// Picks the best candidate from an already-resolved address list — pure
/// logic, no I/O, so it's unit-testable without a real network interface.
String? pickBestLocalAddress(List<InternetAddress> addresses) {
  for (final addr in addresses) {
    if (!addr.isLoopback && !addr.isLinkLocal && addr.address.isNotEmpty) {
      return addr.address;
    }
  }
  return null;
}

/// Real LAN IP (e.g. 192.168.x.x / 10.x.x.x) of this machine's primary
/// network interface, or null if none found / lookup failed. Cheap local
/// OS call — safe to call on every heartbeat rather than caching once,
/// since a kiosk PC's LAN IP can change (Wi-Fi roam, cable swap).
Future<String?> getLocalIpAddress() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      final ip = pickBestLocalAddress(interface.addresses);
      if (ip != null) return ip;
    }
  } catch (_) {
    // No network / permission denied — heartbeat proceeds without local_ip.
  }
  return null;
}
