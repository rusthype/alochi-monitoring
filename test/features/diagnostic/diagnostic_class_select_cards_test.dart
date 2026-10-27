import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_class_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_class_grid.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_school_card.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Map<String, dynamic> cls(
  String label, {
  String lang = 'uz',
  bool noTests = false,
}) =>
    {'class_label': label, 'language': lang, 'no_tests': noTests};

void main() {
  Future<List<Object?>> pump(
    WidgetTester t,
    List<Map<String, dynamic>> rows, {
    Size size = const Size(1280, 720),
    bool fail = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final pushed = <Object?>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => DiagnosticClassSelectScreen(
            schoolId: 's1',
            schoolName: 'School',
            loadClasses: (_) async {
              if (fail) throw Exception('boom');
              return (rows.toList(), false);
            },
          ),
        ),
        GoRoute(
          path: '/diagnostic_student_select',
          builder: (_, state) {
            pushed.add(state.extra);
            return const Scaffold(body: Text('student-select'));
          },
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('uz'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await t.pumpAndSettle();
    return pushed;
  }

  int columns(WidgetTester t) {
    final tops = t
        .widgetList<DiagnosticSchoolCard>(find.byType(DiagnosticSchoolCard))
        .map((w) => t.getTopLeft(find.byWidget(w)).dy)
        .toList();
    return tops.where((y) => y == tops.first).length;
  }

  test('grade number + column helper', () {
    expect(classGradeNumber('3-A'), 3);
    expect(classGradeNumber('10-B'), 10);
    expect(classGradeNumber('Boshlang'), isNull);
    expect(diagnosticClassColumns(100), 1);
    expect(diagnosticClassColumns(5000), 6);
  });

  testWidgets('renders badge + label cards, natural order', (t) async {
    await pump(t, [cls('10-A'), cls('3-B'), cls('3-A')]);
    expect(find.byType(DiagnosticSchoolCard), findsNWidgets(3));
    final order = t
        .widgetList<DiagnosticSchoolCard>(find.byType(DiagnosticSchoolCard))
        .map((c) => c.title)
        .toList();
    expect(order, ['3-A', '3-B', '10-A']);
    // Badge number and large label are both rendered.
    expect(find.text('3'), findsNWidgets(2));
    expect(find.text('10'), findsOneWidget);
    expect(find.text('3-A'), findsOneWidget);
  });

  testWidgets('language line only when needed', (t) async {
    await pump(t, [cls('3-A'), cls('3-B', lang: 'ru')]);
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text("O'zbek"), findsOneWidget);
  });

  testWidgets('tap selects class and pushes student select', (t) async {
    final pushed = await pump(t, [cls('3-A'), cls('3-B')]);
    await t.tap(find.text('3-B'));
    await t.pumpAndSettle();
    expect(find.text('student-select'), findsOneWidget);
    expect((pushed.single as Map)['classLabel'], '3-B');
  });

  testWidgets('no_tests class shows snackbar instead of navigating', (t) async {
    await pump(t, [cls('3-A', noTests: true)]);
    await t.tap(find.text('3-A'));
    await t.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('student-select'), findsNothing);
  });

  testWidgets('column count adapts to window width', (t) async {
    final rows = [for (var i = 1; i <= 12; i++) cls('$i-A')];
    await pump(t, rows, size: const Size(1280, 720));
    final c1280 = columns(t);
    final w1280 = t.getSize(find.byType(DiagnosticSchoolCard).first).width;
    await pump(t, rows, size: const Size(1920, 1080));
    final c1920 = columns(t);
    final w1920 = t.getSize(find.byType(DiagnosticSchoolCard).first).width;
    await pump(t, rows, size: const Size(1024, 600));
    final c1024 = columns(t);
    final w1024 = t.getSize(find.byType(DiagnosticSchoolCard).first).width;
    expect(c1920, greaterThan(c1280));
    expect(c1024, lessThanOrEqualTo(c1280));
    expect(c1024, greaterThanOrEqualTo(3));
    for (final w in [w1280, w1920, w1024]) {
      expect(w, inInclusiveRange(200, 280));
    }
  });

  testWidgets('empty state', (t) async {
    await pump(t, []);
    expect(find.byType(DiagnosticSchoolCard), findsNothing);
    expect(find.byType(DiagnosticClassGrid), findsNothing);
    final l10n = AppLocalizations.of(t.element(find.byType(Scaffold).first))!;
    expect(find.text(l10n.diagnosticNoClasses), findsOneWidget);
  });

  testWidgets('error state shows retry', (t) async {
    await pump(t, [], fail: true);
    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
  });
}
