// A freshly opened USB pack must start in the flow that matches its tests:
// diagnostic-only -> diagnostic kiosk, monitoring-only/other -> /group_select.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/features/offline/offline_control_center_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('pack_start_route_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
  });

  tearDown(() async {
    OfflinePackSession.close();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<OfflinePackSession> open(List<String> types) =>
      OfflinePackSession.open(
          LoadedPack(
            manifest: PackManifest(
              formatVersion: 1,
              packUuid: '00000000-0000-4000-8000-0000000000a1',
              schoolId: '00000000-0000-4000-8000-0000000000b2',
              schoolCode: '999',
              createdAt: DateTime.utc(2026, 1, 1),
              expiresAt: DateTime.utc(2099, 1, 1),
              kdfIter: 1,
              kdfSalt: Uint8List(16),
              files: const {},
            ),
            tests: [
              for (var i = 0; i < types.length; i++)
                {'key': 't$i', 'type': types[i]},
            ],
            groups: const [],
            students: const [],
            chainKey: Uint8List(32),
          ),
          Directory(p.join(tmp.path, 'media')));

  test('diagnostic-only pack starts in the diagnostic kiosk', () async {
    final s = await open(['diagnostic', 'diagnostic']);
    expect(s.isDiagnosticOnly, isTrue);
    expect(s.isMonitoringOnly, isFalse);
    expect(diagnosticPackRoute(s), '/diagnostic_school_select');
  });

  test('monitoring-only pack keeps the group picker', () async {
    final s = await open(['test', 'package']);
    expect(s.isDiagnosticOnly, isFalse);
    expect(s.isMonitoringOnly, isTrue);
    expect(diagnosticPackRoute(s), isNull);
  });

  test('mixed or empty pack keeps the group picker', () async {
    expect(diagnosticPackRoute(await open(['diagnostic', 'test'])), isNull);
    expect(diagnosticPackRoute(await open([])), isNull);
  });
}
