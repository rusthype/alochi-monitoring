import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_question_dots.dart';
import 'package:alochi_monitoring/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('DiagnosticQuestionDots', () {
    testWidgets('renders total dots, 2-digit-padded', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticQuestionDots(
        total: 12,
        currentIndex: 0,
        answeredIndexes: const {},
        onSelectIndex: (_) {},
      )));

      expect(find.text('01'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('current dot uses brand background', (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticQuestionDots(
        total: 3,
        currentIndex: 1,
        answeredIndexes: const {},
        onSelectIndex: (_) {},
      )));

      final container = tester.widget<Container>(find
          .ancestor(
            of: find.text('02'),
            matching: find.byType(Container),
          )
          .first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.brand);
    });

    testWidgets('answered, non-current dot uses the emerald-muted style',
        (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticQuestionDots(
        total: 3,
        currentIndex: 0,
        answeredIndexes: const {1},
        onSelectIndex: (_) {},
      )));

      final container = tester.widget<Container>(find
          .ancestor(
            of: find.text('02'),
            matching: find.byType(Container),
          )
          .first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.emeraldMuted);
    });

    testWidgets('unanswered, non-current dot uses the pageBg/border style',
        (tester) async {
      await tester.pumpWidget(_wrap(DiagnosticQuestionDots(
        total: 3,
        currentIndex: 0,
        answeredIndexes: const {},
        onSelectIndex: (_) {},
      )));

      final container = tester.widget<Container>(find
          .ancestor(
            of: find.text('02'),
            matching: find.byType(Container),
          )
          .first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppColors.pageBg);
      expect(decoration.border, isNotNull);
    });

    testWidgets('tapping a dot calls onSelectIndex with its 0-based index',
        (tester) async {
      int? tapped;
      await tester.pumpWidget(_wrap(DiagnosticQuestionDots(
        total: 3,
        currentIndex: 0,
        answeredIndexes: const {},
        onSelectIndex: (i) => tapped = i,
      )));

      await tester.tap(find.text('03'));
      await tester.pump();

      expect(tapped, 2);
    });
  });
}
