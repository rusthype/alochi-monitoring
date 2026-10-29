// F24: pack expiry uses MonitoredClock's trusted time, not the raw system
// clock. F36(c): a naive manifest timestamp is UTC (the backend writes UTC).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/fixtures/offline';

class _Hwm implements HighWaterStore {
  DateTime? v;
  _Hwm(this.v);
  @override
  Future<DateTime?> read() async => v;
  @override
  Future<void> write(DateTime utc) async => v = utc;
}

class _BrokenHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => throw StateError('no storage');
  @override
  Future<void> write(DateTime utc) async {}
}

void main() {
  final keys = OfflineKeys(
    signingPem: File('$_dir/test_signing_public.pem').readAsStringSync(),
    resultsPem: File('$_dir/test_results_public.pem').readAsStringSync(),
  );
  final goldenPath = '$_dir/golden.alochipack'; // expires 2099-01-01Z
  final saved = MonitoredClock.instance;
  tearDown(() => MonitoredClock.instance = saved);

  MonitoredClock clockAt(DateTime wall, HighWaterStore hwm) => MonitoredClock(
      ticks: () => 0, wall: () => wall.millisecondsSinceEpoch,
      highWaterStore: hwm);

  group('F24 trusted expiry time', () {
    test('wall set back past expiry still rejects an expired pack', () async {
      // The PC clock says 2026 but it was seen at 2100 before.
      MonitoredClock.instance =
          clockAt(DateTime.utc(2026, 1, 1), _Hwm(DateTime.utc(2100, 1, 1)));
      await expectLater(
        inspectPackFile(goldenPath, keys),
        throwsA(isA<PackException>()
            .having((e) => e.code, 'code', PackError.expired)),
      );
    });

    test('normal case: a valid pack opens', () async {
      MonitoredClock.instance =
          clockAt(DateTime.utc(2026, 6, 1), _Hwm(DateTime.utc(2026, 5, 1)));
      final a = await inspectPackFile(goldenPath, keys);
      expect(a.manifest.schoolCode, '999');
    });

    test('unreadable high-water store falls back to the monitored clock',
        () async {
      MonitoredClock.instance =
          clockAt(DateTime.utc(2026, 6, 1), _BrokenHwm());
      final a = await inspectPackFile(goldenPath, keys);
      expect(a.manifest.schoolCode, '999');
    });

    test('explicit now still wins (tests / callers)', () async {
      await expectLater(
        inspectPackFile(goldenPath, keys, now: DateTime.utc(2100, 1, 1)),
        throwsA(isA<PackException>()
            .having((e) => e.code, 'code', PackError.expired)),
      );
    });

    test('trustedNowUtc is the later of the monotonic clock and the mark',
        () async {
      final c = clockAt(DateTime.utc(2026, 1, 1), _Hwm(DateTime.utc(2030, 1, 1)));
      expect(await c.trustedNowUtc(), DateTime.utc(2030, 1, 1));
      final d = clockAt(DateTime.utc(2031, 1, 1), _Hwm(DateTime.utc(2030, 1, 1)));
      expect(await d.trustedNowUtc(), DateTime.utc(2031, 1, 1));
    });
  });

  group('F36c manifest timestamps', () {
    Uint8List manifest(String created, String expires) =>
        Uint8List.fromList(utf8.encode(jsonEncode({
          'format_version': 1,
          'pack_uuid': 'u',
          'school_id': 's',
          'school_code': '1',
          'created_at': created,
          'expires_at': expires,
          'kdf': {
            'alg': 'PBKDF2-HMAC-SHA256',
            'iter': minKdfIter,
            'salt': base64.encode(List.filled(16, 1))
          },
          'files': {},
        })));

    test('naive timestamps are UTC, Z and offsets are honoured', () {
      final m = PackManifest.fromBytes(
          manifest('2026-10-17T09:00:00', '2026-11-17T09:00:00Z'));
      expect(m.createdAt, DateTime.utc(2026, 10, 17, 9));
      expect(m.createdAt.isUtc, isTrue);
      expect(m.expiresAt, DateTime.utc(2026, 11, 17, 9));
      final o = PackManifest.fromBytes(
          manifest('2026-10-17T09:00:00+05:00', '2026-11-17 09:00:00.250'));
      expect(o.createdAt, DateTime.utc(2026, 10, 17, 4));
      expect(o.expiresAt, DateTime.utc(2026, 11, 17, 9, 0, 0, 250));
    });
  });
}
