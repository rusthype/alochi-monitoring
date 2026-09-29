// lib/core/services/crash_reporter_service.dart
// Best-effort crash capture: writes one JSON file per crash to local disk so
// a fatal, uncaught error is never lost even on a network-less kiosk, then
// uploads (and deletes) whatever's pending once the app can reach the
// internet again. Every method here must never itself throw — capturing or
// uploading a crash report is a diagnostic nicety, not something allowed to
// cause a SECOND crash.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';

class CrashReporterService {
  CrashReporterService._();

  // ponytail: plain module-level ring buffer, not a class with DI — this app
  // has exactly one process-wide log stream (fed from main.dart's
  // ZoneSpecification print hook), so a static list is the lazy-correct
  // choice, same posture as screen_capture_win.dart's module-level state.
  static const int _maxLogLines = 50;
  static final List<String> _recentLogs = [];

  /// Fed from main.dart's `ZoneSpecification(print: ...)` — the ONLY call
  /// site that should ever invoke this, so every existing print/debugPrint
  /// call site app-wide is captured without being touched individually.
  static void logLine(String line) {
    _recentLogs.add('[${DateTime.now().toIso8601String()}] $line');
    if (_recentLogs.length > _maxLogLines) _recentLogs.removeAt(0);
  }

  static Future<Directory> _crashDir() async {
    final dir = await getApplicationSupportDirectory();
    final crashDir = Directory(join(dir.path, 'crashes'));
    if (!await crashDir.exists()) {
      await crashDir.create(recursive: true);
    }
    return crashDir;
  }

  /// Writes [error]/[stack] plus the recent print-log ring buffer to a new
  /// JSON file. Wrapped end-to-end in try/catch — a failure to WRITE a crash
  /// log must never itself throw/crash further.
  static Future<void> captureCrash(Object error, StackTrace stack) async {
    try {
      final dir = await _crashDir();
      final file = File(join(
          dir.path, 'crash_${DateTime.now().millisecondsSinceEpoch}.json'));
      final payload = {
        'timestamp': DateTime.now().toIso8601String(),
        'error': error.toString(),
        'stack': stack.toString(),
        'recent_logs': List<String>.from(_recentLogs),
        'os_version': Platform.operatingSystemVersion,
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (e) {
      debugPrint('CrashReporterService.captureCrash failed: $e');
    }
  }

  /// Uploads every locally-queued crash report, deleting each one only on a
  /// confirmed 2xx response. Any failure (network, non-2xx) leaves the file
  /// in place for the next attempt.
  static Future<void> uploadPending() async {
    try {
      final dir = await _crashDir();
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .cast<File>()
          .toList();
      for (final file in files) {
        try {
          final body = await file.readAsString();
          final ok = await api.uploadCrashReport(body);
          if (ok) await file.delete();
        } catch (e) {
          debugPrint('CrashReporterService.uploadPending file error: $e');
        }
      }
    } catch (e) {
      debugPrint('CrashReporterService.uploadPending error: $e');
    }
  }
}
