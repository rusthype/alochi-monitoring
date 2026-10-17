// lib/core/local_server/hub_guard.dart
//
// Pure, I/O-free building blocks of the LAN hub's abuse protection (decision 7
// of phase 3): size limits, bounded JSON decoding, constant-time comparison,
// token buckets, and the failed-join gate. Time is always a monotonic
// `TicksFn` (MonitoredClock.ticksMs), never the wall clock, so changing the
// system date cannot reset a lockout.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' show sha256;

import '../security/monitored_clock.dart' show TicksFn;

class HubLimits {
  HubLimits._();

  // Request body ceilings (bytes).
  static const int joinBody = 1024;
  static const int keepaliveBody = 1024;
  static const int pingBody = 64 * 1024;
  static const int frameBody = 512 * 1024;

  /// A real result is a few KB (engine: raw answers + section/topic scores;
  /// diagnostic: ~75 bytes per answered question). test/lan_hub_review_test.dart
  /// measures the 300-question worst case (~43 KB engine, ~16 KB diagnostic)
  /// and proves it fits here with headroom. It used to be 1 MB, then 128 KB:
  /// the biggest entry one request can add to the export is ~2x this (JSON
  /// escapes backslashes twice), which is what a pack-filling attacker pays
  /// with (N-2).
  static const int resultBody = 64 * 1024;

  /// Whole-body read deadlines. Small bodies get a short one so a slow-body
  /// connection cannot sit on a slot (S-002).
  static const Duration smallBodyTimeout = Duration(seconds: 3);
  static const Duration frameBodyTimeout = Duration(seconds: 8);
  static const Duration resultBodyTimeout = Duration(seconds: 6);

  static const int maxClients = 60;

  /// One address cannot take many slots (a hostile PC re-joining under made-up
  /// machine ids would otherwise fill the 60 and lock the class out).
  static const int maxClientsPerIp = 8;

  /// Result quota per SOURCE ADDRESS and hub run -- not per token and not per
  /// machine_id, both of which a hostile PC can renew by joining again (S-001).
  static const int maxResultsPerIp = 150;
  static const int maxResultBytesPerIp = 2560 * 1024; // export-format bytes

  /// The server imports at most 5000 entries / 10 MiB (10,485,760) of
  /// DECRYPTED JSON per file (offline_pack.py) and rejects the whole file
  /// above it. The chain budget is measured in exactly that unit (see
  /// export_format.dart) and stops 1 MiB short.
  static const int maxPackEntries = 4800;
  static const int maxPackPlainBytes = 9 * 1024 * 1024;

  /// Room kept for every roster student who has no result yet, so a hostile
  /// PC (or four) cannot fill the pack before the honest ones have finished:
  /// a further result is accepted only while `used + reserve + entry` fits.
  /// The reserve never exceeds half the budget (a huge roster must not make
  /// the hub refuse everything).
  static const int reservePerStudent = 24 * 1024;

  /// Per STUDENT (not per PC or address: a hostile PC can send as any
  /// roster student, from any number of addresses).
  static const int maxResultsPerStudent = 3;
  static const int maxResultBytesPerStudent = 192 * 1024; // export bytes

  /// Server keeps <=201 incidents / <=101 clock flags per entry, <=1 KiB per
  /// item, <=48 KiB per list. The hub adds up to two items of its own.
  static const int maxClientIncidents = 198;
  static const int maxClientClockFlags = 98;
  static const int maxMetaItemBytes = 1024;
  static const int maxMetaListBytes = 48 * 1024;

  static const int jsonMaxDepth = 24;
  static const int jsonMaxNodes = 200000;

  /// Requests being served at once. Authenticated /keepalive and /ping are
  /// exempt (they are tiny and carry liveness), as is /health.
  static const int maxInFlight = 128;

  /// Concurrent requests one token / one address may hold (S-002).
  static const int maxConcurrentPerToken = 4;
  static const int maxConcurrentPerIp = 16;
  static const int maxConcurrentJoinPerIp = 4;

  /// A frame costs this many tokens of the per-token bucket, and may not come
  /// faster than half the interval the hub announced (S-007).
  static const double frameCost = 10;

