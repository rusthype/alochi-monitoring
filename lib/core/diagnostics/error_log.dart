// lib/core/diagnostics/error_log.dart
//
// Tiny persisted error ring buffer + counters feeding the kiosk device report.
// Only fed explicitly from known failure paths (updater, API clients) — there
// is deliberately no global error handler here. Never throws.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

const kErrUpdateSignature = 'update_signature_failed';
const kErrNetworkReset = 'network_econnreset';
const kErrOther = 'other';

/// Maps an error to one of the three report buckets.
String classifyError(Object error, [String? context]) {
  final msg = error.toString();
  if (msg.contains('Code signature validation failed')) {
    return kErrUpdateSignature;
  }
  final lower = msg.toLowerCase();
  if (error is SocketException ||
      lower.contains('econnreset') ||
      lower.contains('connection reset')) {
    return kErrNetworkReset;
  }
  return kErrOther;
}

/// Truncates to [max] chars and masks things that must not leave the device:
/// bearer tokens, long opaque tokens and digit runs of 4+ (PINs, phones, ids).
String sanitizeErrorMessage(String raw, {int max = 200}) {
  var s = raw
      .replaceAll(RegExp(r'Bearer\s+\S+', caseSensitive: false), 'Bearer ***')
      .replaceAll(RegExp(r'[A-Za-z0-9_\-]{24,}'), '***')
      .replaceAll(RegExp(r'\d{4,}'), '#')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length > max) s = s.substring(0, max);
  return s;
}

/// Pure ring-buffer append: newest last, capped at [cap]. On overflow the
/// oldest entry of the most frequent `kind` is dropped (ties: the overall
/// oldest), so one flooding kind cannot push rare kinds out of the ring.
/// Entries without a `kind` all share one group, i.e. plain drop-oldest.
List<Map<String, dynamic>> appendRing(
    List<Map<String, dynamic>> entries, Map<String, dynamic> entry,
    {int cap = 20}) {
  final out = [...entries, entry];
  while (out.length > cap) {
    final counts = <Object?, int>{}; // insertion order = first appearance
    for (final e in out) {
      counts[e['kind']] = (counts[e['kind']] ?? 0) + 1;
    }
    Object? victim;
    var best = 0;
    for (final c in counts.entries) {
      if (c.value > best) {
        best = c.value;
        victim = c.key;
      }
    }
    out.removeAt(out.indexWhere((e) => e['kind'] == victim));
  }
  return out;
}

class ErrorSnapshot {
  final Map<String, int> counts;
  final List<Map<String, dynamic>> entries;
  const ErrorSnapshot(this.counts, this.entries);
}

class ErrorLog {
  static const _entriesKey = 'device_error_log';
  static const _eventsKey = 'device_error_events';
  // Legacy lifetime counters: never reported, deleted on first write.
  static const _legacyCountsKey = 'device_error_counts';

  static const window = Duration(days: 7);
  static const maxEventsPerKind = 1000;
  static const dedupWindow = Duration(seconds: 60);

  /// Injectable clock for tests.
  static DateTime Function() clock = DateTime.now;

  /// Set by DeviceReportSender; called (unawaited) after every record.
  static void Function()? onRecorded;

  static Future<void> _chain = Future.value();

  /// Records [error]; fire-and-forget safe, swallows every failure.
  static Future<void> record(Object error, [String? context]) {
    _chain = _chain.then((_) => _record(error, context)).catchError((_) {});
    return _chain;
  }

  static Future<void> _record(Object error, String? context) async {
    final kind = classifyError(error, context);
    final prefs = await SharedPreferences.getInstance();
    final now = clock().toUtc();
    final message = sanitizeErrorMessage(error.toString());
    // Same kind+message as the newest entry within [dedupWindow]: bump that
    // entry's `count` instead of logging again (a slow network used to write
    // one 20s-timeout entry every few seconds). Counter and onRecorded are
    // skipped, so a repeat burst counts once.
    final prev = _readEntries(prefs, now);
    if (prev.isNotEmpty) {
      final last = prev.last;
      final lastAt = DateTime.tryParse('${last['at']}');
      if (last['kind'] == kind &&
          last['message'] == message &&
          lastAt != null &&
          now.difference(lastAt) <= dedupWindow) {
        last['count'] = ((last['count'] as num?)?.toInt() ?? 1) + 1;
        last['at'] = now.toIso8601String();
        await prefs.setString(_entriesKey, jsonEncode(prev));
        return;
      }
    }
    final events = _readEvents(prefs, now);
    final list = [
      ...(events[kind] ?? const <int>[]),
      now.millisecondsSinceEpoch
    ];
    events[kind] = list.length > maxEventsPerKind
        ? list.sublist(list.length - maxEventsPerKind)
        : list;
    final entries = appendRing(prev, {
      'kind': kind,
      'message': message,
      'at': now.toIso8601String(),
    });
    await prefs.setString(_eventsKey, jsonEncode(events));
    await prefs.setString(_entriesKey, jsonEncode(entries));
    await prefs.remove(_legacyCountsKey);
    final cb = onRecorded;
    if (cb != null) cb();
  }

  /// Per-kind event times (epoch ms) within [window] of [now].
  static Map<String, List<int>> _readEvents(
      SharedPreferences prefs, DateTime now) {
    final out = <String, List<int>>{};
    try {
      final cutoff = now.subtract(window).millisecondsSinceEpoch;
      final m = jsonDecode(prefs.getString(_eventsKey) ?? '{}') as Map;
      for (final e in m.entries) {
        final l = [
          for (final t in e.value as List)
            if ((t as int) >= cutoff) t
        ];
        if (l.isNotEmpty) out[e.key.toString()] = l;
      }
    } catch (_) {
      // Corrupt store: start over rather than block reporting.
    }
    return out;
  }

  static List<Map<String, dynamic>> _readEntries(
      SharedPreferences prefs, DateTime now) {
    try {
      final cutoff = now.subtract(window);
      final l = jsonDecode(prefs.getString(_entriesKey) ?? '[]') as List;
      return [
        for (final e in l)
          if (DateTime.tryParse(((e as Map)['at'] ?? '').toString())
                  ?.isAfter(cutoff) ??
              false)
            Map<String, dynamic>.from(e)
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<ErrorSnapshot> snapshot() async {
    try {
      await _chain;
      final prefs = await SharedPreferences.getInstance();
      final now = clock().toUtc();
      final ev = _readEvents(prefs, now);
      return ErrorSnapshot({for (final e in ev.entries) e.key: e.value.length},
          _readEntries(prefs, now));
    } catch (_) {
      return const ErrorSnapshot({}, []);
    }
  }
}
