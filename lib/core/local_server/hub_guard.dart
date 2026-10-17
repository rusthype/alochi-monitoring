// lib/core/local_server/hub_guard.dart
//
// Pure, I/O-free building blocks of the LAN hub's abuse protection (decision 7
// of phase 3): size limits, bounded JSON decoding, constant-time comparison,
// token buckets, and the failed-join gate. Time is always a monotonic
// `TicksFn` (MonitoredClock.ticksMs), never the wall clock, so changing the
// system date cannot reset a lockout.
import 'dart:convert';
import 'dart:typed_data';

import '../security/monitored_clock.dart' show TicksFn;

class HubLimits {
  HubLimits._();

  // Request body ceilings (bytes).
  static const int joinBody = 1024;
  static const int keepaliveBody = 1024;
  static const int pingBody = 64 * 1024;
  static const int frameBody = 512 * 1024;
  static const int resultBody = 1024 * 1024;

  static const int maxClients = 60;

  /// One address cannot take many slots (a hostile PC re-joining under made-up
  /// machine ids would otherwise fill the 60 and lock the class out).
  static const int maxClientsPerIp = 8;

  /// Accepted results per client PC per hub run (a PC takes a handful).
  static const int maxResultsPerClient = 100;

  /// The server imports at most 5000 entries / 10 MB decrypted per file
  /// (offline_pack.py); stop well before, or one export would be refused whole.
  static const int maxPackEntries = 4800;
  static const int maxPackPlainBytes = 8 * 1024 * 1024;

  /// Server keeps <=201 incidents / <=101 clock flags per entry, <=1 KiB per
  /// item, <=48 KiB per list. The hub adds up to two items of its own.
  static const int maxClientIncidents = 198;
  static const int maxClientClockFlags = 98;
  static const int maxMetaItemBytes = 1024;
  static const int maxMetaListBytes = 48 * 1024;

  static const int jsonMaxDepth = 24;
  static const int jsonMaxNodes = 200000;

  /// Requests being served at once; more get 503.
  static const int maxInFlight = 128;
  static const Duration bodyTimeout = Duration(seconds: 10);

  /// A client silent this long counts as "no contact".
  static const int noContactMs = 15000;

  /// A client silent this long is forgotten (frees its slot).
  static const int evictMs = 20 * 60 * 1000;
}

/// A refusal that maps to an HTTP status and a stable machine code. Carries no
/// internals by construction.
class HubHttpError implements Exception {
  final int status;
  final String code;
  final Map<String, Object?> extra;
  final Map<String, String> headers;
  const HubHttpError(this.status, this.code,
      {this.extra = const {}, this.headers = const {}});
  @override
  String toString() => 'HubHttpError($status, $code)';
}

/// Equality that does not leak where two strings first differ.
bool constantTimeEquals(String a, String b) {
  var diff = a.length ^ b.length;
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = i < a.length ? a.codeUnitAt(i) : 0;
    final y = i < b.length ? b.codeUnitAt(i) : 0;
    diff |= x ^ y;
  }
  return diff == 0;
}

/// strict UTF-8 + JSON decode with depth and node ceilings. Any failure
/// (malformed UTF-8, malformed JSON, too deep, too big) is the same 400.
Object? decodeJsonBounded(Uint8List bytes) {
  final Object? root;
  try {
    root = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    // FormatException, and anything exotic a hostile document might trigger.
    throw const HubHttpError(400, 'bad_json');
  }
  var nodes = 0;
  final stack = <(Object?, int)>[(root, 1)];
  while (stack.isNotEmpty) {
    final (node, depth) = stack.removeLast();
    if (++nodes > HubLimits.jsonMaxNodes || depth > HubLimits.jsonMaxDepth) {
      throw const HubHttpError(400, 'bad_json');
    }
    if (node is Map) {
      for (final v in node.values) {
        stack.add((v, depth + 1));
      }
    } else if (node is List) {
      for (final v in node) {
        stack.add((v, depth + 1));
      }
    }
  }
  return root;
}

