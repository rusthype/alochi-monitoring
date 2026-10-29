// Wave 8a: LAN / offline-pack ServerClock. The hub is its own clock: its
// offset is learned from the hub's own responses, kept apart from the cloud
// offset, and MonitoredClock uses the one matching the active session.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_crypto.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/core/services/server_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/lan_test_pack.dart';

class _NoHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

final String _mediaSha = OfflineCrypto.sha256Hex(lanMediaBytes);
const _s = 1000;
const _min = 60 * _s;

String _date(int epochMs) =>
    HttpDate.format(DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerClock.resetForTest();
  });
  tearDown(ServerClock.resetForTest);

  group('two independent offsets', () {
    test('a hub observation never moves the cloud offset, and vice versa', () {
      var device = DateTime.utc(2026, 10, 29, 10);
      ServerClock.deviceNow = () => device;
      ServerClock.observe(_date(device.millisecondsSinceEpoch + 5 * _min));
      final cloud = ServerClock.offset;
      final cloudSeq = ServerClock.observationCount;
      expect(cloud, const Duration(minutes: 5));

      ServerClock.hub.observe(_date(device.millisecondsSinceEpoch - 3 * _min));
      expect(ServerClock.hub.offset, const Duration(minutes: -3));
      expect(ServerClock.offset, cloud);
      expect(ServerClock.observationCount, cloudSeq);

      ServerClock.observe(_date(device.millisecondsSinceEpoch + 6 * _min));
      expect(ServerClock.hub.offset, const Duration(minutes: -3));
      expect(ServerClock.hub.observationCount, 1);
    });

    test('the active sample follows the session mode; no hub sample = null',
        () {
      final device = DateTime.utc(2026, 10, 29, 10);
      ServerClock.deviceNow = () => device;
      ServerClock.observe(_date(device.millisecondsSinceEpoch + 5 * _min));
      expect(ServerClock.source, 'cloud');
      expect(ServerClock.activeSample()?.offsetMs, 5 * _min);

      ServerClock.useHub(true);
      expect(ServerClock.source, 'hub');
      expect(ServerClock.activeSample(), isNull,
          reason: 'cloud offset must not stand in for the hub');
      ServerClock.hub.observe(_date(device.millisecondsSinceEpoch + 2 * _min));
      expect(ServerClock.activeSample()?.offsetMs, 2 * _min);

      ServerClock.useHub(false);
      expect(ServerClock.activeSample()?.offsetMs, 5 * _min);
    });

    test('joining a hub starts a fresh hub offset (an old hub is no witness)',
        () {
      final device = DateTime.utc(2026, 10, 29, 10);
      ServerClock.deviceNow = () => device;
      ServerClock.useHub(true);
      ServerClock.hub.observe(_date(device.millisecondsSinceEpoch + _min));
      ServerClock.useHub(false);
      ServerClock.useHub(true);
      expect(ServerClock.activeSample(), isNull);
    });

    test('the hub offset is never persisted', () async {
      final device = DateTime.utc(2026, 10, 29, 10);
      ServerClock.deviceNow = () => device;
      ServerClock.useHub(true);
      ServerClock.hub.observe(_date(device.millisecondsSinceEpoch + 9 * _min));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('server_clock_offset_ms'), isNull);
    });
  });

  group('MonitoredClock source handling', () {
    // A world with one cloud and one hub clock, both ahead of the device by
    // different amounts.
    late int ticks, wall;
    String source = 'cloud';
    ({int offsetMs, int seq})? cloud, hub;

    MonitoredClock make() => MonitoredClock(
          ticks: () => ticks,
          wall: () => wall,
          highWaterStore: _NoHwm(),
          offsetUncertaintyMs: () => 0,
          serverSample: () => source == 'hub' ? hub : cloud,
          serverSource: () => source,
        );

    setUp(() {
      ticks = 1000000;
      wall = 1790000000000;
      source = 'cloud';
      cloud = (offsetMs: 7 * _min, seq: 1);
      hub = (offsetMs: -2 * _min, seq: 1);
    });

    test('snapshot names the source of the server witness it stores', () {
      final c = make();
      var snap = c.snapshotRecord();
      expect(snap['server_epoch_at_save_ms'], wall + 7 * _min);
      expect(snap['server_source'], 'cloud');
      source = 'hub';
      snap = c.snapshotRecord();
      expect(snap['server_epoch_at_save_ms'], wall - 2 * _min);
      expect(snap['server_source'], 'hub');
      // Field names of the existing snapshot are unchanged.
      expect(
          c.snapshot().keys,
          containsAll(
              ['epoch_at_save', 'ticks_at_save', 'server_epoch_at_save_ms']));
      expect(c.snapshot().containsKey('server_source'), isFalse);
    });

    test('no witness, no server_source', () {
      cloud = null;
      expect(make().snapshotRecord().containsKey('server_source'), isFalse);
    });

    test('a witness saved under another source is ignored on rebase', () {
      final c = make();
      final epoch = c.nowMs;
      final save = ticks;
      final serverAtSave = wall + 7 * _min; // saved under the CLOUD clock
      ticks += 4 * _min;
      wall += 4 * _min;
      // Cloud witness, current source cloud: server elapsed counts.
      final viaCloud = c.rebaseSavedDeadline(
          deadlineEpochMs: epoch + 10 * _min,
          epochAtSaveMs: epoch,
          ticksAtSaveMs: save,
          serverEpochAtSaveMs: serverAtSave,
          serverSourceAtSave: 'cloud');
      // Now on the hub: the same stored witness must NOT be compared with the
      // hub offset (would read as a 9 min jump).
      source = 'hub';
      final viaHub = c.rebaseSavedDeadline(
          deadlineEpochMs: epoch + 10 * _min,
          epochAtSaveMs: epoch,
          ticksAtSaveMs: save,
          serverEpochAtSaveMs: serverAtSave,
          serverSourceAtSave: 'cloud');
      expect(viaCloud, c.nowMs + 6 * _min);
      // Ignored witness = the plain tick rule: exactly 4 min elapsed.
      expect(viaHub, c.nowMs + 6 * _min);
    });

    test('a record without server_source is a cloud witness (old records)', () {
      final c = make();
      final epoch = c.nowMs;
      final save = ticks;
      ticks += _min;
      wall += _min;
      source = 'hub';
      final r = c.rebaseSavedDeadline(
          deadlineEpochMs: epoch + 10 * _min,
          epochAtSaveMs: epoch,
          ticksAtSaveMs: save,
          serverEpochAtSaveMs: wall + 7 * _min);
      expect(r, c.nowMs + 9 * _min);
    });

    test('switching source mid-run neither credits nor flags a false suspend',
        () {
      final c = make();
      ticks += 5 * _s;
      wall += 5 * _s;
      expect(c.absorbSuspend(), 0);
      // A hub joins: its offset differs from the cloud one by 9 min.
      source = 'hub';
      ticks += 5 * _s;
      wall += 5 * _s;
      hub = (offsetMs: -2 * _min, seq: 2);
      expect(c.absorbSuspend(), 0);
      ticks += 5 * _s;
      wall += 5 * _s;
      hub = (offsetMs: -2 * _min, seq: 3);
      expect(c.absorbSuspend(), 0);
      expect(
          c.pendingFlags
              .any((f) => f['type'] == 'clock_change_server_confirmed'),
          isFalse);
    });

    test(
        'a jump pending while the source switches falls back to the offline '
        'rule', () {
      var probes = 0;
      final c = MonitoredClock(
        ticks: () => ticks,
        wall: () => wall,
        highWaterStore: _NoHwm(),
        offsetUncertaintyMs: () => 0,
        serverSample: () => source == 'hub' ? hub : cloud,
        serverSource: () => source,
        probeServer: () => probes++,
      );
      wall += 10 * _min; // suspend: wall ahead of ticks
      expect(c.absorbSuspend(), 0);
      expect(probes, 1);
      source = 'hub';
      expect(c.absorbSuspend(), 10 * _min,
          reason: 'the cloud verdict can no longer arrive');
    });
  });

  group('the LAN hub', () {
    late Directory tmp;
    late ShelfHub hub;
    late MonitoredClock hubClock;
    const hubWall = 1790000000000;
    final sessions = <LanClientSession>[];

    setUpAll(() {
      HttpOverrides.global = null;
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('hub_clock_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      hubClock = MonitoredClock(
          ticks: () => 1000000, wall: () => hubWall, highWaterStore: _NoHwm());
      final media = makeMediaDir(tmp, _mediaSha);
      final session = await OfflinePackSession.open(
          lanTestPack(mediaRef: 'media/$_mediaSha.jpg'), media);
      hub = ShelfHub(session,
          bindAddress: InternetAddress.loopbackIPv4,
          firstPort: 0,
          lastPort: 0,
          clock: hubClock);
      await hub.start(announce: false);
    });

    tearDown(() async {
      for (final s in sessions) {
        s.close();
      }
      sessions.clear();
      await hub.stop();
      hub.dispose();
      OfflinePackSession.close();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    test('every hub answer carries a Date from the hub\'s trusted clock',
        () async {
      final c = http.Client();
      addTearDown(c.close);
      for (final path in ['/health']) {
        final r = await c.get(Uri.parse('http://127.0.0.1:${hub.port}$path'));
        final d = HttpDate.parse(r.headers['date']!).millisecondsSinceEpoch;
        expect((d - hubWall).abs(), lessThan(2 * _s), reason: path);
      }
      // An error answer too.
      final bad = await c.post(Uri.parse('http://127.0.0.1:${hub.port}/join'),
          headers: {'content-type': 'application/json'}, body: '{}');
      expect(bad.statusCode, isNot(200));
      expect(bad.headers['date'], isNotNull);
    });

    test('a LAN client feeds the hub offset, never the cloud one', () async {
      final s = await LanClientSession.join(
        host: '127.0.0.1',
        port: hub.port!,
        code: hub.state!.code,
        client: http.Client(),
        machineId: 'pc-1',
        deviceName: 'PC',
        mediaDirFor: (id) async => Directory(p.join(tmp.path, 'cm', id)),
      );
      sessions.add(s);
      // A student PC has no USB pack open (the hub keeps its own reference).
      final packSession = OfflinePackSession.current;
      OfflinePackSession.current = null;
      expect(ServerClock.observationCount, 0);

      await s.activate();
      expect(ServerClock.source, 'hub');
      expect(ServerClock.hub.observationCount, 0);
      await api.ping();
      expect(ServerClock.hub.observationCount, greaterThan(0));
      expect(ServerClock.observationCount, 0, reason: 'cloud untouched');
      final expected = hubWall - DateTime.now().millisecondsSinceEpoch;
      expect((ServerClock.hub.offset.inMilliseconds - expected).abs(),
          lessThan(3 * _s));

      s.close();
      expect(ServerClock.source, 'cloud');
      OfflinePackSession.current = packSession;
    });
  });
}