  /// Largest media file the hub serves and a client accepts (the backend's
  /// own ceiling is 15 MiB per image).
  static const int maxMediaFile = 16 * 1024 * 1024;

  /// A client silent this long counts as "no contact".
  static const int noContactMs = 15000;

  /// A client silent this long is forgotten (frees its slot).
  static const int evictMs = 20 * 60 * 1000;

  /// A refused seat claim is not re-reported to the teacher within this time,
  /// and a claim the teacher rejected stays refused this long (S-003).
  static const int claimCooldownMs = 10 * 1000;
  static const int rejectedClaimMs = 5 * 60 * 1000;

  /// One address may have this many unresolved seat conflicts at once (a
  /// hostile PC with many tokens could otherwise bury the honest ones, N-3).
  static const int maxOpenConflictsPerIp = 4;

  /// After the teacher frees a seat for a claimant, only THAT claimant may take
  /// it for this long (N-3: another PC must not win the race).
  static const int seatReserveMs = 60 * 1000;

  /// Frame limits against decompression bombs (S-006): a screen capture is
  /// 640x360 or 960x540.
  static const int maxFrameSide = 4096;
  static const int maxFramePixels = 8 * 1000 * 1000;
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
    if (node is double && !node.isFinite) {
      // `1e999` parses to Infinity; jsonEncode would later throw on it (S-010).
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
  int? blockedForMs(String ip, {bool ignoreGlobal = false}) {
    final now = ticks();
    var wait = 0;
    if (!ignoreGlobal && now < _globalBlockedUntil) {
      wait = _globalBlockedUntil - now;
    }
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

/// Runs async sections one at a time (first come, first served).
class Mutex {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() section) {
    final done = Completer<T>();
    final previous = _tail;
    _tail = done.future.then<void>((_) {}, onError: (_) {});
    previous.then((_) async {
      try {
        done.complete(await section());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }
}

/// Pixel size claimed by a JPEG's SOFn header, or null when none is found, a
/// second SOF is present (the fake-header trick: a decoder may honour a
/// different one than a walker, N-1), the stream is truncated, or it is not a
/// JPEG. Only the header is read -- nothing is decoded. The authoritative
/// number is [codecFrameSize]; this is the cheap second line.
({int width, int height})? jpegSize(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  ({int width, int height})? found;
  var i = 2; // always at the 0xFF that starts the next marker
  while (i + 1 < b.length) {
    if (b[i] != 0xFF) return null;
    var m = i + 1;
    while (m < b.length && b[m] == 0xFF) {
      m++; // fill bytes before the marker code
    }
    if (m >= b.length) return null;
    final marker = b[m];
    if (marker == 0x00 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD8)) {
      i = m + 1; // standalone marker
      continue;
    }
    if (marker == 0xD9) return null; // EOI before any scan: not a picture
    if (marker == 0xDA) return found; // SOS: the frame header is behind us
    if (m + 2 >= b.length) return null;
    final len = (b[m + 1] << 8) | b[m + 2];
    if (len < 2) return null;
    final isSof = marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      if (found != null) return null; // two frame headers: refuse
      if (m + 7 >= b.length) return null;
      final h = (b[m + 4] << 8) | b[m + 5];
      final w = (b[m + 6] << 8) | b[m + 7];
      found = (width: w, height: h);
    }
    i = m + 1 + len;
  }
  return null;
}

/// The pixel size the platform's own image codec reports for [bytes], WITHOUT
/// decoding them (an `ImageDescriptor` only parses the header), or null when
/// the codec cannot make sense of the data. This is what the teacher's
/// `Image.memory` will later decode with, so a header that fools a hand-written
/// walker (two SOFs, N-1) cannot fool this. Both native objects are released on
/// every path.
Future<({int width, int height})?> codecFrameSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return (width: descriptor.width, height: descriptor.height);
  } catch (_) {
    return null; // not decodable as an image: the caller answers 400
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Short, non-secret tag of a pack, shown next to the hub name on both sides so
/// a student can compare it with what the teacher reads out. The pack uuid
/// itself never goes into the (public) UDP announcement.
String packFingerprint(String packUuid) => sha256
    .convert(utf8.encode('alochi-pack:$packUuid'))
    .toString()
    .substring(0, 6)
    .toUpperCase();