/// Keeps at most [maxItems] Map items of at most [itemBytes] each and
/// [totalBytes] overall; whatever does not fit is only counted, in one trailing
/// `{type: <overflowType>, dropped: n}` item — so squeezed-out evidence stays
/// visible, as IncidentLog does on the client.
List<Map<String, dynamic>> sanitizeMetaList(
  Object? raw, {
  required int maxItems,
  required String overflowType,
  int itemBytes = HubLimits.maxMetaItemBytes,
  int totalBytes = HubLimits.maxMetaListBytes,
}) {
  if (raw is! List || raw.isEmpty) return const [];
  final out = <Map<String, dynamic>>[];
  var dropped = 0, used = 0;
  for (final item in raw) {
    if (item is! Map || item['type'] is! String) {
      dropped++;
      continue;
    }
    final map = Map<String, dynamic>.from(item);
    final size = utf8.encode(jsonEncode(map)).length;
    if (out.length >= maxItems ||
        size > itemBytes ||
        used + size > totalBytes) {
      dropped++;
      continue;
    }
    used += size;
    out.add(map);
  }
  if (dropped > 0) out.add({'type': overflowType, 'dropped': dropped});
  return out;
}

/// Classic token bucket on a monotonic clock.
class TokenBucket {
  final double capacity;
  final double refillPerSecond;
  double _tokens;
  int _lastMs;

  TokenBucket(this.capacity, this.refillPerSecond, int nowMs)
      : _tokens = capacity,
        _lastMs = nowMs;

  bool take(int nowMs, [double cost = 1]) {
    final dt = nowMs - _lastMs;
    if (dt > 0) {
      _tokens = (_tokens + dt / 1000.0 * refillPerSecond).clamp(0, capacity);
      _lastMs = nowMs;
    }
    if (_tokens < cost) return false;
    _tokens -= cost;
    return true;
  }
}

/// Throttle for wrong class codes: [maxFailures] wrong tries from one IP block
/// that IP for [blockMs]. A second, global ceiling ([globalMaxFailures] wrong
/// tries from ANY addresses within [blockMs]) closes the multi-address
/// brute-force that a per-IP limit alone leaves open; its price is that a
/// flood of wrong codes can delay legitimate joins for a minute.
class JoinFailureGate {
  final TicksFn ticks;
  final int maxFailures;
  final int blockMs;
  final int globalMaxFailures;

  final Map<String, _IpFailures> _ips = {};
  final List<int> _globalFailures = [];
  int _globalBlockedUntil = 0;

  static const int _forgetAfterMs = 10 * 60 * 1000;
  static const int _maxTracked = 2048;

  JoinFailureGate({
    required this.ticks,
    this.maxFailures = 5,
    this.blockMs = 60000,
    this.globalMaxFailures = 60,
  });

  /// Milliseconds until [ip] may try again, or null when it may try now.
  int? blockedForMs(String ip) {
    final now = ticks();
    var wait = 0;
    if (now < _globalBlockedUntil) wait = _globalBlockedUntil - now;
    final e = _ips[ip];
    if (e != null && now < e.blockedUntil) {
      final w = e.blockedUntil - now;
      if (w > wait) wait = w;
    }
    return wait > 0 ? wait : null;
  }

  void recordFailure(String ip) {
    final now = ticks();
    _prune(now);
    final e = _ips.putIfAbsent(ip, _IpFailures.new);
    if (now - e.lastAt > _forgetAfterMs) e.count = 0;
    e.lastAt = now;
    if (++e.count >= maxFailures) {
      e.blockedUntil = now + blockMs;
      e.count = 0;
    }
    _globalFailures
      ..removeWhere((t) => now - t > blockMs)
      ..add(now);
    if (_globalFailures.length >= globalMaxFailures) {
      _globalBlockedUntil = now + blockMs;
      _globalFailures.clear();
    }
  }

  void recordSuccess(String ip) => _ips.remove(ip);

  void _prune(int now) {
    if (_ips.length < _maxTracked) return;
    _ips.removeWhere(
        (_, e) => now >= e.blockedUntil && now - e.lastAt > _forgetAfterMs);
    if (_ips.length >= _maxTracked) _ips.clear(); // hostile churn: reset
  }
}

class _IpFailures {
  int count = 0;
  int lastAt = 0;
  int blockedUntil = 0;
}
