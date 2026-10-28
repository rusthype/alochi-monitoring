// The student thank-you screen only says "Yuborildi" (sent) when the offline
// queue is really empty; while results are still queued it says "Saqlandi"
// (saved) calmly, and it never shows the teacher's red cloud-off badge/count.
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_finished_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/sync_status_badge.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(SharedPreferences prefs, Future<int> Function() pending) =>
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DiagnosticFinishedScreen(
          pendingCountOverride: pending,
          onReturn: () {},
        ),
      ),
    );

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

  Future<void> boot(WidgetTester tester, Future<int> Function() pending) async {
    await tester.pumpWidget(_wrap(prefs, pending));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('results still queued: "Saqlandi", no "Yuborildi", no badge',
      (tester) async {
    await boot(tester, () async => 2);
    final t = l10n(tester);
    expect(find.text(t.diagnosticFinishedSavedPill), findsOneWidget);
    expect(find.text(t.diagnosticFinishedSubmittedPill), findsNothing);
    expect(find.byType(SyncStatusBadge), findsNothing);
    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    expect(find.text('2'), findsNothing, reason: 'no pending count for a student');
    await tester.pump(const Duration(seconds: 16));
  });

  testWidgets('queue empty: "Yuborildi"', (tester) async {
    await boot(tester, () async => 0);
    final t = l10n(tester);
    expect(find.text(t.diagnosticFinishedSubmittedPill), findsOneWidget);
    expect(find.text(t.diagnosticFinishedSavedPill), findsNothing);
    expect(find.byType(SyncStatusBadge), findsNothing);
    await tester.pump(const Duration(seconds: 16));
  });

  testWidgets('queue cannot be read: stays honest ("Saqlandi")',
      (tester) async {
    await boot(tester, () async => throw StateError('db'));
    final t = l10n(tester);
    expect(find.text(t.diagnosticFinishedSavedPill), findsOneWidget);
    expect(find.text(t.diagnosticFinishedSubmittedPill), findsNothing);
    await tester.pump(const Duration(seconds: 16));
  });

  testWidgets('flips to "Yuborildi" once the queue drains', (tester) async {
    var pending = 1;
    await boot(tester, () async => pending);
    final t = l10n(tester);
    expect(find.text(t.diagnosticFinishedSavedPill), findsOneWidget);

    pending = 0;
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(t.diagnosticFinishedSubmittedPill), findsOneWidget);
    expect(find.text(t.diagnosticFinishedSavedPill), findsNothing);
    await tester.pump(const Duration(seconds: 16));
  });
}
