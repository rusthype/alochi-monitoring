// LAN client (phase 3): LanClientSession + LanClientApi against the REAL hub
// on loopback. The key promise: a result is kept in the encrypted outbox until
// the hub acknowledges it, so a hub that is down never costs a result.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/lan_outbox_db.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/core/offline/lan_client_api.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/lan_diagnostic_api.dart';
import 'package:alochi_monitoring/core/offline/offline_crypto.dart';
import 'package:alochi_monitoring/core/offline/offline_errors.dart';
import 'package:alochi_monitoring/core/offline/offline_media.dart';
import 'package:alochi_monitoring/core/offline/offline_package_api.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart' show LoadedPack;
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/core/local_server/hub_guard.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/lan_test_pack.dart';

/// The "real server" on a school LAN without internet: unreachable.
class _NoInternetApi extends MonitoringApi {
  @override
  Future<bool> ping() async => false;
  @override
  Future<bool> pingHealth(
          {Duration timeout = const Duration(seconds: 2)}) async =>
      false;
}

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

final String _mediaSha = OfflineCrypto.sha256Hex(lanMediaBytes);

Future<void> eventually(Future<bool> Function() cond,
    {Duration timeout = const Duration(seconds: 8)}) async {
  final end = DateTime.now().add(timeout);
  while (!await cond()) {
    if (DateTime.now().isAfter(end)) fail('condition not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ShelfHub hub;
  late MonitoredClock clock;
  final sessions = <LanClientSession>[];

  setUpAll(() {
    HttpOverrides.global =
        null; // real loopback sockets, not flutter_test's mock
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lan_client_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    clock = MonitoredClock(
        ticks: () => 1000000, wall: () => 0, highWaterStore: _MemHwm());
    final media = makeMediaDir(tmp, _mediaSha);
    final session = await OfflinePackSession.open(
        lanTestPack(mediaRef: 'media/$_mediaSha.jpg'), media);
    hub = ShelfHub(session,
        bindAddress: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
        clock: clock);
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

  Future<LanClientSession> connect(
      {String machine = 'student-pc-1', String? code, int? port}) async {
    final s = await LanClientSession.join(
      host: '127.0.0.1',
      port: port ?? hub.port!,
      code: code ?? hub.state!.code,
      client: http.Client(),
      machineId: machine,
      deviceName: 'PC',
      mediaDirFor: (id) async =>
          Directory(p.join(tmp.path, 'client_media', id)),
    );
    sessions.add(s);
    return s;
  }

  group('join', () {
    test('wrong code, throttling, bad address, unreachable hub', () async {
      final wrong = hub.state!.code == '000000' ? '111111' : '000000';
      for (var i = 0; i < 5; i++) {
        await expectLater(
            connect(code: wrong),
            throwsA(isA<LanJoinException>()
                .having((e) => e.code, 'code', LanJoinError.badCode)));
      }
      await expectLater(
          connect(),
          throwsA(isA<LanJoinException>()
              .having((e) => e.code, 'code', LanJoinError.blocked)
              .having((e) => e.retryAfterSec, 'retry', greaterThan(0))));

      await expectLater(
          LanClientSession.join(host: 'bad host!', port: 8080, code: '123456'),
          throwsA(isA<LanJoinException>()
              .having((e) => e.code, 'code', LanJoinError.badAddress)));
      await expectLater(
          LanClientSession.join(host: '127.0.0.1', port: 0, code: '123456'),
          throwsA(isA<LanJoinException>()
              .having((e) => e.code, 'code', LanJoinError.badAddress)));

      // A port nobody listens on.
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final dead = s.port;
      await s.close();
      await expectLater(
          LanClientSession.join(host: '127.0.0.1', port: dead, code: '123456'),
          throwsA(isA<LanJoinException>()
              .having((e) => e.code, 'code', LanJoinError.unreachable)));
    });

    test('join exposes the hub identity, activate() refuses beside a USB pack',
        () async {
      final s = await connect();
      expect(s.packUuid, lanPackUuid);
      expect(s.schoolCode, '999');
      expect(s.schoolId, lanSchool);
      await expectLater(
          s.activate(),
          throwsA(isA<LanJoinException>()
              .having((e) => e.code, 'code', LanJoinError.packActive)));
    });
  });

  group('N-4 the old hub\'s bearer token', () {
    Future<LanClientSession> rejoin(LanClientSession old,
            {required String host, required int port}) =>
        LanClientSession.join(
          host: host,
          port: port,
          code: hub.state!.code,
          client: http.Client(),
          machineId: 'student-pc-1',
          deviceName: 'PC',
          replacing: old,
          mediaDirFor: (id) async =>
              Directory(p.join(tmp.path, 'client_media', id)),
        );

    test(
        'it goes only to the very host and port that issued it -- never to '
        'another (rogue) hub', () async {
      final old = await connect();
      expect(old.isSameHub('127.0.0.1', hub.port!), isTrue);
      expect(old.isSameHub('127.0.0.1', hub.port! + 1), isFalse);
      expect(old.isSameHub('localhost', hub.port!), isFalse);

      // A hub that is not the old one, recording what it is sent.
      final rogue = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <HttpHeaders>[];
      rogue.listen((req) {
        seen.add(req.headers);
        req.response
          ..statusCode = 401
          ..write('{}');
        req.response.close();
      });
      addTearDown(() => rogue.close(force: true));

      await expectLater(
          rejoin(old, host: '127.0.0.1', port: rogue.port),
          throwsA(isA<LanJoinException>()
              .having((e) => e.code, 'code', LanJoinError.badCode)));
      expect(seen, hasLength(1));
      expect(seen.single.value('authorization'), isNull,
          reason: 'the old hub\'s token must not reach another address');
    });

    test('...but a re-join to the SAME hub still presents it (join lock)',
        () async {
      final old = await connect();
      hub.state!.setJoinsLocked(true);
      // Without the token a locked hub refuses; with it, the PC is let back in.
      final again = await rejoin(old, host: '127.0.0.1', port: hub.port!);
      sessions.add(again);
      expect(again.hubName, old.hubName);
    });
  });

  group('F-2 a student over the hub\'s cap is never dropped', () {
    test(
        'student_quota keeps the row queued (not "rejected"), shows the hold '
        'and the hub counts the refusal for the teacher', () async {
      final s = await connect();
      final cap = hub.resultsPerStudentCap;
      for (var i = 0; i <= cap; i++) {
        await s.recordResult(lanResultPayload(), token: 'honest-$i');
      }
      // (recordResult already flushes in the background: wait for the hold)
      await eventually(() async {
        await s.flushOutbox();
        return s.hold.value != null;
      });
      final counts = await LanOutboxDb.counts();
      expect(counts.rejected, 0, reason: 'must not be marked rejected');
      expect(counts.pending, 1);
      expect(s.hold.value, 'student_quota');
      expect(hub.state!.resultsAccepted, cap);
      expect(hub.state!.refusedResults, 1);
      // slow retry: an immediate flush does not hammer the hub
      expect(await s.flushOutbox(), 0);
      expect((await LanOutboxDb.counts()).pending, 1);
    });
  });

  group('content', () {
    test('LanClientApi serves exactly what OfflinePackageApi would', () async {
      final s = await connect();
      final lan = LanClientApi(s);
      final local = OfflinePackageApi(OfflinePackSession.current!);

      expect(await lan.fetchGroups('999'), await local.fetchGroups('999'));
      expect(await lan.fetchStudents(lanG1), await local.fetchStudents(lanG1));
      expect(await lan.fetchTestCatalog(groupId: lanG2),
          await local.fetchTestCatalog(groupId: lanG2));
      expect((await lan.getTestCatalog()).map((e) => e.testKey),
          (await local.getTestCatalog()).map((e) => e.testKey));
      expect((await lan.getPackages(5)).single.id, '42');
      expect((await lan.getQuestions('42', 1)).single.id, 'q1');
      expect(await lan.getQuestions('42', 9), isEmpty);
      await expectLater(
          lan.getTestDetail('missing'),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', kOfflineNotFound)));
      expect(await lan.fetchTest('missing'), isNull);
    });

    test('fetchTest pulls the test AND its images (hash-verified) first',
        () async {
      final s = await connect();
      final lan = LanClientApi(s);
      final data = await lan.fetchTest('t_all');
      expect(data, isNotNull);
      expect(data!['test_key'], 't_all');
      final file = File(p.join(s.mediaDir.path, '$_mediaSha.jpg'));
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), lanMediaBytes);

      // The same names the engine resolves through OfflineMedia.
      OfflineMedia.root = s.mediaDir;
      addTearDown(() => OfflineMedia.root = null);
      expect(OfflineMedia.fileFor('media/$_mediaSha.jpg')!.path, file.path);
    });

    test('an image whose bytes do not match its name is refused', () async {
      // Corrupt the file the HUB serves (same name, other bytes).
      final hubFile = File(p.join(tmp.path, 'media', '$_mediaSha.jpg'));
      hubFile.writeAsBytesSync(Uint8List.fromList([9, 9, 9]));
      final s = await connect();
      final lan = LanClientApi(s);
      expect(await lan.fetchTest('t_all'), isNull);
      expect(File(p.join(s.mediaDir.path, '$_mediaSha.jpg')).existsSync(),
          isFalse);
    });

    test('mediaNamesIn finds only well-formed pack references', () {
      final names = LanClientSession.mediaNamesIn({
        'a': ['media/$_mediaSha.jpg', 'media/../x.jpg', 'http://x/y.jpg'],
        'b': {'c': 'media/${'A' * 64}.jpg', 'd': 'media/$_mediaSha.exe'},
      });
      expect(names, {'$_mediaSha.jpg'});
    });
  });

  group('outbox: nothing is lost until the hub acks', () {
    Future<int> hubRows() async =>
        (await PackResultsDb.rowsForPack(lanPackUuid)).length;

    test('recordResult -> hub ack -> outbox is empty, chain has the row',
        () async {
      final s = await connect();
      await s.recordResult(lanResultPayload(), token: 'k1');
      await eventually(() async => (await hubRows()) == 1);
      await eventually(
          () async => (await LanOutboxDb.pending(lanPackUuid)).isEmpty);
      await eventually(() async => s.pending.value == 0);

      // Same token again (a retry): acknowledged, still one row.
      await s.recordResult(lanResultPayload(), token: 'k1');
      await s.flushOutbox();
      expect(await hubRows(), 1);
    });

    test('hub down: the result waits (encrypted); hub back: it is delivered',
        () async {
      final s = await connect();
      await hub.stop();
      await s.recordResult(lanResultPayload(), token: 'offline-1');
      await s.recordResult(lanResultPayload(), token: 'offline-2');
      expect(await s.flushOutbox(), 0);
      await eventually(() async => !s.connected.value);
      expect((await LanOutboxDb.pending(lanPackUuid)), hasLength(2));
      expect(s.pending.value, 2);

      // At rest it is not readable.
      final db = await OfflineQueue.db;
      final raw = (await db.query('lan_outbox')).first['envelope'] as String;
      expect(raw, startsWith('ENC1:'));
      expect(raw, isNot(contains(lanS1)));

      // The teacher restarts the hub: new code, new port; the student joins
      // again and the backlog drains IN ORDER.
      await hub.start(announce: false);
      final s2 = await connect(port: hub.port);
      expect(await s2.flushOutbox(), 2);
      expect(await LanOutboxDb.pending(lanPackUuid), isEmpty);
      final rows = await PackResultsDb.rowsForPack(lanPackUuid);
      expect(rows.map((r) => r.idempotencyKey), ['offline-1', 'offline-2']);
    });

    test('a result the hub refuses for good is KEPT and flagged, not dropped',
        () async {
      final s = await connect();
      await s.recordResult(
          lanResultPayload(student: '00000000-0000-4000-8000-0000000000ff'),
          token: 'bad-student');
      await eventually(() async => (await LanOutboxDb.counts()).rejected == 1);
      expect((await LanOutboxDb.counts()).pending, 0);
      expect(await hubRows(), 0);
      final db = await OfflineQueue.db;
      final row = (await db.query('lan_outbox')).single;
      expect(row['status'], LanOutboxDb.statusRejected);
      expect(row['reject_reason'], 'student_invalid');
      // A rejected row is not retried.
      expect(await LanOutboxDb.pending(lanPackUuid), isEmpty);
    });

    test('rows of another pack are not posted to this hub', () async {
      await LanOutboxDb.enqueue(
          packUuid: 'some-other-pack',
          idempotencyKey: 'foreign',
          envelopeJson: jsonEncode({'payload': lanResultPayload()}));
      final s = await connect();
      expect(await s.flushOutbox(), 0);
      expect(await hubRows(), 0);
      expect((await LanOutboxDb.counts()).pending, 1);
    });

    test('the API entry points all land in the outbox', () async {
      final s = await connect();
      final lan = LanClientApi(s);
      expect(
          (await lan.submitLocalResultFull(
              lanResultPayload(), 'via-api'))['synced'],
          isTrue);
      await eventually(() async => (await hubRows()) == 1);
      expect(
          (await PackResultsDb.rowsForPack(lanPackUuid)).single.idempotencyKey,
          'via-api');
      // An unusable key is hashed, deterministically, not sent raw.
      await s.recordResult(lanResultPayload(), token: 'has space/and slash');
      await eventually(() async => (await hubRows()) == 2);
      expect((await PackResultsDb.rowsForPack(lanPackUuid)).last.idempotencyKey,
          startsWith('h:'));
    });

    test('incidents and clock flags ride along into the chain meta', () async {
      final s = await connect();
      await s.recordResult(lanResultPayload(), token: 'meta');
      await eventually(() async => (await hubRows()) == 1);
      final meta = jsonDecode(
              (await PackResultsDb.rowsForPack(lanPackUuid)).single.metaJson)
          as Map<String, dynamic>;
      expect(meta['idempotency_key'], 'meta');
      expect((meta['incidents'] as List).last['type'], 'lan_client');
      expect((meta['incidents'] as List).last['machine_id'], 'student-pc-1');
    });
  });

  group('diagnostic over LAN', () {
    test('roster + questions from the hub snapshot; answers reach the chain',
        () async {
      final s = await connect();
      final d = LanDiagnosticKioskApi(s);

      final (schools, _) = await d.listSchools();
      expect(schools.single['school_id'], lanSchool);
      final (classes, _) = await d.listClasses(lanSchool);
      expect(classes.map((c) => c['class_label']), contains('5-A | Ingliz'));
      final (students, _) = await d.listStudents(lanSchool, '5-A | Ingliz');
      expect(students.single['student_name'], 'Valiyev Ali');
      final attemptId = students.single['attempt_id'] as String;
      expect(attemptId, 'offline|$lanS1|$lanG1|uz');

      expect((await d.availableSubjects(5))['subjects'], ['math']);
      final start = await d.startAttempt(attemptId: attemptId, subject: 'math');
      final qs = start['questions'] as List;
      expect(qs.single['option_b'], '4');
      expect(start['test_key'], 'diag:math:g5:uz:v1');

      final answers = [
        {'question_id': 'math-q1', 'selected': 'B'}
      ];
      expect(
          (await d.finishAttempt(attemptId: attemptId, answers: answers))['ok'],
          isTrue);
      // A genuine retake is a NEW entry, not swallowed as a duplicate.
      expect(
          (await d.finishAttempt(attemptId: attemptId, answers: answers))['ok'],
          isTrue);

      await eventually(() async {
        await s.flushOutbox();
        return (await PackResultsDb.rowsForPack(lanPackUuid)).length == 2;
      });
      final rows = await PackResultsDb.rowsForPack(lanPackUuid);
      final first = jsonDecode(rows.first.payloadJson) as Map<String, dynamic>;
      expect(first['test_key'], 'diag:math:g5:uz:v1');
      expect(first['student_id'], lanS1);
      expect(first['answers'], [
        {'q': 'math-q1', 'a': 'B'}
      ]);
      // Old pack (no subjects_done / done_students): never flagged as a retake.
      expect(rows.map((r) => jsonDecode(r.payloadJson) as Map),
          everyElement(isNot(contains('retake'))));
      expect(rows.map((r) => r.idempotencyKey).toSet(), hasLength(2));
      expect(rows.first.idempotencyKey.length, lessThanOrEqualTo(64));
    });
  });

  group('diagnostic retake over LAN', () {
    const doneId = '00000000-0000-4000-8000-0000000000e5';

    Future<void> restartHub(LoadedPack pack) async {
      await hub.stop();
      hub.dispose();
      OfflinePackSession.close();
      final session = await OfflinePackSession.open(
          pack, Directory(p.join(tmp.path, 'media2')));
      hub = ShelfHub(session,
          bindAddress: InternetAddress.loopbackIPv4,
          firstPort: 0,
          lastPort: 0,
          clock: clock);
      await hub.start(announce: false);
    }

    Future<List<Map<String, dynamic>>> chain(int n, LanClientSession s) async {
      await eventually(() async {
        await s.flushOutbox();
        return (await PackResultsDb.rowsForPack(lanPackUuid)).length == n;
      });
      return [
        for (final r in await PackResultsDb.rowsForPack(lanPackUuid))
          jsonDecode(r.payloadJson) as Map<String, dynamic>
      ];
    }

    test('done_students + subjects_done reach the client; retake lands in chain',
        () async {
      await restartHub(lanTestPack(
        englishDiag: true,
        subjectsDone: {
          lanS1: ['math']
        },
        doneStudents: [
          {
            'id': doneId,
            'name': 'Done Dilnoza',
            'group_id': lanG1,
            'subjects_done': ['math', 'english'],
          }
        ],
      ));
      final s = await connect();
      final d = LanDiagnosticKioskApi(s);
      final (rows, _) = await d.listStudents(lanSchool, '5-A | Ingliz');
      List<Object?> row(Map<String, dynamic> r) =>
          [r['student_name'], r['status'], r['next_subject']];
      expect(rows.map(row).toList(), [
        ['Valiyev Ali', 'partial', 'english'],
        ['Done Dilnoza', 'completed', ''],
      ]);

      Future<void> finish(String sid, String q) => d.finishAttempt(
              attemptId: 'offline|$sid|$lanG1|uz',
              answers: [
                {'question_id': q, 'selected': 'A'}
              ]);
      await finish(lanS1, 'english-q1'); // not done yet: plain result
      await finish(lanS1, 'math-q1'); // done online: retake
      await finish(doneId, 'math-q1'); // done_students row: retake
      final got = await chain(3, s);
      Map<String, dynamic> entry(String sid, String key) => got
          .firstWhere((e) => e['student_id'] == sid && e['test_key'] == key);
      expect(entry(lanS1, 'diag:english:g5:uz:v1').containsKey('retake'),
          isFalse);
      expect(entry(lanS1, 'diag:math:g5:uz:v1')['retake'], isTrue);
      expect(entry(doneId, 'diag:math:g5:uz:v1')['retake'], isTrue);
    });
  });

  group('proctoring over the client API', () {
    test('sessionPing / proctorFrame reach the hub and bring commands back',
        () async {
      final s = await connect();
      final lan = LanClientApi(s);
      final reply = await lan.sessionPing(
        sessionId: 'S1',
        name: 'Valiyev Ali',
        testKey: 't_all',
        studentCode: lanS1,
        tabSwitchCount: 1,
        currentQuestionIndex: 0,
        totalQuestions: 5,
        deviceName: 'PC',
        capabilities: const ['pause_lock'],
        answers: {'x': 'y'},
      );
      expect(reply['locked'], false);
      expect(reply['proctor_token'], isNotEmpty);
      expect(hub.state!.views().single.status.name, 'testing');

      final id = hub.state!.views().single.id;
      hub.state!.setLocked(id, true);
      final jpeg = lanJpeg(marker: 'client-frame');
      final fr = await lan.proctorFrame(
          sessionId: 'S1',
          token: reply['proctor_token'] as String,
          jpeg: jpeg,
          focus: true,
          monitorCount: 1,
          questionIndex: 0,
          totalQuestions: 5,
          frameType: 'keyframe');
      expect(fr['locked'], true);
      expect(hub.state!.frameOf(id), jpeg);

      // A frame for a session the hub does not know is "no action", not a throw.
      expect(
          await lan.proctorFrame(
              sessionId: 'nope',
              token: 't',
              jpeg: jpeg,
              focus: true,
              monitorCount: 1),
          isEmpty);
      expect(await lan.sessionResume('t_all'), {'exists': false});
    });

    test('a kicked client learns its token is gone and must re-join', () async {
      final s = await connect();
      final lan = LanClientApi(s);
      hub.state!.kick(hub.state!.views().single.id);
      await expectLater(
          lan.fetchGroups('999'),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', kLanSessionExpired)));
      expect(s.needsRejoin.value, isTrue);
    });

    test('ping() is the hub health probe (drives the connectivity dot)',
        () async {
      final s = await connect();
      final lan = LanClientApi(s);
      expect(await lan.ping(), isTrue);
      await hub.stop();
      expect(await lan.ping(), isFalse);
    });
  });

  group('T2 review (client side)', () {
    test('fingerprint of the pack matches the one the hub shows', () async {
      final s = await connect();
      expect(s.fingerprint, packFingerprint(lanPackUuid));
      expect(s.fingerprint, matches(RegExp(r'^[0-9A-F]{6}$')));
    });

    test('close() tells the hub (the PC does not linger as a ghost)', () async {
      final s = await connect();
      expect(hub.state!.clientCount, 1);
      s.close();
      await eventually(() async => hub.state!.clientCount == 0);
    });

    test('a closed hub says so: joinsClosed; a live token refreshes anyway',
        () async {
      final s = await connect(machine: 'in-already');
      hub.state!.setJoinsLocked(true);
      await expectLater(
          connect(machine: 'latecomer'),
          throwsA(isA<LanJoinException>()
              .having((e) => e.code, 'code', LanJoinError.joinsClosed)));
      final again = await LanClientSession.join(
          host: '127.0.0.1',
          port: hub.port!,
          code: hub.state!.code,
          client: http.Client(),
          machineId: 'in-already',
          replacing: s,
          mediaDirFor: (id) async => Directory(p.join(tmp.path, 'cm2')));
      sessions.add(again);
      expect(again.packUuid, lanPackUuid);
    });

    test(
        'pack_full / client_quota: the result is NOT dropped; it is held, '
        'shown, and retried slowly', () async {
      // A second hub on the same pack that takes only 2 results per address.
      await hub.stop();
      final small = ShelfHub(OfflinePackSession.current!,
          bindAddress: InternetAddress.loopbackIPv4,
          firstPort: 0,
          lastPort: 0,
          clock: clock,
          maxResultsPerIp: 2);
      await small.start(announce: false);
      addTearDown(() async {
        await small.stop();
        small.dispose();
      });
      final s = await connect(port: small.port, code: small.state!.code);
      for (var i = 0; i < 3; i++) {
        await s.recordResult(lanResultPayload(), token: 'held-$i');
        await s.flushOutbox();
      }
      await eventually(() async {
        await s.flushOutbox();
        return s.hold.value != null;
      });
      expect(s.hold.value, 'client_quota');
      expect(await PackResultsDb.rowsForPack(lanPackUuid), hasLength(2));
      // Still queued (pending), never flagged rejected, never deleted.
      final counts = await LanOutboxDb.counts();
      expect(counts.pending, 1);
      expect(counts.rejected, 0);
      // No retry storm: while held, flushing does not even hit the hub.
      final before = (await LanOutboxDb.pending(lanPackUuid)).single.attempts;
      for (var i = 0; i < 5; i++) {
        await s.flushOutbox();
      }
      expect((await LanOutboxDb.pending(lanPackUuid)).single.attempts, before);
    });

    test('pack_full holds the same way (and a later ack clears the hold)',
        () async {
      await hub.stop();
      final small = ShelfHub(OfflinePackSession.current!,
          bindAddress: InternetAddress.loopbackIPv4,
          firstPort: 0,
          lastPort: 0,
          clock: clock,
          maxPackEntries: 1);
      await small.start(announce: false);
      addTearDown(() async {
        await small.stop();
        small.dispose();
      });
      final s = await connect(port: small.port, code: small.state!.code);
      await s.recordResult(lanResultPayload(), token: 'fits');
      await s.recordResult(lanResultPayload(), token: 'does-not-fit');
      await eventually(() async {
        await s.flushOutbox();
        return s.hold.value != null;
      });
      expect(s.hold.value, 'pack_full');
      expect((await LanOutboxDb.counts()).rejected, 0);
      expect((await LanOutboxDb.counts()).pending, 1);
    });

    test('a pack_uuid that is not a UUID is refused as a bad hub response',
        () async {
      final fake = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => fake.close(force: true));
      fake.listen((req) async {
        req.response
          ..statusCode = 200
          ..write(jsonEncode({
            'token': 'x' * 32,
            'pack_uuid': '../../etc/passwd',
            'hub_name': 'evil'
          }));
        await req.response.close();
      });
      await expectLater(
          LanClientSession.join(
              host: '127.0.0.1', port: fake.port, code: '123456'),
          throwsA(isA<LanJoinException>()
              .having((e) => e.code, 'code', LanJoinError.badResponse)));
    });

    test('hub answers are size-capped (join 64 KB, JSON 4 MB)', () async {
      final fake = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => fake.close(force: true));
      var padJoin = true;
      fake.listen((req) async {
        final r = req.response..statusCode = 200;
        if (req.uri.path == '/join') {
          r.write(jsonEncode({
            'token': 'x' * 32,
            'pack_uuid': lanPackUuid,
            'hub_name': 'fake',
            if (padJoin) 'pad': 'a' * 200000, // 200 KB > 64 KB cap
          }));
        } else {
          r.write('[${'0,' * 3000000}0]'); // ~6 MB of JSON > 4 MB cap
        }
        await r.close();
      });
      await expectLater(
          LanClientSession.join(
              host: '127.0.0.1', port: fake.port, code: '123456'),
          throwsA(isA<LanJoinException>()
              .having((e) => e.code, 'code', LanJoinError.badResponse)));

      padJoin = false;
      final flooded = await LanClientSession.join(
          host: '127.0.0.1',
          port: fake.port,
          code: '123456',
          client: http.Client(),
          machineId: 'm',
          mediaDirFor: (id) async => Directory(p.join(tmp.path, 'cm3')));
      sessions.add(flooded);
      await expectLater(
          flooded.getJson('/groups'),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', kLanBadResponse)));
    });

    test('the machine id is a random UUID made once and kept in settings',
        () async {
      SharedPreferences.setMockInitialValues({});
      final a = await LanClientSession.persistentMachineId();
      final b = await LanClientSession.persistentMachineId();
      expect(a, b);
      expect(
          a,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$')));
      // garbage in the settings is replaced, not trusted
      SharedPreferences.setMockInitialValues(
          {'lan_machine_id_v1': 'not a uuid'});
      final c = await LanClientSession.persistentMachineId();
      expect(c, isNot('not a uuid'));
    });
  });

  group('mode switch', () {
    test('connectivity chip on a LAN client measures the HUB, not the internet',
        () async {
      final s = await connect();
      // A real student PC has no pack. Closing it stops the in-process hub,
      // so a stub answers GET /health on the hub's port (hub up, internet down).
      final port = hub.port!;
      OfflinePackSession.close();
      await eventually(() async => !hub.running);
      final stub = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      stub.listen((r) {
        r.response.statusCode = 200;
        r.response.close();
      });
      addTearDown(() => stub.close(force: true));
      final savedApi = api;
      api = _NoInternetApi();
      addTearDown(() {
        ConnectivityService.instance.dispose();
        api = savedApi;
      });

      await s.activate();
      expect(api, isA<LanClientApi>());
      await ConnectivityService.instance.refresh();
      expect(ConnectivityService.instance.last.tier, isNot(SignalTier.none));

      s.close();
      // Leaving LAN mode: the (unreachable) real client is probed again.
      expect(api, isA<_NoInternetApi>());
      await ConnectivityService.instance.refresh();
      expect(ConnectivityService.instance.last.tier, SignalTier.none);

      await OfflinePackSession.open(
          lanTestPack(), Directory(p.join(tmp.path, 'media_again2')));
    });

    test('activate() swaps the global clients; close() restores them',
        () async {
      final s = await connect();
      // The hub's USB pack and a LAN client cannot be open together; a real
      // student PC has no pack. Simulate that PC.
      await hub.stop();
      OfflinePackSession.close();
      final restoredApi = api;
      final restoredDiag = diagnosticKioskApi;

      await s.activate();
      expect(api, isA<LanClientApi>());
      expect(diagnosticKioskApi, isNot(same(restoredDiag)));
      expect(TestCache.isMemoryMode, isTrue);
      expect(OfflineMedia.root, isNotNull);
      expect(LanClientSession.isActive, isTrue);

      s.close();
      expect(identical(api, restoredApi), isTrue);
      expect(identical(diagnosticKioskApi, restoredDiag), isTrue);
      expect(TestCache.isMemoryMode, isFalse);
      expect(OfflineMedia.root, isNull);
      expect(LanClientSession.isActive, isFalse);

      // Re-open a pack so tearDown has something to close.
      await OfflinePackSession.open(
          lanTestPack(), Directory(p.join(tmp.path, 'media_again')));
    });
  });
}
