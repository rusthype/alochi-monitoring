// The two LAN screens (phase 3): the teacher's class monitor and the student's
// connect dialog. Strings are read back through AppLocalizations so uz and ru
// are both exercised and nothing is hard-coded.
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/local_server/hub_state.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/features/offline/lan_connect_dialog.dart';
import 'package:alochi_monitoring/features/offline/teacher_lan_monitoring_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/lan_test_pack.dart';

Widget _wrap(Widget child, Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('formatRemaining', () {
    expect(formatRemaining(0), '0:00');
    expect(formatRemaining(75), '1:15');
    expect(formatRemaining(3600 + 5 * 60 + 9), '1:05:09');
    expect(formatRemaining(-4), '0:00');
  });

  test('parseHubAddress', () {
    expect(
        parseHubAddress('192.168.1.5:8085'), (host: '192.168.1.5', port: 8085));
    expect(parseHubAddress(' 192.168.1.5 '), (host: '192.168.1.5', port: 8080));
    expect(parseHubAddress('http://pc-teacher:8081/'),
        (host: 'pc-teacher', port: 8081));
    for (final bad in [
      '',
      ':80',
      'a b:80',
      '1.2.3.4:0',
      '1.2.3.4:99999',
      '1.2.3.4:x',
      'x/y'
    ]) {
      expect(parseHubAddress(bad), isNull, reason: bad);
    }
  });

  for (final locale in const [Locale('uz'), Locale('ru')]) {
    group('teacher monitor (${locale.languageCode})', () {
      late Directory tmp;
      late ShelfHub hub;

      setUp(() async {
        await TestWidgetsFlutterBinding.instance.runAsync(() async {
          tmp = Directory.systemTemp.createTempSync('lan_screen_');
          await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
          final session = await OfflinePackSession.open(
              lanTestPack(), Directory(p.join(tmp.path, 'media')));
          hub = ShelfHub(session,
              bindAddress: InternetAddress.loopbackIPv4,
              firstPort: 0,
              lastPort: 0);
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

      testWidgets('shows code, a student row, and drives the controls',
          (tester) async {
        final st = hub.state!;
        final joined = st.join(
            ip: '10.0.0.2',
            code: st.code,
            machineId: 'pc1',
            deviceName: 'PC-1');
        st.ping(
            joined.client!,
            PingInput.fromJson({
              'session_id': 'S1',
              'name': 'Valiyev Ali',
              'test_key': 't_all',
              'status': 'active',
              'student_code': lanS1,
              'tab_switch_count': 3,
              'current_question_index': 1,
              'total_questions': 5,
            }));

        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester
            .pumpWidget(_wrap(const TeacherLanMonitoringScreen(), locale));
        await tester.pump(const Duration(milliseconds: 600));
        final l10n =
            AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

        expect(find.text(l10n.lanHubTitle), findsOneWidget);
        expect(find.text(l10n.lanHubRunning), findsOneWidget);
        final code = st.code;
        expect(find.text('${code.substring(0, 3)} ${code.substring(3)}'),
            findsOneWidget);
        expect(find.text(l10n.lanHubFirewall), findsOneWidget);
        expect(find.text(l10n.lanClients(1, 60)), findsOneWidget);
        expect(find.text('Valiyev Ali'), findsOneWidget);
        expect(find.text(l10n.lanStatusTesting), findsOneWidget);
        expect(find.textContaining(l10n.lanQuestionOf(2, 5)), findsOneWidget);
        expect(find.text(l10n.lanSelectClient), findsOneWidget);

        // Select the student: the detail panel with the controls appears and
        // the hub starts asking that PC for fresh keyframes.
        await tester.tap(find.text('Valiyev Ali'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(st.watchedId, joined.client!.id);
        expect(find.text(l10n.lanNoFrame), findsOneWidget);

        await tester.tap(find.text(l10n.lanAddMinutes(5)));
        await tester.pump();
        expect(joined.client!.extraTimeSeconds, 300);
        await tester.tap(find.text(l10n.lanAddMinutes(1)));
        await tester.pump();
        expect(joined.client!.extraTimeSeconds, 360);

        await tester.tap(find.text(l10n.lanLock));
        await tester.pump(const Duration(milliseconds: 600));
        expect(joined.client!.locked, isTrue);
        expect(find.text(l10n.lanUnlock), findsOneWidget);
        expect(find.text(l10n.lanStatusLocked), findsWidgets);

        await tester.tap(find.text(l10n.lanEndTest));
        await tester.pumpAndSettle();
        expect(
            find.text(l10n.lanEndTestConfirm('Valiyev Ali')), findsOneWidget);
        await tester.tap(find.text(l10n.lanEndTestYes));
        await tester.pumpAndSettle();
        expect(joined.client!.terminatedSessions, contains('S1'));

        // Rotating the code changes what is shown.
        final before = st.code;
        await tester.tap(find.byTooltip(l10n.lanRefreshCode));
        await tester.pump(const Duration(milliseconds: 600));
        expect(st.code == before, isFalse);

        // Leaving the screen stops the "watch" but keeps the hub running.
        await tester.pumpWidget(const SizedBox());
        expect(st.watchedId, isNull);
        expect(hub.running, isTrue);
        // let the hub's coalesced change notification (400 ms) fire
        await tester.pump(const Duration(seconds: 1));
      });

      testWidgets('empty class: says nobody has connected yet', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester
            .pumpWidget(_wrap(const TeacherLanMonitoringScreen(), locale));
        await tester.pump(const Duration(milliseconds: 600));
        final l10n =
            AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
        expect(find.text(l10n.lanNoClients), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    });

    group('connect dialog (${locale.languageCode})', () {
      testWidgets(
          'validates the code and the address before touching the network',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_wrap(const LanConnectDialog(), locale));
        await tester.pump();
        final l10n = AppLocalizations.of(tester.element(find.byType(Dialog)))!;

        // no code
        await tester.tap(find.text(l10n.lanConnect));
        await tester.pump();
        expect(find.text(l10n.lanErrCodeFormat), findsOneWidget);

        // code ok, address missing
        await tester.enterText(find.byType(TextField).last, '123456');
        await tester.tap(find.text(l10n.lanConnect));
        await tester.pump();
        expect(find.text(l10n.lanErrAddress), findsOneWidget);

        // the 6-digit field only takes digits
        await tester.enterText(find.byType(TextField).last, '12ab34');
        expect(
            tester
                .widget<TextField>(find.byType(TextField).last)
                .controller!
                .text,
            '1234');
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('a wrong class code is reported with the localized message',
          (tester) async {
        late Directory tmp;
        late ShelfHub hub;
        await tester.runAsync(() async {
          tmp = Directory.systemTemp.createTempSync('lan_dialog_');
          await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
          final session = await OfflinePackSession.open(
              lanTestPack(), Directory(p.join(tmp.path, 'media')));
          hub = ShelfHub(session,
              bindAddress: InternetAddress.loopbackIPv4,
              firstPort: 0,
              lastPort: 0);
          await hub.start(announce: false);
        });
        addTearDown(() async {
          await tester.runAsync(() async {
            await hub.stop();
            hub.dispose();
            OfflinePackSession.close();
            await OfflineQueue.resetForTest();
            tmp.deleteSync(recursive: true);
          });
        });

        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_wrap(const LanConnectDialog(), locale));
        await tester.pump();
        final l10n = AppLocalizations.of(tester.element(find.byType(Dialog)))!;

        final wrong = hub.state!.code == '000000' ? '111111' : '000000';
        await tester.enterText(
            find.byType(TextField).first, '127.0.0.1:${hub.port}');
        await tester.enterText(find.byType(TextField).last, wrong);
        await tester.tap(find.text(l10n.lanConnect));
        // Real socket I/O + the continuation chain in the fake-async zone.
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
        }
        expect(find.text(l10n.lanErrBadCode), findsOneWidget);
        expect(LanClientSession.isActive, isFalse);
        await tester.pumpWidget(const SizedBox());
      });
    });
  }
}
