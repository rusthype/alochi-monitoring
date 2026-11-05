import 'dart:convert';

import 'package:alochi_monitoring/core/services/diagnostic_export_service.dart';
import 'package:alochi_monitoring/core/sync/sync_service.dart';
import 'package:archive/archive.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_pin_verifier.dart';
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
  testWidgets('a failing history load shows the error + retry, not a spinner',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
      getAllOverride: () async {
        calls++;
        if (calls == 1) throw StateError('db locked');
        return _fixture;
      },
    )));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticHistoryScreen)))!;
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(l10n.loadFailed), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text('Aliyev Ali'), findsOneWidget);
    expect(find.text(l10n.loadFailed), findsNothing);
  });

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
    Map<String, dynamic> hrow(String id, String name, String school,
            {String? schoolId, String status = 'sent'}) =>
        {
          'attempt_id': id,
          'student_name': name,
          'class_label': '4-A',
          'school': school,
          'school_id': schoolId,
          'math_score': 10,
          'english_score': 20,
          'status': status,
          'date_taken': 1000,
        };
    final cachedSchools = <Map<String, dynamic>>[
      {'school_id': 'A', 'school_name': '56-maktab', 'school_number': '56', 'kiosk_pin': '1111'},
      {'school_id': 'B', 'school_name': '12-maktab', 'school_number': '12', 'kiosk_pin': ''},
      {'school_id': 'C', 'school_name': '7-maktab', 'school_number': '7', 'kiosk_pin': '2222'},
    ];
    final aRow = hrow('a1', 'Alpha Student', '56-maktab', schoolId: 'A');
    final aPending =
        hrow('a2', 'Alpha Pending', '56-maktab', schoolId: 'A', status: 'pending');
    final bRow = hrow('b1', 'Bravo Student', '12-maktab', schoolId: 'B');
    final cRow = hrow('c1', 'Charlie Student', '7-maktab', schoolId: 'C');
    final oldA = hrow('o1', 'Old Alpha', ' 56-MAKTAB');
    final lost = hrow('u1', 'Lost Student', 'Noma\'lum maktab');

    late List<Map<String, dynamic>>? exported;
    late List<Map<String, String>> verified;
    var verdict = DiagnosticPinResult.ok;

    Future<AppLocalizations> pump(
      WidgetTester tester,
      List<Map<String, dynamic>> rows, {
      Future<String> Function(List<Map<String, dynamic>>, {void Function(int)? onProgress})? export,
    }) async {
      exported = null;
      verified = [];
      verdict = DiagnosticPinResult.ok;
      await tester.pumpWidget(_wrap(DiagnosticHistoryScreen(
        getAllOverride: () async => rows,
        loadSchoolsOverride: () async => cachedSchools,
        verifyPinOverride: ({required schoolId, required pin, legacyPin = ''}) async {
          verified.add({'id': schoolId, 'pin': pin, 'legacy': legacyPin});
          return verdict;
        },
        exportToZipOverride: export ??
            (records, {onProgress}) async {
              exported = records;
              return '/tmp/alochi_diagnostika_test.zip';
            },
      )));
      await tester.pumpAndSettle();
      return AppLocalizations.of(
          tester.element(find.byType(DiagnosticHistoryScreen)))!;
    }

    Future<void> tapExport(WidgetTester tester, AppLocalizations l10n) async {
      await tester.tap(find.text(l10n.diagnosticExportZipButton));
      await tester.pumpAndSettle();
    }

    Future<void> typePin(
        WidgetTester tester, AppLocalizations l10n, String pin) async {
      await tester.enterText(find.byType(TextField), pin);
      await tester.tap(find.text(l10n.confirmBtn));
      await tester.pumpAndSettle();
    }

    testWidgets('export button is disabled when the filtered list is empty',
        (tester) async {
      final l10n = await pump(tester, const []);
      final button = tester.widget<OutlinedButton>(find.ancestor(
        of: find.text(l10n.diagnosticExportZipButton),
        matching: find.byType(OutlinedButton),
      ));
      expect(button.onPressed, isNull);
    });

    testWidgets(
        'one school: no chooser, PIN is verified for THAT school and only its '
        'rows are exported', (tester) async {
      final l10n = await pump(tester, [aRow, oldA]);
      await tapExport(tester, l10n);
      expect(find.text(l10n.selectSchool), findsNothing);
      expect(find.byType(TextField), findsOneWidget);

      await typePin(tester, l10n, '1111');
      expect(verified, [
        {'id': 'A', 'pin': '1111', 'legacy': '1111'}
      ]);
      expect(exported!.map((r) => r['attempt_id']), ['a1', 'o1']);
      expect(find.text(l10n.diagnosticExportSuccess), findsOneWidget);
    });

    testWidgets('a wrong PIN blocks the export', (tester) async {
      final l10n = await pump(tester, [aRow]);
      verdict = DiagnosticPinResult.wrong;
      await tapExport(tester, l10n);
      await typePin(tester, l10n, '0000');
      expect(exported, isNull);
      expect(find.text(l10n.incorrectPin), findsOneWidget);
    });

    testWidgets(
        'two schools: chooser; school A export has no school B row in the '
        'zip/html, and the verifier only ever sees A\'s id', (tester) async {
      AppLocalizations? l;
      late List<String> zipEntries;
      late String zipHtml;
      final l10n = await pump(tester, [aRow, bRow, cRow, oldA],
          export: (records, {onProgress}) async {
        exported = records;
        final bytes = DiagnosticExportService.buildZipBytes(records, l10n: l!);
        final archive = ZipDecoder().decodeBytes(bytes);
        zipEntries = archive.files.map((f) => f.name).toList();
        zipHtml = archive.files
            .map((f) => utf8.decode(f.content as List<int>))
            .join('\n');
        return '/tmp/x.zip';
      });
      l = l10n;
      await tapExport(tester, l10n);
      expect(find.text(l10n.selectSchool), findsOneWidget);
      expect(find.text('56-maktab'), findsOneWidget);
      expect(find.text('12-maktab'), findsOneWidget);

      await tester.tap(find.text('56-maktab'));
      await tester.pumpAndSettle();
      await typePin(tester, l10n, '1111');

      expect(verified.map((v) => v['id']), ['A']);
      expect(exported!.map((r) => r['attempt_id']), ['a1', 'o1']);
      expect(zipEntries, hasLength(2));
      expect(zipHtml, contains('Alpha Student'));
      expect(zipHtml, contains('Old Alpha'));
      expect(zipHtml, isNot(contains('Bravo')));
      expect(zipHtml, isNot(contains('Charlie')));
    });

    testWidgets('the PIN of school A cannot unlock school C', (tester) async {
      final l10n = await pump(tester, [aRow, cRow]);
      // Only C's PIN ('2222') is valid; A's '1111' is a different school's.
      await tapExport(tester, l10n);
      await tester.tap(find.text('7-maktab'));
      await tester.pumpAndSettle();
      verdict = DiagnosticPinResult.wrong;
      await typePin(tester, l10n, '1111');
      expect(verified, [
        {'id': 'C', 'pin': '1111', 'legacy': '2222'}
      ]);
      expect(exported, isNull);
    });

    testWidgets('a school without a PIN exports without any PIN dialog',
        (tester) async {
      final l10n = await pump(tester, [aRow, bRow]);
      await tapExport(tester, l10n);
      await tester.tap(find.text('12-maktab'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(verified, isEmpty);
      expect(exported!.map((r) => r['attempt_id']), ['b1']);
    });

    testWidgets(
        'rows whose school cannot be resolved are listed but not exportable',
        (tester) async {
      final l10n = await pump(tester, [aRow, lost]);
      await tapExport(tester, l10n);
      // Chooser appears even with one resolvable school so the operator sees why.
      expect(find.text(l10n.selectSchool), findsOneWidget);
      expect(find.text(l10n.diagnosticExportUnresolvedTitle(1)), findsOneWidget);
      expect(find.text(l10n.diagnosticExportUnresolvedHint), findsOneWidget);

      await tester.tap(find.text(l10n.diagnosticExportUnresolvedTitle(1)));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectSchool), findsOneWidget, reason: 'disabled');
      expect(exported, isNull);

      await tester.tap(find.text('56-maktab'));
      await tester.pumpAndSettle();
      await typePin(tester, l10n, '1111');
      expect(exported!.map((r) => r['attempt_id']), ['a1']);
    });

    testWidgets('only unresolved rows: nothing can be exported', (tester) async {
      final l10n = await pump(tester, [lost]);
      await tapExport(tester, l10n);
      expect(find.text(l10n.diagnosticExportUnresolvedTitle(1)), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(exported, isNull);
      expect(verified, isEmpty);
    });

    testWidgets('respects the currently selected filter chip when exporting',
        (tester) async {
      final l10n = await pump(tester, [aRow, aPending]);
      await tester.ensureVisible(find.text(l10n.diagnosticHistoryFilterPending));
      await tester.tap(find.text(l10n.diagnosticHistoryFilterPending));
      await tester.pumpAndSettle();
      await tapExport(tester, l10n);
      await typePin(tester, l10n, '1111');
      expect(exported!.map((r) => r['attempt_id']), ['a2']);
    });

    testWidgets('a failed export shows the error snackbar, not a fake success',
        (tester) async {
      final l10n = await pump(tester, [aRow],
          export: (records, {onProgress}) async => throw Exception('disk full'));
      await tapExport(tester, l10n);
      await typePin(tester, l10n, '1111');
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
