// Audit E-07 / A2: when OfflineQueue.enqueueLocal fails, the host must NOT
// clear the completed attempt and must NOT show the thank-you/result screen
// as if saved: it shows the in-place retry state, and a retry that succeeds
// queues the result exactly once and then clears the attempt.

import 'dart:io';

import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/features/test/engine_host_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _testKey = 'host_enqueue_fail_v1';
const _student = 'S-HOST';

Map<String, dynamic> _blob({Object? grade = 5}) => {
      'test_key': _testKey,
      'title': 'Host Test',
      'grade': grade,
      'version': 1,
      'parts': ['Math'],
      'variants': {
        '1': {
          'Math': [
            {
              'type': 'text_choice',
              'q': 'Q1',
              'opts': ['Alpha', 'Beta'],
              'ans': 0,
            },
          ],
        },
      },
    };

Widget _host(Map<String, dynamic> blob) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: EngineHostScreen(
        testData: blob,
        variant: 1,
        firstName: 'Ism',
        lastName: 'Familiya',
        school: '56',
        studentId: _student,
        duration: const Duration(minutes: 5),
      ),
    );

/// Chains of real-IO futures (sqlite isolate, prefs) need several
/// real-wait / pump hops to unwind inside the widget-test FakeAsync zone.
Future<void> _io(WidgetTester tester, {int ms = 300}) async {
  for (var i = 0; i < (ms ~/ 100).clamp(1, 12); i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    await QueueCrypto.encryptPayload('{}');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('host_enqueue_');
    // HistoryDb (local history row) resolves its folder through path_provider.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tmp.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('enqueue failure keeps the attempt and offers a retry',
      (tester) async {
    await tester.runAsync(() async {
      await OfflineQueue.openAtPath(p.join(tmp.path, 'a.db'));
      await (await OfflineQueue.db).close(); // every insert now throws
    });

    await tester.pumpWidget(_host(_blob()));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    await tester.tap(find.text('Alpha'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.widgetWithText(ElevatedButton, l10n.finish));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, l10n.finish),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await _io(tester, ms: 600);

    // Honest failure state with a retry - not a result / thank-you screen.
    expect(find.text(l10n.resultNotSavedError), findsOneWidget);
    expect(find.widgetWithText(FilledButton, l10n.retry), findsOneWidget);
    // The completed attempt is still on disk.
    final kept = await tester.runAsync(() => AttemptStore.load(_testKey));
    expect(kept, isNotNull);
    expect(kept!['completed'], isTrue);

    // Storage recovers; retry queues exactly one row and clears the attempt.
    await tester
        .runAsync(() => OfflineQueue.openAtPath(p.join(tmp.path, 'b.db')));
    await tester.tap(find.widgetWithText(FilledButton, l10n.retry));
    await tester.pump(const Duration(milliseconds: 100));
    await _io(tester, ms: 600);

    final rows = await tester.runAsync(() async {
      final d = await OfflineQueue.db;
      return (await d.query('local_queue')).length;
    });
    expect(rows, 1);
    expect(await tester.runAsync(() => AttemptStore.load(_testKey)), isNull);
    expect(find.text(l10n.resultNotSavedError), findsNothing);

    // Tear the result screen down inside the test so its timers are gone
    // before the framework checks for pending ones.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 70));
  });

  testWidgets('a malformed test shows the fixed message, never exception text',
      (tester) async {
    // `variants` is the wrong type -> spec has no variants -> data-empty path;
    // and a hostile `test_data` wrapper must not leak its toString either.
    await tester.pumpWidget(_host({'test_data': 'not-a-map', 'variants': 5}));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('type '), findsNothing);
    expect(
        find.textContaining(RegExp(
            '${RegExp.escape(l10n.testDataEmptyMsg)}|${RegExp.escape(l10n.testLoadFailed)}')),
        findsOneWidget);
  });
}
