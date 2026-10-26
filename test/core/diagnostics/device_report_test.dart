import 'dart:io';

import 'package:alochi_monitoring/core/diagnostics/device_info_collector.dart';
import 'package:alochi_monitoring/core/diagnostics/device_report_sender.dart';
import 'package:alochi_monitoring/core/diagnostics/error_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('classify: macOS updater signature error', () {
    expect(classifyError(Exception('Code signature validation failed: bad')),
        kErrUpdateSignature);
  });

  test('classify: network resets and everything else', () {
    expect(
        classifyError(
            const SocketException('Connection reset by peer, errno = 54')),
        kErrNetworkReset);
    expect(classifyError(Exception('read ECONNRESET')), kErrNetworkReset);
    expect(classifyError(Exception('boom')), kErrOther);
  });

  test('sanitize truncates to 200 and masks tokens/PINs', () {
    expect(sanitizeErrorMessage('ab ' * 200).length, 200);
    final s =
        sanitizeErrorMessage('Bearer abc.def pin 123456 token ${'a1' * 20}');
    expect(s, isNot(contains('abc.def')));
    expect(s, isNot(contains('123456')));
    expect(s, isNot(contains('a1a1a1a1a1')));
  });

  test('appendRing caps at 20 keeping newest', () {
    var l = <Map<String, dynamic>>[];
    for (var i = 0; i < 25; i++) {
      l = appendRing(l, {'i': i});
    }
    expect(l.length, 20);
    expect(l.first['i'], 5);
    expect(l.last['i'], 24);
  });

  test('ErrorLog persists counts + entries', () async {
    SharedPreferences.setMockInitialValues({});
    for (var i = 0; i < 22; i++) {
      await ErrorLog.record(Exception('ECONNRESET $i'), 'api');
    }
    await ErrorLog.record(Exception('Code signature validation failed'));
    final snap = await ErrorLog.snapshot();
    expect(snap.counts[kErrNetworkReset], 22);
    expect(snap.counts[kErrUpdateSignature], 1);
    expect(snap.entries.length, 20);
    expect(snap.entries.last['kind'], kErrUpdateSignature);
  });

  test('payload shape, school_id null when unknown', () {
    const info = DeviceInfo(
        os: 'macos',
        osVersion: '14',
        cpu: 'M1',
        ramMb: 8192,
        screenW: 2880,
        screenH: 1800,
        appVersion: '1.0.167+167');
    final p = buildDeviceReportPayload(
      info: info,
      deviceId: 'dev-1',
      schoolId: null,
      errors: const ErrorSnapshot({
        kErrOther: 2
      }, [
        {'kind': 'other', 'message': 'm', 'at': '2026-10-26T00:00:00Z'}
      ]),
    );
    expect(p.keys.toSet(), {
      'device_id',
      'school_id',
      'os',
      'os_version',
      'cpu',
      'ram_mb',
      'screen_w',
      'screen_h',
      'app_version',
      'error_counts',
      'last_errors',
    });
    expect(p['school_id'], isNull);
    expect(p['error_counts'], {
      'update_signature_failed': 0,
      'network_econnreset': 0,
      'other': 2,
    });
    expect((p['last_errors'] as List).length, 1);
  });

  test('send() never throws when offline/unconfigured', () async {
    SharedPreferences.setMockInitialValues({});
    await DeviceReportSender.instance.send();
  });
}
