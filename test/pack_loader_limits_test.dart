// Zip-bomb / weak-KDF guards in the pack loader (T2 findings).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/security/incident_log.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/fixtures/offline';

class _NoHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

void main() {
  final keys = OfflineKeys(
    signingPem: File('$_dir/test_signing_public.pem').readAsStringSync(),
    resultsPem: File('$_dir/test_results_public.pem').readAsStringSync(),
  );
  final golden = File('$_dir/golden.alochipack').readAsBytesSync();

  PackError? codeOf(void Function() f) {
    try {
      f();
    } on PackException catch (e) {
      return e.code;
    }
    return null;
  }

  group('size limits (checked on declared sizes, before reading)', () {
    test('golden pack fits the default limits', () {
      expect(PackLoader(keys: keys).inspect(golden).manifest.schoolCode, '999');
    });

    test('per-member cap', () {
      final l = PackLoader(
          keys: keys, limits: const PackLimits(maxContentBytes: 100));
      expect(codeOf(() => l.inspect(golden)), PackError.tooLarge);
    });

    test('media member cap', () {
      final l =
          PackLoader(keys: keys, limits: const PackLimits(maxMediaBytes: 10));
      expect(codeOf(() => l.inspect(golden)), PackError.tooLarge);
    });

    test('total cap and member-count cap', () {
      expect(
          codeOf(() => PackLoader(
                  keys: keys, limits: const PackLimits(maxTotalBytes: 1000))
              .inspect(golden)),
          PackError.tooLarge);
      expect(
          codeOf(() =>
              PackLoader(keys: keys, limits: const PackLimits(maxMembers: 2))
                  .inspect(golden)),
          PackError.tooLarge);
    });

    test('a deflated member is refused outright', () {
      final src = ZipDecoder().decodeBytes(golden);
      final out = Archive();
      for (final f in src.files) {
        out.addFile(ArchiveFile(f.name, f.size, f.readBytes()!)
          ..compression = CompressionType.deflate);
      }
      final bytes = Uint8List.fromList(ZipEncoder().encode(out));
      expect(codeOf(() => PackLoader(keys: keys).inspect(bytes)),
          PackError.badFormat);
    });
  });

  group('kdf.iter floor', () {
    Uint8List manifest(int iter) => Uint8List.fromList(utf8.encode(jsonEncode({
          'format_version': 1,
          'pack_uuid': 'u',
          'school_id': 's',
          'school_code': '1',
          'created_at': '2026-01-01T00:00:00Z',
          'expires_at': '2099-01-01T00:00:00Z',
          'kdf': {
            'alg': 'PBKDF2-HMAC-SHA256',
            'iter': iter,
            'salt': base64.encode(List.filled(16, 1))
          },
          'files': {},
        })));

    test('600000 is accepted, anything lower is rejected', () {
      expect(PackManifest.fromBytes(manifest(minKdfIter)).kdfIter, 600000);
      for (final low in [1, 1000, 599999]) {
        expect(codeOf(() => PackManifest.fromBytes(manifest(low))),
            PackError.badFormat);
      }
    });
  });

  group('bounded proctoring metadata', () {
    test('incidents beyond the cap are counted, not silently dropped', () {
      final log = IncidentLog.instance..drain();
      for (var i = 0; i < 250; i++) {
        log.add(i.isEven ? 'focus_lost' : 'focus_regained');
      }
      log.add('multi_monitor'); // a NEW kind arriving after the cap
      final out = log.drain();
      expect(out.length, 201); // 200 kept + one overflow summary
      final overflow = out.last;
      expect(overflow['type'], 'incident_overflow');
      expect(overflow['dropped'], {
        'focus_lost': 25,
        'focus_regained': 25,
        'multi_monitor': 1,
      });
      expect(log.drain(), isEmpty); // cleared afterwards
    });

    test('clock flags beyond the cap are counted too', () {
      var ticks = 0;
      var wall = 0;
      final c = MonitoredClock(
          ticks: () => ticks, wall: () => wall, highWaterStore: _NoHwm());
      for (var i = 0; i < 130; i++) {
        ticks += 5000;
        wall += 5000 + 3600000; // every window jumps an hour
        c.checkNow();
      }
      final out = c.drainFlags();
      expect(out.length, 101);
      expect(out.last, {'type': 'clock_flags_overflow', 'dropped': 30});
    });
  });
}
