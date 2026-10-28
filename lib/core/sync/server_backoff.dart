// lib/core/sync/server_backoff.dart
//
// The server's own "come back later": a 429 / 503 answer to a result submit may
// carry `Retry-After` (seconds or an HTTP date). The submit helpers note it
// here and SyncService schedules its next automatic flush no earlier, so 30
// PCs that were all told "wait 60 s" do not return in lockstep.
import 'dart:io' show HttpDate;

class ServerBackoff {
  /// A server asking for more than this is treated as asking for this much:
  /// a result must never wait out an hours-long header.
  static const Duration maxWait = Duration(minutes: 5);

  static DateTime? _until;

  /// Test seam.
  static DateTime Function() clock = DateTime.now;

  /// `Retry-After` value -> wait, capped at [maxWait]. Null when absent,
  /// unparsable or not positive. [now] is the reference for the HTTP-date
  /// form (the response's own `Date` is the best one; default: device time).
  static Duration? parse(String? raw, {DateTime? now}) {
    final v = raw?.trim() ?? '';
    if (v.isEmpty) return null;
    Duration? d;
    final secs = int.tryParse(v);
    if (secs != null) {
      d = Duration(seconds: secs);
    } else {
      try {
        d = HttpDate.parse(v).difference((now ?? clock()).toUtc());
      } catch (_) {
        return null;
      }
    }
    if (d <= Duration.zero) return null;
    return d > maxWait ? maxWait : d;
  }

  /// Remember that no automatic flush should start for [wait]; the longest
  /// outstanding wait wins.
  static void note(Duration wait) {
    final capped = wait > maxWait ? maxWait : wait;
    final until = clock().add(capped);
    final cur = _until;
    if (cur == null || until.isAfter(cur)) _until = until;
  }

  static Duration remaining() {
    final u = _until;
    if (u == null) return Duration.zero;
    final left = u.difference(clock());
    return left > Duration.zero ? left : Duration.zero;
  }

  static bool get active => remaining() > Duration.zero;

  static void clear() => _until = null;
}
