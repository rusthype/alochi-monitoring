// Built-in ("assets") runners in offline USB / LAN mode (decision 3): their
// results go to the pack chain (USB) or the hub (LAN) in the roster student's
// name, never to the online `local_queue`; the hub admits exactly the closed
// `asset:` key list; no score is shown.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/local_server/hub_guard.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/asset_test_keys.dart';
import 'package:alochi_monitoring/core/offline/export_format.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_asset_results.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/features/combined/combined_screen.dart';
import 'package:alochi_monitoring/features/interhouse/interhouse_data.dart';
import 'package:alochi_monitoring/features/offline/offline_asset_ui.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/asset_screens.dart';
import 'helpers/lan_test_pack.dart';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

const _student = OfflineAssetStudent(
  studentId: lanS1,
  groupId: lanG1,
  groupName: '5-A | Ingliz',
  firstName: 'Ali',
  lastName: 'Valiyev',
);

Map<String, dynamic> _runnerPayload({String nativeKey = 'unit1_eng'}) => {
      'name': 'Valiyev Ali',
      'grade': 1,
      'variant': '3',
      'source': 'flutter',
      'vocab': {'cor': 0, 'tot': 0},
      'english': {'cor': 30, 'tot': 49},
      'math': {'cor': 0, 'tot': 0},
      'pct': 61,
      'school_code': '',
      'answers': [
        {'section': 'Vocabulary', 'q': 'q', 'chosen': 'a', 'correct': 'b'}
      ],
      'detail': {'test_key': nativeKey},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Real loopback sockets for the hub tests (flutter_test mocks dart:io HTTP).
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('asset keys', () {
    test('namespaced: never a server-known key or a scoring prefix', () {
      expect(kAssetTestKeys, hasLength(4));
      for (final k in kAssetTestKeys) {
        expect(k, startsWith('asset:'));
        for (final scoring in ['diag:', 'package:', 'pack:']) {
          expect(k.startsWith(scoring), isFalse, reason: k);
        }
      }
      // The runners' native keys are (or may be) MonitoringTest rows: they
      // would be refused server-side as `test_not_in_pack`.
      for (final native in [
        'unit1_eng',
        'monitoring_unit1',
        'interhouse_g2',
        'bob1_4'
      ]) {
        expect(kAssetTestKeys.contains(native), isFalse);
      }
    });
  });

  group('offlineAssetBody', () {
    test('adds the roster identity and the namespaced key (top level + detail)',
        () {
      final src = _runnerPayload();
      final body = offlineAssetBody(
          payload: src,
          testKey: kAssetKeyUnit1,
          student: _student,
          schoolCode: '999');
      expect(body['student_id'], lanS1);
      expect(body['group_id'], lanG1);
      expect(body['group_name'], '5-A | Ingliz');
      expect(body['school_code'], '999');
      expect(body['test_key'], 'asset:unit1_eng');
      expect((body['detail'] as Map)['test_key'], 'asset:unit1_eng');
      // The runner's own fields travel untouched; its map is not mutated.
      expect(body['english'], {'cor': 30, 'tot': 49});
      expect(src.containsKey('student_id'), isFalse);
      expect((src['detail'] as Map)['test_key'], 'unit1_eng');
    });

    test('a payload without detail still gets one carrying the key', () {
      final body = offlineAssetBody(
          payload: {'name': 'x', 'pct': 50},
          testKey: kAssetKeyBob14,
          student: _student,
          schoolCode: '999');
      expect(body['detail'], {'test_key': 'asset:bob1_4'});
    });

    test('no student / unknown key -> refused, never an anonymous row', () {
      expect(
          () => offlineAssetBody(
              payload: {},
              testKey: kAssetKeyUnit1,
              student: null,
              schoolCode: '999'),
          throwsA(isA<OfflineAssetException>()
              .having((e) => e.code, 'code', kOfflineStudentRequired)));
      expect(
          () => offlineAssetBody(
              payload: {},
              testKey: kAssetKeyUnit1,
              student: const OfflineAssetStudent(
                  studentId: '',
                  groupId: '',
                  groupName: '',
                  firstName: '',
                  lastName: ''),
              schoolCode: '999'),
          throwsA(isA<OfflineAssetException>()));
      expect(
          () => offlineAssetBody(
              payload: {},
              testKey: 'unit1_eng',
              student: _student,
              schoolCode: '999'),
          throwsA(isA<OfflineAssetException>()
              .having((e) => e.code, 'code', kOfflineUnknownAssetKey)));
    });
  });

  // ── S-N1: a student-typed answer must not be able to break the result ──────
  group('oversized typed answers (S-N1)', () {
    Map<String, dynamic> hugePayload() => {
          ..._runnerPayload(),
          'answers': [
            {
              'section': 'Spelling',
              'q': 'q0',
              'chosen': 'x' * 60000,
              'ok': false
            },
            {
              'section': 'Vocabulary',
              'q': 'q1',
              'chosen': 'a train',
              'ok': true
            },
            {'section': 'Reading', 'q': 'q2', 'chosen': 7},
          ],
        };

    test('offlineAssetBody clips chosen to $kMaxAnswerChars, nothing else', () {
      final src = hugePayload();
      final body = offlineAssetBody(
          payload: src,
          testKey: kAssetKeyUnit1,
          student: _student,
          schoolCode: '999');
      final a = (body['answers'] as List).cast<Map>();
      expect((a[0]['chosen'] as String).length, kMaxAnswerChars);
      expect(a[0]['section'], 'Spelling');
      expect(a[1]['chosen'], 'a train');
      expect(a[2]['chosen'], 7);
      // The runner's own map (the online queue's input) is untouched.
      expect(
          ((src['answers'] as List).first as Map)['chosen'], hasLength(60000));
      expect(utf8.encode(jsonEncode(body)).length, lessThan(2000));
    });

    test('clipping never splits a character', () {
      final body = offlineAssetBody(payload: {
        'answers': [
          {'chosen': '\u{1F600}' * 500}
        ]
      }, testKey: kAssetKeyUnit1, student: _student, schoolCode: '999');
      final c = ((body['answers'] as List).first as Map)['chosen'] as String;
      expect(c.runes.length, kMaxAnswerChars);
      expect(c.runes.every((r) => r == 0x1F600), isTrue);
    });

    test('the real longest expected answer (40 chars) is far below the limit',
        () {
      expect(kMaxAnswerChars, greaterThanOrEqualTo(5 * 40));
    });

    test('every free-text field of the three runners carries the limit', () {
      for (final f in [
        'lib/features/unit1/unit1_runner.dart',
        'lib/features/combined/combined_runner.dart',
        'lib/features/interhouse/interhouse_runner.dart',
      ]) {
        final src = File(f).readAsStringSync();
        final fields = RegExp(r'TextField\(').allMatches(src).length;
        final limited = RegExp(
                r'TextField\(\n\s+controller: [_a-z.]+,\n\s+inputFormatters: \[LengthLimitingTextInputFormatter\(kMaxAnswerChars\)\]')
            .allMatches(src)
            .length;
        expect(fields, 3, reason: f);
        expect(limited, fields, reason: f);
      }
    });

    test('USB: a 60 000-character answer is stored clipped; export entry small',
        () async {
      final tmp = Directory.systemTemp.createTempSync('asset_huge_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      await OfflinePackSession.open(
          lanTestPack(), Directory(p.join(tmp.path, 'media')));
      try {
        await recordOfflineAssetResult(
            payload: hugePayload(),
            token: 'huge',
            testKey: kAssetKeyUnit1,
            student: _student);
        final row = (await PackResultsDb.rowsForPack(lanPackUuid)).single;
        expect(row.payloadJson.length, lessThan(2000));
        expect(exportEntryBytes(row.payloadJson, row.metaJson),
            lessThan(HubLimits.resultBody));
      } finally {
        OfflinePackSession.close();
        await OfflineQueue.resetForTest();
        tmp.deleteSync(recursive: true);
      }
    });
  });

  // ── USB: the open pack's chain ─────────────────────────────────────────────
  group('USB pack mode', () {
    late Directory tmp;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('asset_usb_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      await OfflinePackSession.open(
          lanTestPack(), Directory(p.join(tmp.path, 'media')));
    });

    tearDown(() async {
      OfflinePackSession.close();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    test('the result lands in the pack chain, NOT in local_queue', () async {
      await recordOfflineAssetResult(
          payload: _runnerPayload(),
          token: 'k1',
          testKey: kAssetKeyUnit1,
          student: _student);

      final rows = await PackResultsDb.rowsForPack(lanPackUuid);
      expect(rows, hasLength(1));
      final saved = jsonDecode(rows.single.payloadJson) as Map;
      expect(saved['student_id'], lanS1);
      expect(saved['group_id'], lanG1);
      expect(saved['test_key'], 'asset:unit1_eng');
      expect(saved['school_code'], '999');
      expect(await OfflineQueue.pendingLocalCount(), 0);
      expect(await OfflineQueue.pendingCount(), 0);
    });

    test('all four runners record under their own key', () async {
      var i = 0;
      for (final key in kAssetTestKeys) {
        await recordOfflineAssetResult(
            payload: _runnerPayload(),
            token: 'k${i++}',
            testKey: key,
            student: _student);
      }
      final keys = [
        for (final r in await PackResultsDb.rowsForPack(lanPackUuid))
          (jsonDecode(r.payloadJson) as Map)['test_key']
      ];
      expect(keys, kAssetTestKeys.toList());
    });

    test('no student picked: nothing written anywhere, explicit error',
        () async {
      await expectLater(
          recordOfflineAssetResult(
              payload: _runnerPayload(),
              token: 'k',
              testKey: kAssetKeyUnit1,
              student: null),
          throwsA(isA<OfflineAssetException>()));
      expect(await PackResultsDb.rowsForPack(lanPackUuid), isEmpty);
      expect(await OfflineQueue.pendingLocalCount(), 0);
    });

    test('a retry under the same token is idempotent (one row)', () async {
      for (var i = 0; i < 3; i++) {
        await recordOfflineAssetResult(
            payload: _runnerPayload(),
            token: 'same',
            testKey: kAssetKeyUnit1,
            student: _student);
      }
      expect(await PackResultsDb.rowsForPack(lanPackUuid), hasLength(1));
    });
  });

  // ── LAN: through the hub ───────────────────────────────────────────────────
  group('LAN hub', () {
    late Directory tmp;
    late ShelfHub hub;
    late http.Client client;
    late String base;

    setUp(() async {
      client = http.Client();
      tmp = Directory.systemTemp.createTempSync('asset_hub_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      final session = await OfflinePackSession.open(
          lanTestPack(), Directory(p.join(tmp.path, 'media')));
      hub = ShelfHub(session,
          bindAddress: InternetAddress.loopbackIPv4,
          firstPort: 0,
          lastPort: 0,
          clock: MonitoredClock(
              ticks: () => 1000000, wall: () => 0, highWaterStore: _MemHwm()));
      await hub.start(announce: false);
      base = 'http://127.0.0.1:${hub.port}';
    });

    tearDown(() async {
      client.close();
      await hub.stop();
      hub.dispose();
      OfflinePackSession.close();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    Future<String> join() async {
      final r = await client.post(Uri.parse('$base/join'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'code': hub.state!.code,
            'machine_id': 'machine-1',
            'device_name': 'PC 1'
          }));
      expect(r.statusCode, 200, reason: r.body);
      return (jsonDecode(r.body) as Map)['token'] as String;
    }

    Future<http.Response> send(
        String token, String key, Map<String, dynamic> payload) {
      return client.post(Uri.parse('$base/result'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
            'idempotency-key': key,
          },
          body: jsonEncode({'payload': payload}));
    }

    Map<String, dynamic> body(String key) => offlineAssetBody(
        payload: _runnerPayload(),
        testKey: key,
        student: _student,
        schoolCode: '999');

    test('admits exactly the closed asset key list', () async {
      final t = await join();
      var i = 0;
      for (final key in kAssetTestKeys) {
        final r = await send(t, 'a${i++}', body(key));
        expect(r.statusCode, 200, reason: '$key ${r.body}');
      }
      expect(await PackResultsDb.rowsForPack(lanPackUuid),
          hasLength(kAssetTestKeys.length));
    });

    test('everything else that is not in the pack is still refused', () async {
      final t = await join();
      // A look-alike inside the namespace, and the runners' NATIVE keys.
      for (final bad in [
        'asset:other',
        'asset:',
        'unit1_eng',
        'monitoring_unit1',
        'interhouse_g2',
        'bob1_4',
        'diag:english:g9:uz:v9',
      ]) {
        final top = {...body(kAssetKeyUnit1), 'test_key': bad};
        var r = await send(t, 'top-$bad', top);
        expect(r.statusCode, 422, reason: 'top-level $bad');
        expect((jsonDecode(r.body) as Map)['reason'], 'test_not_in_pack');

        final det = {
          ...body(kAssetKeyUnit1),
          'detail': {'test_key': bad}
        };
        r = await send(t, 'det-$bad', det);
        expect(r.statusCode, 422, reason: 'detail $bad');
        expect((jsonDecode(r.body) as Map)['reason'], 'test_not_in_pack');
      }
      expect(await PackResultsDb.rowsForPack(lanPackUuid), isEmpty);
    });

    test('an asset key does not bypass the roster check', () async {
      final t = await join();
      final r = await send(t, 'x', {
        ...body(kAssetKeyUnit1),
        'student_id': '00000000-0000-4000-8000-0000000000ff'
      });
      expect(r.statusCode, 422);
      expect((jsonDecode(r.body) as Map)['reason'], 'student_invalid');
      // ... nor the (student, group) pairing.
      final r2 =
          await send(t, 'y', {...body(kAssetKeyUnit1), 'group_id': lanG2});
      expect((jsonDecode(r2.body) as Map)['reason'], 'student_invalid');
    });

    test('the largest real assets body (79 long answers) fits the hub limit',
        () async {
      final big = offlineAssetBody(payload: {
        ..._runnerPayload(),
        'answers': [
          for (var i = 0; i < 79; i++)
            {
              'section': 'Reading',
              'q': 'Q$i ${'w' * 200}',
              'chosen': 'c' * 60,
              'correct': 'd' * 60,
              'ok': false,
            }
        ],
      }, testKey: kAssetKeyCombined, student: _student, schoolCode: '999');
      final size = utf8.encode(jsonEncode({'payload': big})).length;
      expect(size, lessThan(HubLimits.resultBody ~/ 2),
          reason: 'must keep >= 50% headroom, was $size');
      final r = await send(await join(), 'big', big);
      expect(r.statusCode, 200, reason: r.body);
    });

    test('a 60 000-char answer: unclipped would be 413, clipped is accepted',
        () async {
      final raw = {
        ..._runnerPayload(),
        'answers': [
          {'section': 'Spelling', 'q': 'q', 'chosen': 'x' * 60000, 'ok': false},
        ],
      };
      final t = await join();
      // Without the clip the hub refuses it (the student would see "saved").
      final unclipped = await send(
          t,
          'raw',
          {
            ...raw,
            'student_id': lanS1,
            'group_id': lanG1,
            'test_key': kAssetKeyUnit1,
          }..['answers'] = [
              {'chosen': 'x' * 70000}
            ]);
      expect(unclipped.statusCode, 413);
      final clipped = offlineAssetBody(
          payload: raw,
          testKey: kAssetKeyUnit1,
          student: _student,
          schoolCode: '999');
      final r = await send(t, 'clipped', clipped);
      expect(r.statusCode, 200, reason: r.body);
    });

    test(
        'LAN client: recordOfflineAssetResult -> outbox -> hub -> pack chain '
        '(student PC has a LanClientSession and no pack)', () async {
      final lan = await LanClientSession.join(
        host: '127.0.0.1',
        port: hub.port!,
        code: hub.state!.code,
        client: http.Client(),
        machineId: 'pc-1',
        deviceName: 'pc-1',
        mediaDirFor: (id) async => Directory(p.join(tmp.path, 'cm')),
      );
      final pack = OfflinePackSession.current;
      OfflinePackSession.current = null; // a student PC has no pack open
      LanClientSession.current = lan;
      try {
        expect(offlineContentSource, same(lan));
        expect(isOfflineContentMode, isTrue);
        await recordOfflineAssetResult(
            payload: _runnerPayload(),
            token: 'lan-1',
            testKey: kAssetKeyInterhouse,
            student: _student);
        // recordResult already started a background flush; wait for the ack.
        for (var i = 0;
            i < 100 && (await PackResultsDb.rowsForPack(lanPackUuid)).isEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      } finally {
        LanClientSession.current = null;
        OfflinePackSession.current = pack;
        lan.close();
      }
      final rows = await PackResultsDb.rowsForPack(lanPackUuid);
      expect(rows, hasLength(1));
      final saved = jsonDecode(rows.single.payloadJson) as Map;
      expect(saved['test_key'], 'asset:interhouse_g2');
      expect(saved['student_id'], lanS1);
      expect(saved['school_code'], '999'); // from the hub, not the typed field
      expect(hub.state!.resultsAccepted, 1);
      expect(await OfflineQueue.pendingLocalCount(), 0);
    });
  });

  // ── the real result screens ────────────────────────────────────────────────
  group('result screens in USB mode', () {
    late Directory tmp;
    late IhTestData ih;

    setUpAll(() async {
      ih = await IhLoader.load();
    });

    setUp(() async {
      await TestWidgetsFlutterBinding.instance.runAsync(() async {
        tmp = Directory.systemTemp.createTempSync('asset_ui_');
        await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
        await OfflinePackSession.open(
            lanTestPack(), Directory(p.join(tmp.path, 'media')));
      });
    });

    tearDown(() async {
      await TestWidgetsFlutterBinding.instance.runAsync(() async {
        OfflinePackSession.close();
        await OfflineQueue.resetForTest();
        tmp.deleteSync(recursive: true);
      });
    });

    Future<List<PackResultRow>> waitRows(WidgetTester t, int n) async {
      var rows = <PackResultRow>[];
      for (var i = 0; i < 100 && rows.length < n; i++) {
        rows =
            (await t.runAsync(() => PackResultsDb.rowsForPack(lanPackUuid)))!;
        if (rows.length >= n) break;
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump();
      }
      await t.pump();
      return rows;
    }

    final cases = <String,
        ({
      Widget Function(OfflineAssetStudent?, IhTestData) build,
      String key
    })>{
      'unit1': (build: (s, _) => unit1Result(s), key: 'asset:unit1_eng'),
      'combined': (
        build: (s, _) => combinedResult(s),
        key: 'asset:monitoring_unit1'
      ),
      'interhouse': (
        build: (s, d) => interhouseResult(s, d),
        key: 'asset:interhouse_g2'
      ),
      'bob14/local': (build: (s, _) => localResult(s), key: 'asset:bob1_4'),
    };

    for (final e in cases.entries) {
      testWidgets('${e.key}: saved to the chain, no score, nothing queued',
          (tester) async {
        await tester.pumpWidget(assetTestApp(e.value.build(_student, ih)));
        final rows = await waitRows(tester, 1);

        expect(rows, hasLength(1));
        final saved = jsonDecode(rows.single.payloadJson) as Map;
        expect(saved['student_id'], lanS1);
        expect(saved['group_id'], lanG1);
        expect(saved['test_key'], e.value.key);
        expect((saved['detail'] as Map)['test_key'], e.value.key);
        expect(saved['school_code'], '999');

        final l10n =
            AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
        expect(find.text(l10n.usbSavedTitle), findsOneWidget);
        expect(find.textContaining('%'), findsNothing);
        expect(find.textContaining(RegExp(r'\d+\s*/\s*\d+')), findsNothing);
        expect(await tester.runAsync(OfflineQueue.pendingLocalCount), 0);
        expect(await tester.runAsync(OfflineQueue.pendingCount), 0);
      });

      testWidgets('${e.key}: no student -> honest failure, nothing written',
          (tester) async {
        await tester.pumpWidget(assetTestApp(e.value.build(null, ih)));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();

        final l10n =
            AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
        expect(find.text(l10n.resultNotSavedError), findsOneWidget);
        expect(find.text(l10n.retry), findsOneWidget);
        expect(find.text(l10n.usbSavedTitle), findsNothing);
        expect(
            await tester.runAsync(() => PackResultsDb.rowsForPack(lanPackUuid)),
            isEmpty);
        expect(await tester.runAsync(OfflineQueue.pendingLocalCount), 0);
      });
    }
  });

  // ── student gate on the entry screens ──────────────────────────────────────
  group('entry screens', () {
    late Directory tmp;

    Future<void> open(WidgetTester t) async {
      await t.runAsync(() async {
        tmp = Directory.systemTemp.createTempSync('asset_entry_');
        await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
        await OfflinePackSession.open(
            lanTestPack(), Directory(p.join(tmp.path, 'media')));
      });
    }

    Future<void> close(WidgetTester t) async {
      await t.runAsync(() async {
        OfflinePackSession.close();
        await OfflineQueue.resetForTest();
        tmp.deleteSync(recursive: true);
      });
    }

    testWidgets('picker: group -> student gives the roster ids',
        (tester) async {
      await open(tester);
      OfflineAssetStudent? picked;
      await tester.pumpWidget(assetTestApp(
          Scaffold(body: OfflineStudentPicker(onChanged: (s) => picked = s))));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('offline_group')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5-A | Ingliz').last);
      await tester.pumpAndSettle();
      expect(picked, isNull);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valiyev Ali').last);
      await tester.pumpAndSettle();

      expect(picked?.studentId, lanS1);
      expect(picked?.groupId, lanG1);
      expect(picked?.groupName, '5-A | Ingliz');
      expect(picked?.lastName, 'Valiyev');
      expect(picked?.firstName, 'Ali');
      await close(tester);
    });

    testWidgets(
        'pack open: roster picker replaces the name fields and a run '
        'cannot start without a student', (tester) async {
      await open(tester);
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(assetTestApp(const CombinedScreen()));
      await tester.pump(const Duration(milliseconds: 500));
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

      await tester.tap(find.text('1').first); // variant 1
      await tester.pump();
      await tester.tap(find.text(l10n.continueButton));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OfflineStudentPicker), findsOneWidget);
      expect(find.text(l10n.firstNameLabel), findsNothing);

      await tester.enterText(find.byType(TextField).last, '1234');
      await tester.tap(find.text(l10n.startTest));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(l10n.selectStudent), findsWidgets);
      expect(find.byType(CombinedScreen), findsOneWidget); // did not start
      await close(tester);
    });

    testWidgets('online (no pack): unchanged name fields, no picker',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(assetTestApp(const CombinedScreen()));
      await tester.pump(const Duration(milliseconds: 500));
      final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
      await tester.tap(find.text('1').first);
      await tester.pump();
      await tester.tap(find.text(l10n.continueButton));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(OfflineStudentPicker), findsNothing);
      expect(find.text(l10n.firstNameLabel), findsWidgets);
    });
  });
}
