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

/// Pure ring-buffer append: newest last, capped at [cap].
List<Map<String, dynamic>> appendRing(
    List<Map<String, dynamic>> entries, Map<String, dynamic> entry,
    {int cap = 20}) {
  final out = [...entries, entry];
  return out.length > cap ? out.sublist(out.length - cap) : out;
}

class ErrorSnapshot {
  final Map<String, int> counts;
  final List<Map<String, dynamic>> entries;
  const ErrorSnapshot(this.counts, this.entries);
}

class ErrorLog {
  static const _entriesKey = 'device_error_log';
  static const _countsKey = 'device_error_counts';

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
    final snap = _read(prefs);
    final counts = {...snap.counts, kind: (snap.counts[kind] ?? 0) + 1};
    final entries = appendRing(snap.entries, {
      'kind': kind,
      'message': sanitizeErrorMessage(error.toString()),
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    await prefs.setString(_countsKey, jsonEncode(counts));
    await prefs.setString(_entriesKey, jsonEncode(entries));
    final cb = onRecorded;
    if (cb != null) cb();
  }

  static ErrorSnapshot _read(SharedPreferences prefs) {
    var counts = <String, int>{};
    var entries = <Map<String, dynamic>>[];
    try {
      final c = jsonDecode(prefs.getString(_countsKey) ?? '{}') as Map;
      counts = {for (final e in c.entries) e.key.toString(): e.value as int};
      final l = jsonDecode(prefs.getString(_entriesKey) ?? '[]') as List;
      entries = [for (final e in l) Map<String, dynamic>.from(e as Map)];
    } catch (_) {
      // Corrupt store: start over rather than block reporting.
    }
    return ErrorSnapshot(counts, entries);
  }

  static Future<ErrorSnapshot> snapshot() async {
    try {
      await _chain;
      return _read(await SharedPreferences.getInstance());
    } catch (_) {
      return const ErrorSnapshot({}, []);
    }
  }
}
