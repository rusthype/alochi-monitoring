// LAN multi-monitor switch: the teacher picks which monitor of a student PC is
// streamed. Hub state, loopback client round-trip, and the segmented control.
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/local_server/hub_state.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/lan_client_api.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/features/offline/teacher_lan_monitoring_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/lan_test_pack.dart';

PingInput _ping() => PingInput.fromJson({
      'session_id': 'S1',
      'name': 'Valiyev Ali',
      'test_key': 't_all',
      'status': 'active',
      'student_code': lanS1,
    });

Map<String, Object?> _frame(HubState st, HubClient c, int monitors,
        {int index = 0}) =>
    st.acceptFrame(c,
        sessionId: 'S1',
        frameType: 'keyframe',
        jpeg: lanJpeg(),
        focus: true,
        monitorCount: monitors,
        monitorIndex: index);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ShelfHub hub;

  setUpAll(() {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestWidgetsFlutterBinding.instance.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('lan_monsw_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      final session = await OfflinePackSession.open(
          lanTestPack(), Directory(p.join(tmp.path, 'media')));
      hub = ShelfHub(session,
          bindAddress: InternetAddress.loopbackIPv4, firstPort: 0, lastPort: 0);
      await hub.start(announce: false);
    });
  });

  tearDown(() async {
    await TestWidgetsFlutterBinding.instance.runAsync(() async {
      await hub.stop();
      hub.dispose();
      OfflinePackSession.close();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });
  });

  HubClient joinPc(HubState st, {String machine = 'pc1'}) {
    final j = st.join(
        ip: '10.0.0.2', code: st.code, machineId: machine, deviceName: 'PC-1');
    st.ping(j.client!, _ping());
    return j.client!;
  }

  group('hub state', () {
    test('default 0; setMonitor clamps to the reported count; reply carries it',
        () {
      final st = hub.state!;
      final c = joinPc(st);
      expect(_frame(st, c, 2)['requested_monitor_index'], 0);

      st.setMonitor(c.id, 1);
      expect(st.viewOfId(c.id)!.requestedMonitor, 1);
      expect(st.ping(c, _ping())['requested_monitor_index'], 1);

      st.setMonitor(c.id, 7); // beyond the 2 reported monitors
      expect(st.viewOfId(c.id)!.requestedMonitor, 1);
      st.setMonitor(c.id, -3);
      expect(st.viewOfId(c.id)!.requestedMonitor, 0);
      st.setMonitor(999, 1); // unknown client: ignored
    });

    test('a monitor that disappears falls back in the reply', () {
      final st = hub.state!;
      final c = joinPc(st);
      _frame(st, c, 2);
      st.setMonitor(c.id, 1);
      c.lastFrameAt = 0;
      final r = _frame(st, c, 1); // the second monitor was unplugged
      expect(r['requested_monitor_index'], 0);
      expect(st.viewOfId(c.id)!.monitorCount, 1);
    });

    test('reset on rejoin and when the attempt ends', () {
      final st = hub.state!;
      final c = joinPc(st);
      _frame(st, c, 2);
      st.setMonitor(c.id, 1);
      final again = joinPc(st); // same machine re-joins
      expect(st.viewOfId(again.id)!.requestedMonitor, 0);

      _frame(st, again, 2);
      st.setMonitor(again.id, 1);
      again.endTest();
      expect(st.viewOfId(again.id)!.requestedMonitor, 0);
    });
  });

  test('loopback: a requested index reaches the client frame reply', () async {
    await TestWidgetsFlutterBinding.instance.runAsync(() async {
      final s = await LanClientSession.join(
        host: '127.0.0.1',
        port: hub.port!,
        code: hub.state!.code,
        client: http.Client(),
        machineId: 'student-pc-1',
        deviceName: 'PC',
        mediaDirFor: (id) async =>
            Directory(p.join(tmp.path, 'client_media', id)),
      );
      final lan = LanClientApi(s);
      final reply = await lan.sessionPing(
        sessionId: 'S1',
        name: 'Valiyev Ali',
        testKey: 't_all',
        studentCode: lanS1,
        tabSwitchCount: 0,
        currentQuestionIndex: 0,
        totalQuestions: 5,
        deviceName: 'PC',
        capabilities: const ['pause_lock'],
        answers: const {},
      );
      final token = reply['proctor_token'] as String;
      final id = hub.state!.views().single.id;

      Future<Map<String, dynamic>> send(int idx) => lan.proctorFrame(
          sessionId: 'S1',
          token: token,
          jpeg: lanJpeg(),
          focus: true,
          monitorCount: 2,
          monitorIndex: idx,
          frameType: 'keyframe');

      var fr = await send(0);
      expect(fr['requested_monitor_index'], 0);
      hub.state!.setMonitor(id, 1);
      // frames may not come faster than half the interval
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      fr = await send(1); // the PC also reports what it captures
      expect(fr['requested_monitor_index'], 1);
      expect(hub.state!.viewOfId(id), isNotNull);
      s.close();
    });
  });

  testWidgets('segmented control: hidden at 1 monitor, shown at 2, tap sets',
      (tester) async {
    final st = hub.state!;
    final c = joinPc(st);
    _frame(st, c, 1);

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TeacherLanMonitoringScreen(),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    await tester.tap(find.text('Valiyev Ali'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(l10n.lanMonitorN(2)), findsNothing);
    expect(find.textContaining(l10n.lanMonitorsBadge(2)), findsNothing);

    c.lastFrameAt = 0;
    _frame(st, c, 2);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(l10n.lanMonitorN(1)), findsOneWidget);
    expect(find.text(l10n.lanMonitorN(2)), findsOneWidget);
    expect(find.textContaining(l10n.lanMonitorsBadge(2)), findsOneWidget);

    await tester.ensureVisible(find.text(l10n.lanMonitorN(2)));
    await tester.tap(find.text(l10n.lanMonitorN(2)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.requestedMonitorIndex, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
