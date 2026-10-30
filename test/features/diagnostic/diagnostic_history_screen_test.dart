import 'package:alochi_monitoring/core/sync/sync_service.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_history_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

final _fixture = <Map<String, dynamic>>[
  {
    'attempt_id': 'a1',
    'student_name': 'Aliyev Ali',
    'class_label': '4-A',
    'school': '56-maktab',
    'math_score': 90,
    'english_score': null,
    'status': 'sent',
    'date_taken': 1000,
  },
  {
    'attempt_id': 'a2',
    'student_name': 'Valiyeva Vali',
    'class_label': '5-B',
    'school': '12-maktab',
    'math_score': null,
    'english_score': null,
    'status': 'pending',
    'date_taken': 2000,
  },
];

Widget _wrap(Widget child, {Locale locale = const Locale('uz')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('shows every record under the "all" filter by default',
      (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
      getAllOverride: () async => _fixture,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Aliyev Ali'), findsOneWidget);
    expect(find.text('Valiyeva Vali'), findsOneWidget);
  });

  testWidgets('tapping the "sent" chip filters out pending rows',
      (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
      getAllOverride: () async => _fixture,
    )));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticHistoryScreen)))!;
    // Test font (Ahem) is much wider than real fonts, so the button labels
    // squeeze the scrollable chip list — scroll the chip into view first.
    await tester.ensureVisible(find.text(l10n.diagnosticHistoryFilterSent));
    await tester.tap(find.text(l10n.diagnosticHistoryFilterSent));
    await tester.pumpAndSettle();

    expect(find.text('Aliyev Ali'), findsOneWidget);
    expect(find.text('Valiyeva Vali'), findsNothing);
  });

  testWidgets('tapping the "pending" chip filters out sent rows',
      (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
      getAllOverride: () async => _fixture,
    )));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticHistoryScreen)))!;
    // The "Kutilmoqda" chip is the 3rd/last one in a horizontally scrolling
    // filter row and can sit just outside the default test viewport —
    // scroll it into view before tapping (its center coordinate otherwise
    // misses and lands on a sibling widget).
    await tester.ensureVisible(find.text(l10n.diagnosticHistoryFilterPending));
    await tester.tap(find.text(l10n.diagnosticHistoryFilterPending));
    await tester.pumpAndSettle();

    expect(find.text('Aliyev Ali'), findsNothing);
    expect(find.text('Valiyeva Vali'), findsOneWidget);
  });

  testWidgets('switching back to "all" restores every record', (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
      getAllOverride: () async => _fixture,
    )));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticHistoryScreen)))!;
    await tester.ensureVisible(find.text(l10n.diagnosticHistoryFilterPending));
    await tester.tap(find.text(l10n.diagnosticHistoryFilterPending));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.diagnosticHistoryFilterAll));
    await tester.tap(find.text(l10n.diagnosticHistoryFilterAll));
    await tester.pumpAndSettle();

    expect(find.text('Aliyev Ali'), findsOneWidget);
    expect(find.text('Valiyeva Vali'), findsOneWidget);
  });

  testWidgets('empty fixture shows the empty-state text, not a crash',
      (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
      getAllOverride: () async => const [],
    )));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticHistoryScreen)))!;
    expect(find.text(l10n.diagnosticHistoryNoRecords), findsOneWidget);
  });

  testWidgets(
      'tapping "Barchasini yuborish" calls the flush override and reloads',
      (tester) async {
    var flushCalls = 0;
    await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
      getAllOverride: () async => _fixture,
      flushNowOverride: () async {
        flushCalls++;
        return SyncFlushOutcome.success;
      },
    )));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticHistoryScreen)))!;
    await tester.tap(find.text(l10n.diagnosticHistorySendAll));
    await tester.pumpAndSettle();

    expect(flushCalls, equals(1));
  });

  // Regression coverage for the real bug: "otpravitni bossam serverga
  // ketganmi ketmaganmi bilib bo'lmayapti" — the button gave zero feedback
  // either way. These pin down that the screen now shows a SnackBar that
  // actually reflects what happened, not just "I called flush".

  testWidgets(
      'shows a success snackbar when the flush actually clears a pending row',
      (tester) async {
    var sent = false;
    await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
      getAllOverride: () async => sent
          ? _fixture
              .map((r) =>
                  r['attempt_id'] == 'a2' ? {...r, 'status': 'sent'} : r)
              .toList()
          : _fixture,
      flushNowOverride: () async {
        sent = true;
        return SyncFlushOutcome.success;
      },
    )));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticHistoryScreen)))!;
    await tester.tap(find.text(l10n.diagnosticHistorySendAll));
    await tester.pumpAndSettle();

    expect(find.text(l10n.diagnosticHistorySendSuccess), findsOneWidget);
  });

  testWidgets('shows a no-network snackbar without pretending it worked',
      (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
      getAllOverride: () async => _fixture,
      flushNowOverride: () async => SyncFlushOutcome.noNetwork,
    )));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticHistoryScreen)))!;
    await tester.tap(find.text(l10n.diagnosticHistorySendAll));
    await tester.pumpAndSettle();

    expect(find.text(l10n.diagnosticHistorySendNoNetwork), findsOneWidget);
  });

  testWidgets(
      'shows an error snackbar when the outcome says success but no row actually cleared',
      (tester) async {
    await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
      getAllOverride: () async => _fixture,
      flushNowOverride: () async => SyncFlushOutcome.success,
    )));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticHistoryScreen)))!;
    await tester.tap(find.text(l10n.diagnosticHistorySendAll));
    await tester.pumpAndSettle();

    expect(find.text(l10n.diagnosticHistorySendError), findsOneWidget);
  });

  group('ZIP export', () {
    testWidgets('export button is disabled when the filtered list is empty',
        (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
        getAllOverride: () async => const [],
      )));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticHistoryScreen)))!;
      final button = tester.widget<OutlinedButton>(find.ancestor(
        of: find.text(l10n.diagnosticExportZipButton),
        matching: find.byType(OutlinedButton),
      ));
      expect(button.onPressed, isNull);
    });

    testWidgets(
        'entering the correct PIN calls exportToZipOverride with the filtered records',
        (tester) async {
      List<Map<String, dynamic>>? exported;
      await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
        getAllOverride: () async => _fixture,
        exportToZipOverride: (records, {onProgress}) async {
          exported = records;
          onProgress?.call(records.length);
          return '/tmp/alochi_diagnostika_test.zip';
        },
      )));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticHistoryScreen)))!;
      await tester.tap(find.text(l10n.diagnosticExportZipButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '0555');
      await tester.tap(find.text(l10n.confirmBtn));
      await tester.pumpAndSettle();

      expect(exported, isNotNull);
      expect(exported!.length, equals(_fixture.length));
      expect(find.text(l10n.diagnosticExportSuccess), findsOneWidget);
    });

    testWidgets('wrong PIN never triggers the export override', (tester) async {
      var exportCalls = 0;
      await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
        getAllOverride: () async => _fixture,
        exportToZipOverride: (records, {onProgress}) async {
          exportCalls++;
          return '/tmp/x.zip';
        },
      )));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticHistoryScreen)))!;
      await tester.tap(find.text(l10n.diagnosticExportZipButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1111');
      await tester.tap(find.text(l10n.confirmBtn));
      await tester.pumpAndSettle();

      expect(exportCalls, equals(0));
    });

    testWidgets('respects the currently selected filter chip when exporting',
        (tester) async {
      List<Map<String, dynamic>>? exported;
      await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
        getAllOverride: () async => _fixture,
        exportToZipOverride: (records, {onProgress}) async {
          exported = records;
          return '/tmp/x.zip';
        },
      )));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticHistoryScreen)))!;
      await tester.ensureVisible(find.text(l10n.diagnosticHistoryFilterPending));
      await tester.tap(find.text(l10n.diagnosticHistoryFilterPending));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.diagnosticExportZipButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0555');
      await tester.tap(find.text(l10n.confirmBtn));
      await tester.pumpAndSettle();

      expect(exported!.length, equals(1));
      expect(exported!.first['student_name'], equals('Valiyeva Vali'));
    });

    testWidgets('a failed export shows the error snackbar, not a fake success',
        (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
        getAllOverride: () async => _fixture,
        exportToZipOverride: (records, {onProgress}) async {
          throw Exception('disk full');
        },
      )));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
          tester.element(find.byType(DiagnosticHistoryScreen)))!;
      await tester.tap(find.text(l10n.diagnosticExportZipButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0555');
      await tester.tap(find.text(l10n.confirmBtn));
      await tester.pumpAndSettle();

      expect(find.text(l10n.diagnosticExportError), findsOneWidget);
    });
  });

  group('filter-row action buttons', () {
    for (final lang in ['uz', 'ru']) {
      testWidgets('full export + send-all labels at 1200px ($lang)',
          (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(
            DiagnosticHistoryScreen(getAllOverride: () async => _fixture),
            locale: Locale(lang)));
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
            tester.element(find.byType(DiagnosticHistoryScreen)))!;
        for (final label in [
          l10n.diagnosticExportZipButton,
          l10n.diagnosticHistorySendAll,
        ]) {
          final para = tester.renderObject<RenderParagraph>(find.text(label));
          expect(para.size.width,
              greaterThanOrEqualTo(para.getMaxIntrinsicWidth(double.infinity)),
              reason: '"$label" is truncated');
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('500px width pumps without overflow (ru)', (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(
          DiagnosticHistoryScreen(getAllOverride: () async => _fixture),
          locale: const Locale('ru')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
