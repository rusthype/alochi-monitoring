// The real DiagnosticTestRunnerScreen on a USB pack (no overrides): both
// subjects are answered A-D, each lands as ONE `diag:...` chain entry, the
// app ends on the finished route, and nothing is queued for the real server,
// recorded in the plain-disk history DB, or sent through the parked api.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/diagnostic_history_db.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_test_runner_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _school = '00000000-0000-4000-8000-0000000000b2';
const _g1 = '00000000-0000-4000-8000-0000000000c1';
const _s1 = '00000000-0000-4000-8000-0000000000d1';
const _packUuid = '00000000-0000-4000-8000-0000000000a1';
const _sha = '4161eccd30d857ca5633b1fe7fc1bd5762c6adf526cd3ad54e25421ea2457ee9';

Map<String, dynamic> _diag(String subject) => {
      'type': 'diagnostic',
      'key': 'diag:$subject:g5:uz:v1',
      'catalog': {},
      'data': {
        'questions': [
          {
            'id': '$subject-q1',
            'topic': 't',
            'level': 1,
            'question_text': '$subject one',
            'options': ['oa', 'ob', 'oc', 'od'],
            'image': 'media/$_sha.jpg',
            'svg_visual': '',
          },
          {
            'id': '$subject-q2',
            'topic': 't',
            'level': 1,
            'question_text': '$subject two',
            'options': ['oa', 'ob', 'oc', 'od'],
            'image': '',
            'svg_visual': '',
          },
        ]
      },
    };

LoadedPack _pack() => LoadedPack(
      manifest: PackManifest(
        formatVersion: 1,
        packUuid: _packUuid,
        schoolId: _school,
        schoolCode: '999',
        createdAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2099, 1, 1),
        kdfIter: 1,
        kdfSalt: Uint8List(16),
        files: const {},
      ),
      tests: [_diag('math'), _diag('english')],
      groups: [
        {'id': _g1, 'name': '5-A', 'grade': 5},
      ],
      students: [
        {'id': _s1, 'code': 'A-0001', 'name': 'Valiyev Ali', 'group_id': _g1},
      ],
      chainKey: Uint8List.fromList(List.generate(32, (i) => 100 + i)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('runner on a pack: two chain entries, nothing queued/leaked',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationSupportDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return Directory.systemTemp.path;
      }
      throw PlatformException(code: 'unimplemented');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    late Directory tmp;
    late DiagnosticKioskApi parked;
    var finishedExtra = false;
    final router = GoRouter(
      initialLocation: '/runner',
      routes: [
        GoRoute(
            path: '/runner',
            builder: (_, __) => const DiagnosticTestRunnerScreen(
                  attemptId: 'offline|$_s1|$_g1|uz',
                  studentName: 'Valiyev Ali',
                  grade: 5,
                  language: 'uz',
                  schoolCode: '999',
                )),
        GoRoute(
            path: '/diagnostic_finished',
            builder: (_, __) {
              finishedExtra = true;
              return const SizedBox(key: Key('finished'));
            }),
      ],
    );

    Future<void> settle() async {
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    Future<void> answerSubject(
        AppLocalizations l10n, List<String> picks) async {
      for (var n = 0; n < picks.length; n++) {
        await tester.tap(find.text(picks[n]).first);
        await settle(); // auto-advance (500ms) to the next question
      }
      final next = find.text(l10n.nextSubjectButton);
      await tester.tap(
          next.evaluate().isNotEmpty ? next : find.text(l10n.finishTestButton));
      await settle();
    }

    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmp = Directory.systemTemp.createTempSync('offline_diag_runner_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      await DiagnosticAnswerStore.openInMemory();
      await DiagnosticHistoryDb.openInMemory();
      parked = diagnosticKioskApi;
      await OfflinePackSession.open(
          _pack(), Directory(p.join(tmp.path, 'media')));

      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(
          locale: const Locale('uz'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await settle();
      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticTestRunnerScreen)))!;

      expect(find.text('math one'), findsOneWidget);
      await answerSubject(l10n, ['od', 'oa']); // math: D, A
      // the 1.5s subject transition runs on a real timer
      for (var i = 0;
          i < 40 && find.text('english one').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(find.text('english one'), findsOneWidget);
      await answerSubject(l10n, ['oc', 'ob']); // english: C, B
      await settle();

      expect(finishedExtra, isTrue,
          reason: 'should end on /diagnostic_finished');

      final rows = await PackResultsDb.rowsForPack(_packUuid);
      final payloads =
          rows.map((r) => jsonDecode(r.payloadJson) as Map).toList();
      expect(payloads.map((e) => e['test_key']),
          ['diag:math:g5:uz:v1', 'diag:english:g5:uz:v1']);
      expect(payloads[0]['answers'], [
        {'q': 'math-q1', 'a': 'D'},
        {'q': 'math-q2', 'a': 'A'},
      ]);
      expect(payloads[1]['answers'], [
        {'q': 'english-q1', 'a': 'C'},
        {'q': 'english-q2', 'a': 'B'},
      ]);
      // nothing queued for the real server, no plain-disk history, no
      // unsynced autosave rows left to be re-sent online later
      expect(await OfflineQueue.totalPendingCount(), 0);
      expect(await DiagnosticHistoryDb.getAll(), isEmpty);
      expect(await DiagnosticAnswerStore.attemptsWithPending(), isEmpty);
    });

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      OfflinePackSession.close();
      expect(identical(diagnosticKioskApi, parked), isTrue);
      await DiagnosticAnswerStore.reset();
      await DiagnosticHistoryDb.reset();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });
  });
}
