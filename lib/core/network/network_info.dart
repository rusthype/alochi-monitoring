import 'dart:convert' show utf8;
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:win32/win32.dart';

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

// ── Seat-binding identity (Windows kiosk) ───────────────────────────────────

String? _cachedMachineGuid;
bool _machineGuidResolved = false;

/// Stable per-Windows-installation id (`HKLM\SOFTWARE\Microsoft\Cryptography
/// \MachineGuid`), sent as the seat-binding `machine_id` on every heartbeat.
/// `RRF_SUBKEY_WOW6464KEY` forces the 64-bit registry view explicitly — this
/// key is WOW6432Node-redirected, so a 32-bit process without that flag
/// would be silently pointed at the (usually empty) 32-bit mirror instead.
/// Resolved once and cached: the value never changes while Windows is
/// running. Linux: [linuxSeatId]. macOS and any registry failure return null
/// — the ping/frame calls proceed without machine_id either way.
String? machineGuid() {
  if (_machineGuidResolved) return _cachedMachineGuid;
  _machineGuidResolved = true;
  if (Platform.isLinux) {
    _cachedMachineGuid = linuxSeatId(
      machineId: _readLinuxMachineId(),
      mac: linuxPrimaryMac(),
    );
    return _cachedMachineGuid;
  }
  if (!Platform.isWindows) return null;
  final subKey =
      'SOFTWARE\\Microsoft\\Cryptography'.toNativeUtf16(allocator: calloc);
  final valueName = 'MachineGuid'.toNativeUtf16(allocator: calloc);
  final dataSize = calloc<Uint32>()..value = 256;
  final buffer = calloc<Uint8>(256);
  try {
    final result = RegGetValue(
      HKEY_LOCAL_MACHINE,
      subKey,
      valueName,
      RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY,
      nullptr,
      buffer,
      dataSize,
    );
    if (result == ERROR_SUCCESS) {
      _cachedMachineGuid = buffer.cast<Utf16>().toDartString();
    }
  } catch (_) {
    // Registry unavailable/denied — heartbeat proceeds without machine_id.
  } finally {
    calloc.free(subKey);
    calloc.free(valueName);
    calloc.free(dataSize);
    calloc.free(buffer);
  }
  return _cachedMachineGuid;
}

// ── Linux seat id ───────────────────────────────────────────────────────────
// /etc/machine-id alone is NOT a seat key: a lab image cloned onto N PCs
// carries the same id, and the backend's UniqueConstraint(school, machine_id)
// would collapse them into one seat. Mixing in the primary NIC MAC separates
// clones while staying stable across reboots on one PC.

String? _readLinuxMachineId() {
  for (final path in const ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
    try {
      final id = File(path).readAsStringSync().trim();
      if (id.isNotEmpty) return id;
    } catch (_) {}
  }
  return null;
}

/// First physical NIC's MAC (upper-case `AA:BB:..`) under [netDir]
/// (`/sys/class/net`), or null. Only NICs with a `device` link count (skips
/// lo/docker/veth/bridges). Synchronous so [machineGuid] can stay synchronous.
@visibleForTesting
String? linuxPrimaryMac({String netDir = '/sys/class/net'}) {
  try {
    final dirs = Directory(netDir).listSync()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final d in dirs) {
      if (!Directory('${d.path}/device').existsSync()) continue;
      try {
        final mac = File('${d.path}/address').readAsStringSync().trim();
        if (mac.isNotEmpty && mac != '00:00:00:00:00:00') {
          return mac.toUpperCase();
        }
      } catch (_) {}
    }
  } catch (_) {}
  return null;
}

/// Seat id: first 32 hex chars of sha256 over machine-id and MAC. Machine-id
/// only -> hash of that alone; MAC only -> hash of that; neither -> null.
@visibleForTesting
String? linuxSeatId({String? machineId, String? mac}) {
  final id = machineId?.trim() ?? '';
  final m = mac?.trim().toUpperCase() ?? '';
  if (id.isEmpty && m.isEmpty) return null;
  final seed = m.isEmpty
      ? 'alochi-linux|$id'
      : 'alochi-linux|$id|$m';
  return sha256.convert(utf8.encode(seed)).toString().substring(0, 32);
}

/// One physical network adapter's identity + link-layer address — pure data
/// pulled out of the win32 `IP_ADAPTER_ADDRESSES_LH` linked list, so
/// [pickPrimaryMac] is unit-testable without a real NIC.
class AdapterInfo {
  final String name;
  final int ifType;
  final String mac; // 'AA:BB:CC:DD:EE:FF', or '' when no physical address.
  const AdapterInfo({
    required this.name,
    required this.ifType,
    required this.mac,
  });
}

