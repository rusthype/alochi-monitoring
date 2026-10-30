import 'dart:async';
import 'dart:io';

import 'package:alochi_monitoring/core/diagnostics/device_info_collector.dart';
import 'package:alochi_monitoring/core/diagnostics/device_report_sender.dart';
import 'package:alochi_monitoring/core/diagnostics/error_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('normalizeOsVersion', () {
    expect(normalizeOsVersion('Version 26.5.2 (Build 25F84)'), '26.5.2');
    expect(normalizeOsVersion('"Windows 10 Pro" 10.0 (Build 19045)'),
        '10.0.19045');
    expect(normalizeOsVersion('  weird os  '), 'weird os');
    expect(normalizeOsVersion('x' * 50), 'x' * 40);
  });

  test('cleanCpuName / parseRegQueryCpu / parsePowershellHw / bytesToMb', () {
    expect(cleanCpuName('  Intel(R) Core(TM)  i5-8250U \u0000'),
        'Intel(R) Core(TM) i5-8250U');
    expect(
        parseRegQueryCpu('\r\nHKEY_LOCAL_MACHINE\\HARDWARE\\X\r\n'
            '    ProcessorNameString    REG_SZ    Intel(R) Celeron(R) N4020  \r\n'),
        'Intel(R) Celeron(R) N4020');
    expect(parseRegQueryCpu('ERROR: not found'), '');
    final hw = parsePowershellHw('Intel(R) Core(TM) i3\r\n8087\r\n');
    expect((hw.cpu, hw.ramMb), ('Intel(R) Core(TM) i3', 8087));
    expect(parsePowershellHw('').ramMb, 0);
    expect(bytesToMb(8 * 1024 * 1024 * 1024), 8192);
  });

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

  group('7-day window', () {
    tearDown(() => ErrorLog.clock = DateTime.now);

    test('counts and last_errors drop events older than 7 days', () async {
      SharedPreferences.setMockInitialValues({});
      final t0 = DateTime.utc(2026, 10, 1);
      ErrorLog.clock = () => t0;
      await ErrorLog.record(Exception('ECONNRESET'));
      ErrorLog.clock = () => t0.add(const Duration(days: 6));
      await ErrorLog.record(Exception('boom'));
      var s = await ErrorLog.snapshot();
      expect(s.counts, {kErrNetworkReset: 1, kErrOther: 1});
      ErrorLog.clock = () => t0.add(const Duration(days: 8));
      s = await ErrorLog.snapshot();
      expect(s.counts, {kErrOther: 1});
      expect(s.entries.length, 1);
      expect(s.entries.single['kind'], kErrOther);
    });

    test('per-kind cap of 1000', () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'device_error_events':
            '{"other":[${List.filled(1000, now).join(',')}]}',
      });
      await ErrorLog.record(Exception('boom'));
      expect((await ErrorLog.snapshot()).counts[kErrOther], 1000);
    });

    test('legacy lifetime counters are ignored and removed', () async {
      SharedPreferences.setMockInitialValues(
          {'device_error_counts': '{"network_econnreset":665}'});
      expect((await ErrorLog.snapshot()).counts, isEmpty);
      await ErrorLog.record(Exception('boom'));
      final s = await ErrorLog.snapshot();
      expect(s.counts, {kErrOther: 1});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('device_error_counts'), isFalse);
    });
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

  group('last-sent bookkeeping', () {
    const key = 'device_report_last_sent_ms';

    Future<int?> lastSent() async =>
        (await SharedPreferences.getInstance()).getInt(key);

    test('failed POST (offline / 5xx) leaves last-sent unchanged', () async {
      SharedPreferences.setMockInitialValues({key: 111});
      await http.runWithClient(
        () => DeviceReportSender.instance.send(),
        () => MockClient((_) async => throw const SocketException('offline')),
      );
      expect(await lastSent(), 111);
      await http.runWithClient(
        () => DeviceReportSender.instance.send(),
        () => MockClient((_) async => http.Response('', 503)),
      );
      expect(await lastSent(), 111);
    });

    test('2xx writes last-sent', () async {
      SharedPreferences.setMockInitialValues({});
      var posts = 0;
      await http.runWithClient(
        () => DeviceReportSender.instance.send(),
        () => MockClient((_) async {
          posts++;
          return http.Response('{}', 200);
        }),
      );
      expect(posts, 1);
      expect(await lastSent(), isNotNull);
    });

    DeviceInfo info({String cpu = 'M1', int ramMb = 8192}) => DeviceInfo(
        os: 'windows',
        osVersion: '10.0.19045',
        cpu: cpu,
        ramMb: ramMb,
        screenW: 1,
        screenH: 1,
        appVersion: '1');

    Future<void> sendWith(DeviceInfo i) async {
      DeviceReportSender.instance.collector = () async => i;
      try {
        await http.runWithClient(() => DeviceReportSender.instance.send(),
            () => MockClient((_) async => http.Response('{}', 200)));
      } finally {
        DeviceReportSender.instance.collector = DeviceInfoCollector.collect;
      }
    }

    test('2xx with empty cpu or zero ram does not write last-sent', () async {
      SharedPreferences.setMockInitialValues({});
      await sendWith(info(cpu: ''));
      expect(await lastSent(), isNull);
      await sendWith(info(ramMb: 0));
      expect(await lastSent(), isNull);
    });

    test('incomplete report clears a stale last-sent; complete writes it',
        () async {
      SharedPreferences.setMockInitialValues({key: 111});
      await sendWith(info(ramMb: 0));
      expect(await lastSent(), isNull);
      await sendWith(info());
      expect(await lastSent(), isNotNull);
    });

    const flagKey = 'device_report_hw_complete';
    Future<bool?> flag() async =>
        (await SharedPreferences.getInstance()).getBool(flagKey);

    Future<int> startCheck() async {
      var posts = 0;
      await http.runWithClient(
          () => DeviceReportSender.instance.sendOnStartIfDue(),
          () => MockClient((_) async {
                posts++;
                return http.Response('{}', 200);
              }));
      return posts;
    }

    test('start: fresh stamp but no complete flag (old build) sends at once',
        () async {
      SharedPreferences.setMockInitialValues(
          {key: DateTime.now().millisecondsSinceEpoch});
      expect(await startCheck(), 1);
    });

    test('start: fresh stamp + complete flag does not send', () async {
      SharedPreferences.setMockInitialValues(
          {key: DateTime.now().millisecondsSinceEpoch, flagKey: true});
      expect(await startCheck(), 0);
    });

    test('flag is set only by a complete 2xx report', () async {
      SharedPreferences.setMockInitialValues({});
      await sendWith(info(cpu: ''));
      expect(await flag(), isNull);
      await sendWith(info());
      expect(await flag(), isTrue);
    });

    test('second send() while one is in flight does not POST twice', () async {
      SharedPreferences.setMockInitialValues({});
      var posts = 0;
      final gate = Completer<void>();
      await http.runWithClient(() async {
        final a = DeviceReportSender.instance.send();
        final b = DeviceReportSender.instance.send();
        await b; // returns immediately: guarded
        expect(posts, lessThanOrEqualTo(1));
        gate.complete();
        await a;
      }, () => MockClient((_) async {
            posts++;
            await gate.future;
            return http.Response('{}', 200);
          }));
      expect(posts, 1);
    });
  });
}
