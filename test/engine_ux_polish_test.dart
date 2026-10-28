// test/engine_ux_polish_test.dart
// TestEngine UX polish: tab-tap scroll to first unanswered, green "next" when
// the section is complete, direction-aware section switch, image retry box
// and skeleton placeholder.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/core/engine/question_widgets.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/theme/app_colors.dart';
import 'package:alochi_monitoring/core/widgets/skeleton.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

List<Map<String, dynamic>> _qs(String p, int n) => [
      for (var i = 0; i < n; i++)
        {
          'type': 'text_choice',
          'q': '${p}q$i',
          'opts': ['${p}q${i}o0', '${p}q${i}o1'],
          'ans': 0,
        },
    ];

TestSpec _spec() => TestSpec.fromJson({
      'test_key': 'engine_ux_polish_v1',
      'title': 'UX',
      'grade': 5,
      'version': 1,
      'parts': ['A', 'B'],
      'variants': {
        '1': {'A': _qs('a', 1), 'B': _qs('b', 6)},
      },
    });

Future<void> _pumpEngine(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TestEngine(
      spec: _spec(),
      variant: 1,
      firstName: 'Ism',
      lastName: 'Familiya',
      school: '56',
      studentId: '',
      duration: const Duration(minutes: 10),
      onComplete: (_, __) {},
    ),
  ));
  await tester.pumpAndSettle();
}

double _scrollOffset(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(
        of: find.byType(AnimatedSwitcher), matching: find.byType(Scrollable)))
    .position
    .pixels;

Color _nextColor(WidgetTester tester) {
  final btn = tester.widget<ElevatedButton>(find.ancestor(
      of: find.byIcon(Icons.arrow_forward_rounded),
      matching: find.byType(ElevatedButton)));
  return btn.style!.backgroundColor!.resolve({})!;
}

void main() {
  testWidgets('next button turns green only when the section is complete',
      (tester) async {
    await _pumpEngine(tester);
    expect(_nextColor(tester), AppColors.brand);

    await tester.tap(find.text('aq0o0'));
    await tester.pumpAndSettle();
    expect(_nextColor(tester), AppColors.ok);
  });

  testWidgets('tapping the active tab scrolls to first unanswered question',
      (tester) async {
    await _pumpEngine(tester);
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('bq0o0'), findsOneWidget);

    await tester.tap(find.text('bq0o0'));
    await tester.tap(find.text('bq1o0'));
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), 0);

    await tester.tap(find.widgetWithText(GestureDetector, 'B').first);
    await tester.pumpAndSettle();

    // q2 is the first unanswered one: scrolled down, still on section B.
    expect(_scrollOffset(tester), greaterThan(0));
    expect(find.text('bq2o0').hitTestable(), findsOneWidget);
    expect(find.text('bq0o0').hitTestable(), findsNothing);
    expect(find.text('aq0o0'), findsNothing);
  });

  testWidgets('active tab tap does nothing when everything is answered',
      (tester) async {
    await _pumpEngine(tester);
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      final f = find.text('bq${i}o0');
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }
    final before = _scrollOffset(tester);
    await tester.tap(find.widgetWithText(GestureDetector, 'B').first);
    await tester.pumpAndSettle();
    expect(_scrollOffset(tester), before);
  });

  testWidgets('section switch slides in direction of travel', (tester) async {
    await _pumpEngine(tester);
    final aFinal = tester.getTopLeft(find.text('aq0o0')).dx;

    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-transition: both sections are alive.
    expect(find.text('aq0o0'), findsOneWidget);
    expect(find.text('bq0o0'), findsOneWidget);
    final bMid = tester.getTopLeft(find.text('bq0o0')).dx;
    await tester.pumpAndSettle();
    final bFinal = tester.getTopLeft(find.text('bq0o0')).dx;
    expect(find.text('aq0o0'), findsNothing);
    expect(bMid, greaterThan(bFinal)); // enters from the right going forward

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    final aMid = tester.getTopLeft(find.text('aq0o0')).dx;
    await tester.pumpAndSettle();
    expect(aMid, lessThan(aFinal)); // enters from the left going back
    expect(find.text('bq0o0'), findsNothing);
  });

  testWidgets('broken image box shows a tappable retry label', (tester) async {
    var retried = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: brokenImagePlaceholder(120,
            retryLabel: 'Qayta urinish', onRetry: () => retried++),
      ),
    ));
    await tester.tap(find.text('Qayta urinish'));
    expect(retried, 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: brokenImagePlaceholder(120)),
    ));
    expect(find.text('Qayta urinish'), findsNothing);
  });

  testWidgets('loading image shows a skeleton, not a spinner', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SpellingWidget(
          index: 0,
          question: const Question(
            type: QuestionType.spelling,
            scramble: 'cat',
            strAns: 'cat',
            img: 'https://example.invalid/x.jpg',
          ),
          controller: TextEditingController(),
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.byType(Skeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