const int _ifTypeEthernetCsmacd = 6; // IANA ifType: ethernetCsmacd
const int _ifTypeIeee80211 = 71; // IANA ifType: ieee80211 (Wi-Fi)
// AF_UNSPEC — not exported by package:win32 (lives in its winsock
// constants file, which the barrel doesn't re-export); the value is fixed
// by the Win32 ABI, so it's safe to inline here.
const int _afUnspec = 0;

const List<String> _virtualAdapterNameFragments = [
  'virtual',
  'vethernet',
  'loopback',
  'vpn',
  'hyper-v',
];

bool _isPhysicalAdapter(AdapterInfo a) {
  if (a.mac.isEmpty) return false;
  if (a.ifType != _ifTypeEthernetCsmacd && a.ifType != _ifTypeIeee80211) {
    return false;
  }
  final lowerName = a.name.toLowerCase();
  return !_virtualAdapterNameFragments.any(lowerName.contains);
}

/// Picks the MAC of whichever physical (Ethernet/Wi-Fi, non-virtual/VPN/
/// Hyper-V) adapter is named [preferredAdapterName] — the adapter already
/// holding this machine's primary LAN IP per [getLocalIpAddress] — falling
/// back to the first physical adapter with a MAC if no name match is found.
/// Pure logic, unit-testable without real adapters.
String? pickPrimaryMac(
    List<AdapterInfo> adapters, String? preferredAdapterName) {
  final physical = adapters.where(_isPhysicalAdapter).toList();
  if (preferredAdapterName != null && preferredAdapterName.isNotEmpty) {
    for (final a in physical) {
      if (a.name.toLowerCase() == preferredAdapterName.toLowerCase()) {
        return a.mac;
      }
    }
  }
  return physical.isEmpty ? null : physical.first.mac;
}

String? _cachedMac;
bool _macResolved = false;

/// This machine's primary physical-adapter MAC address (display-only —
/// MachineGuid is the seat-binding key, see [machineGuid]), cached per
/// app-run. Matched to [getLocalIpAddress]'s adapter by friendly name
/// rather than re-parsing win32 sockaddrs, since `dart:io`'s
/// `NetworkInterface.name` already ties the same adapter's friendly name to
/// that IP on Windows.
/// ponytail: name-based match, not sockaddr IP match — upgrade to parsing
/// `FirstUnicastAddress` directly if a name mismatch is ever observed.
Future<String?> primaryMac() async {
  if (_macResolved) return _cachedMac;
  _macResolved = true;
  if (Platform.isLinux) {
    _cachedMac = linuxPrimaryMac();
    return _cachedMac;
  }
  if (!Platform.isWindows) return null;
  try {
    String? preferredName;
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      if (pickBestLocalAddress(interface.addresses) != null) {
        preferredName = interface.name;
        break;
      }
    }
    _cachedMac = pickPrimaryMac(_enumerateAdapters(), preferredName);
  } catch (_) {
    // No network / permission denied — heartbeat proceeds without mac_address.
  }
  return _cachedMac;
}

List<AdapterInfo> _enumerateAdapters() {
  final adapters = <AdapterInfo>[];
  const flags = GAA_FLAG_SKIP_ANYCAST |
      GAA_FLAG_SKIP_MULTICAST |
      GAA_FLAG_SKIP_DNS_SERVER;
  final sizePtr = calloc<Uint32>();
  try {
    sizePtr.value = 0;
    var ret = GetAdaptersAddresses(_afUnspec, flags, nullptr, nullptr, sizePtr);
    if (ret != ERROR_BUFFER_OVERFLOW && ret != ERROR_SUCCESS) return adapters;
    final buffer = calloc<Uint8>(sizePtr.value);
    try {
      ret = GetAdaptersAddresses(
          _afUnspec, flags, nullptr, buffer.cast(), sizePtr);
      if (ret != ERROR_SUCCESS) return adapters;
      var adapter = buffer.cast<IP_ADAPTER_ADDRESSES_LH>();
      while (adapter.address != 0) {
        final ref = adapter.ref;
        final macLen = ref.PhysicalAddressLength.clamp(0, 8);
        final macBytes = [
          for (var i = 0; i < macLen; i++) ref.PhysicalAddress[i],
        ];
        adapters.add(AdapterInfo(
          name: ref.FriendlyName.toDartString(),
          ifType: ref.IfType,
          mac: macBytes
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(':'),
        ));
        adapter = ref.Next;
      }
    } finally {
      calloc.free(buffer);
    }
  } finally {
    calloc.free(sizePtr);
  }
  return adapters;
}
