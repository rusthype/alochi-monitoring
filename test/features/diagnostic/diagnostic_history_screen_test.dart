import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_history_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
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

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('uz'),
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
      },
    )));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
        tester.element(find.byType(DiagnosticHistoryScreen)))!;
    await tester.tap(find.text(l10n.diagnosticHistorySendAll));
    await tester.pumpAndSettle();

    expect(flushCalls, equals(1));
  });
}
