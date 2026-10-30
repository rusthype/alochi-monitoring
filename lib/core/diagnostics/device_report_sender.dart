// lib/core/diagnostics/device_report_sender.dart
//
// Fire-and-forget POST of hardware + error counters to the guest endpoint
// `diagnostic/kiosk/device-report/`. Sent shortly after app start and after
// a recorded error (throttled: 24h / 60 min, persisted). Never throws, never blocks.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'device_info_collector.dart';
import 'error_log.dart';
import '../api/api_host.dart';

/// Same key the school picker writes; school_id is only sent once known.
const _lastSchoolKey = 'last_diag_school_id';

Map<String, dynamic> buildDeviceReportPayload({
  required DeviceInfo info,
  required String deviceId,
  required String? schoolId,
  required ErrorSnapshot errors,
}) {
  final c = errors.counts;
  return {
    'device_id': deviceId,
    'school_id': (schoolId == null || schoolId.isEmpty) ? null : schoolId,
    'os': info.os,
    'os_version': info.osVersion,
    'cpu': info.cpu,
    'ram_mb': info.ramMb,
    'screen_w': info.screenW,
    'screen_h': info.screenH,
    'app_version': info.appVersion,
    'error_counts': {
      kErrUpdateSignature: c[kErrUpdateSignature] ?? 0,
      kErrNetworkReset: c[kErrNetworkReset] ?? 0,
      kErrOther: c[kErrOther] ?? 0,
    },
    'last_errors': errors.entries.length > 20
        ? errors.entries.sublist(errors.entries.length - 20)
        : errors.entries,
  };
}

class DeviceReportSender {
  DeviceReportSender._();
  static final instance = DeviceReportSender._();

  static final String _host = normalizeApiHost(const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.alochi.org',
  ));
  // Backend throttle is 60/hour per IP (shared school NAT): start report at
  // most once per 24h, error-triggered at most once per 60 min.
  static const Duration startInterval = Duration(hours: 24);
  static const Duration errorInterval = Duration(minutes: 60);
  static const _lastSentKey = 'device_report_last_sent_ms';

  Timer? _pending;
  bool _started = false;
  int _incompleteRetries = 0;
  static const _maxIncompleteRetries = 3;

  @visibleForTesting
  Future<DeviceInfo> Function() collector = DeviceInfoCollector.collect;

  Future<Duration?> _sinceLastSent() async {
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(_lastSentKey);
      return ms == null
          ? null
          : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    } catch (_) {
      return null;
    }
  }

  /// Call once from main(); returns immediately.
  void start({Duration delay = const Duration(seconds: 20)}) {
    if (_started) return;
    _started = true;
    ErrorLog.onRecorded = () => unawaited(_onError());
    Timer(delay, () async {
      final since = await _sinceLastSent();
      if (since == null || since >= startInterval) await send();
    });
  }

  Future<void> _onError() async {
    final since = await _sinceLastSent();
    var wait = since == null ? Duration.zero : errorInterval - since;
    // Failed POSTs don't record last-sent: throttle retries by attempt time.
    final at = _lastAttempt;
    if (at != null) {
      final w = errorInterval - DateTime.now().difference(at);
      if (w > wait) wait = w;
    }
    if (wait <= Duration.zero) {
      await send();
    } else {
      _pending ??= Timer(wait, () {
        _pending = null;
        unawaited(send());
      });
    }
  }

  bool _inFlight = false;
  DateTime? _lastAttempt; // in-memory: throttles error retries after failures

  /// Records last-sent only after a 2xx of a complete report (cpu + ram), so
  /// an offline start or an empty hardware probe doesn't block the next
  /// attempt for a full interval. [_inFlight] stops double POSTs.
  Future<void> send() async {
    if (_inFlight) return;
    _inFlight = true;
    _lastAttempt = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      final info = await collector();
      final payload = buildDeviceReportPayload(
        info: info,
        deviceId: await DeviceInfoCollector.deviceId(),
        schoolId: prefs.getString(_lastSchoolKey),
        errors: await ErrorLog.snapshot(),
      );
      if ((payload['device_id'] as String).isEmpty) return; // backend: 400
      final res = await http
          .post(
            Uri.parse('$_host/api/v1/diagnostic/kiosk/device-report/'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (info.isComplete) {
          _incompleteRetries = 0;
          await prefs.setInt(
              _lastSentKey, DateTime.now().millisecondsSinceEpoch);
        } else {
          // Drop any stale stamp so the next launch re-reports at once, and
          // retry in-process after the error interval (capped).
          await prefs.remove(_lastSentKey);
          if (_incompleteRetries++ < _maxIncompleteRetries) {
            _pending ??= Timer(errorInterval, () {
              _pending = null;
              unawaited(send());
            });
          }
        }
      }
    } catch (_) {
      // Guest telemetry: offline/server errors must stay invisible.
    } finally {
      _inFlight = false;
    }
  }
}
