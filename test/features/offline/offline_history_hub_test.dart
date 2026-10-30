import 'package:alochi_monitoring/features/local_test/history_screen.dart';
import 'package:alochi_monitoring/features/offline/offline_history_hub_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _rows = <Map<String, dynamic>>[
  {
    'first_name': 'Ali',
    'last_name': 'Valiyev',
    'school': '39',
    'grade_group': '3-A',
    'date_taken': 1000,
    'total_pct': 75.0,
    'math_score': 7,
    'eng_score': 8,
  },
];

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Widget _hub(
        {Future<void> Function()? clear, List<Map<String, dynamic>>? rows}) =>
    _wrap(OfflineHistoryHubScreen(
      generalTab: HistoryScreen(
        embedded: true,
        getHistoryOverride: () async => rows ?? _rows,
        clearOverride: clear,
      ),
      diagnosticTab: const Center(child: Text('DIAG-BODY')),
    ));

void main() {
  testWidgets('pill tab switcher swaps tab bodies', (tester) async {
    await tester.pumpWidget(_hub());
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    expect(find.text('Ali Valiyev'), findsOneWidget);
    expect(find.text('DIAG-BODY'), findsNothing);

    await tester.tap(find.text(l10n.offlineHistoryTabDiagnostic));
    await tester.pumpAndSettle();
    expect(find.text('DIAG-BODY'), findsOneWidget);

    await tester.tap(find.text(l10n.offlineHistoryTabGeneral));
    await tester.pumpAndSettle();
    expect(find.text('Ali Valiyev'), findsOneWidget);
  });

  testWidgets('card shows localized tags and scores', (tester) async {
    await tester.pumpWidget(_hub());
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    expect(find.text('75%'), findsOneWidget);
    expect(find.text('${l10n.schoolLabel}: 39'), findsOneWidget);
    expect(find.text('${l10n.groupGradeLabel}: 3-A'), findsOneWidget);
    expect(find.text('${l10n.mathShort}: 7'), findsOneWidget);
    expect(find.text('${l10n.engShort}: 8'), findsOneWidget);
  });

  testWidgets('clear action has tooltip, confirms, then clears',
      (tester) async {
    var cleared = false;
    await tester.pumpWidget(_hub(clear: () async => cleared = true));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    expect(find.byTooltip(l10n.clearHistoryTitle), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.clearHistoryTitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.clearHistoryConfirm), findsOneWidget);

    await tester.tap(find.text(l10n.yesDelete));
    await tester.pumpAndSettle();
    expect(cleared, isTrue);
  });

  testWidgets('empty list shows rounded empty state without clear action',
      (tester) async {
    await tester.pumpWidget(_hub(rows: const []));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    expect(find.text(l10n.noHistoryYet), findsOneWidget);
    expect(find.byTooltip(l10n.clearHistoryTitle), findsNothing);
  });
}
