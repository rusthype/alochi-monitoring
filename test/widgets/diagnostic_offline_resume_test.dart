// Offline-resume tests for DiagnosticTestRunnerScreen's fixed-variant local
// persistence (AttemptStore-backed) — kept in their OWN file, separate from
// diagnostic_test_runner_test.dart, because they are the only tests that
// exercise AttemptStore's real crypto/plugin path, which needs its own
// path_provider mocking (see `mockAppSupportDirectoryFor`) and `runAsync`
// wrapping; sharing a file/isolate with the ~30 other runner tests risks
// cross-test pollution of the AlochiImageCacheManager singleton's on-disk
// setup (empirically caused a hang when combined in one file/isolate).
import 'dart:io';

import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_test_runner_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

Map<String, dynamic> _question({
  required String id,
  required String text,
}) {
  return {
    'question_id': id,
    'question_text': text,
    'option_a': 'Variant A',
    'option_b': 'Variant B',
    'option_c': 'Variant C',
    'option_d': 'Variant D',
    'image_url': '',
    'svg_visual': '',
  };
}

Map<String, dynamic> _withMeta(
  Map<String, dynamic> resp, {
  bool isFixedVariant = false,
}) {
  return {...resp, 'is_fixed_variant': isFixedVariant};
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('uz'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// AttemptStore's crypto (QueueCrypto) tries the OS keychain first, then
  /// falls back to a key file via path_provider (queue_crypto.dart).
  /// Directly `await`-ing that call from a `testWidgets` body hangs instead
  /// of throwing MissingPluginException the way a plain `test()` does
  /// (verified empirically) — mocking `getApplicationSupportDirectory` lets
  /// the fallback key succeed. `getTemporaryDirectory` is also mocked
  /// because `_prefetchImages`'s AlochiImageCacheManager touches it on
  /// first use for its own on-disk bookkeeping, even with zero image URLs
  /// to fetch. Every OTHER test/screen in this app still gets the real
  /// MissingPluginException for these plugins, since this mock only exists
  /// in this dedicated file.
  void mockAppSupportDirectoryFor(WidgetTester tester) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory' ||
          call.method == 'getTemporaryDirectory') {
        return Directory.systemTemp.path;
      }
      throw PlatformException(code: 'unimplemented');
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(_pathProviderChannel, null));
  }

  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  group(
      'DiagnosticTestRunnerScreen offline resume '
      '(fixed-variant local persistence)', () {
    List<Map<String, dynamic>> pkg(int count) => [
          for (var i = 1; i <= count; i++)
            _question(id: 'q$i', text: 'Savol $i')
        ];

    testWidgets(
        'restores the saved package/answers/position with NO network call '
        'when a matching attempt is saved', (tester) async {
      mockAppSupportDirectoryFor(tester);
      var availableSubjectsCalls = 0;
      var startAttemptCalls = 0;
      // The seed save + the widget's own restore-load both touch
      // AttemptStore's crypto — see `mockAppSupportDirectoryFor`'s doc
      // comment — so the whole exchange runs inside runAsync.
      await tester.runAsync(() async {
        await AttemptStore.save('diag_att-resume', {
          'all_subjects': ['math'],
          'subjects_completed': <String>[],
          'current_subject': 'math',
          'is_fixed_variant': true,
          'questions': pkg(3),
          'answers': {'1': 'B'},
          'position': 2,
          'total': 3,
          'deadline_epoch_ms': DateTime.now()
              .add(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        });

        await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
          attemptId: 'att-resume',
          studentName: 'Aliyev Ali',
          grade: 3,
          language: 'uz',
          availableSubjectsOverride: (grade, {String language = 'uz'}) async {
            availableSubjectsCalls++;
            return {
              'subjects': ['math']
            };
          },
          startAttemptOverride: ({required attemptId, required subject}) async {
            startAttemptCalls++;
            throw StateError('must not hit the network on a valid resume');
          },
        )));
        await tester.pumpAndSettle();
      });

      expect(availableSubjectsCalls, 0);
      expect(startAttemptCalls, 0);
      expect(find.text('2-savol'), findsOneWidget);
      expect(find.textContaining('04:5'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets(
        'falls back to a live bootstrap when the saved deadline already '
        'passed', (tester) async {
      mockAppSupportDirectoryFor(tester);
      var startAttemptCalls = 0;
      await tester.runAsync(() async {
        await AttemptStore.save('diag_att-expired', {
          'all_subjects': ['math'],
          'subjects_completed': <String>[],
          'current_subject': 'math',
          'is_fixed_variant': true,
          'questions': pkg(2),
          'answers': {'1': 'A'},
          'position': 1,
          'total': 2,
          'deadline_epoch_ms': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        });

        await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
          attemptId: 'att-expired',
          studentName: 'Aliyev Ali',
          grade: 3,
          language: 'uz',
          availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
              {
            'subjects': ['math']
          },
          startAttemptOverride: ({required attemptId, required subject}) async {
            startAttemptCalls++;
            return _withMeta({
              'position': 1,
              'total_questions': 2,
              'subject': subject,
              'questions': pkg(2),
            }, isFixedVariant: true);
          },
        )));
        await tester.pumpAndSettle();
      });

      expect(startAttemptCalls, 1);
      await unmount(tester);
    });

    // KNOWN FOLLOW-UP: this still asserts against the now-legacy
    // AttemptStore blob's 'answers' field, which Task 10 intentionally
    // stopped writing (answers now live in DiagnosticAnswerStore instead —
    // see diagnostic_test_runner_screen.dart's _saveProgressIfFixed). Real
    // coverage for the new behavior lives in diagnostic_answer_store_test.dart
    // (Task 7, unit-level) and diagnostic_test_runner_test.dart's own new
    // tests (Task 10, widget-level). Pointing THIS test at DiagnosticAnswerStore
    // instead was attempted but requires real sqflite/isolate work in this
    // file, which this file's own header comment already documents as
    // empirically causing a hang when combined with its other real
    // plugin/isolate work — needs either deleting this assertion or a
    // different verification approach, not a plain ffi-init addition.
    testWidgets('picking an option persists progress for a later resume',
        (tester) async {
      mockAppSupportDirectoryFor(tester);
      Map<String, dynamic>? saved;
      await tester.runAsync(() async {
        await tester.pumpWidget(_wrap(DiagnosticTestRunnerScreen(
          attemptId: 'att-save',
          studentName: 'Aliyev Ali',
          grade: 3,
          language: 'uz',
          availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
              {
            'subjects': ['math']
          },
          startAttemptOverride: ({required attemptId, required subject}) async {
            return _withMeta({
              'position': 1,
              'total_questions': 2,
              'subject': subject,
              'questions': pkg(2),
            }, isFixedVariant: true);
          },
        )));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Variant A'));
        await tester.pump();
        // _saveProgressIfFixed is fire-and-forget (unawaited) from the
        // screen's own option-select handler — pumpAndSettle alone won't
        // wait for that background write, so give its microtasks a beat.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        saved = await AttemptStore.load('diag_att-save');
      });

      expect(saved, isNotNull);
      expect(saved!['answers'], {'1': 'A'});
      expect(saved!['current_subject'], 'math');
      await unmount(tester);
    });
  });
}
