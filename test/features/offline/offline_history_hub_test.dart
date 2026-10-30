import 'package:alochi_monitoring/features/local_test/history_screen.dart';
import 'package:alochi_monitoring/features/offline/offline_history_hub_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
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
  trackpadTests();
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

// Hub pushed on top of a base route (so there is something to pop back to),
// on macOS where the default page transition is Cupertino (back-swipe).
Future<void> _pushHub(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(platform: TargetPlatform.macOS),
    locale: const Locale('uz'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const OfflineHistoryHubScreen(
            generalTab: Center(child: Text('GEN-BODY')),
            diagnosticTab: Center(child: Text('DIAG-BODY')),
          ),
        )),
        child: const Text('OPEN'),
      ),
    ),
  ));
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

Future<void> _trackpadSwipe(
    WidgetTester tester, Offset start, Offset pan) async {
  final p = TestPointer(1, PointerDeviceKind.trackpad);
  await tester.sendEventToBinding(p.panZoomStart(start));
  for (var i = 1; i <= 10; i++) {
    await tester
        .sendEventToBinding(p.panZoomUpdate(start, pan: pan * (i / 10)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.sendEventToBinding(p.panZoomEnd());
  await tester.pumpAndSettle();
}

void trackpadTests() {
  testWidgets('trackpad swipe left switches to Diagnostika, route stays',
      (tester) async {
    await _pushHub(tester);
    expect(find.text('GEN-BODY'), findsOneWidget);
    await _trackpadSwipe(tester, const Offset(400, 300), const Offset(-600, 0));
    expect(find.byType(OfflineHistoryHubScreen), findsOneWidget);
    expect(find.text('OPEN'), findsNothing);
    expect(find.text('DIAG-BODY'), findsOneWidget);
  });

  testWidgets('trackpad swipe right on first tab does not pop', (tester) async {
    await _pushHub(tester);
    await _trackpadSwipe(tester, const Offset(400, 300), const Offset(600, 0));
    expect(find.byType(OfflineHistoryHubScreen), findsOneWidget);
    expect(find.text('OPEN'), findsNothing);
  });

  // The only swipe-to-pop mechanism on macOS is the Cupertino back-swipe
  // strip on the left screen edge; it must be disabled on the hub.
  testWidgets('edge drag from left screen edge does not pop (macOS)',
      (tester) async {
    await _pushHub(tester);
    final g = await tester.startGesture(const Offset(5, 300));
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(120, 0));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byType(OfflineHistoryHubScreen), findsOneWidget);
    expect(find.text('OPEN'), findsNothing);
  });

  testWidgets('programmatic pop and maybePop still work', (tester) async {
    await _pushHub(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('OPEN'), findsOneWidget, reason: l10n.localeName);

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await Navigator.of(tester.element(find.byType(Scaffold))).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('OPEN'), findsOneWidget);
  });
}
