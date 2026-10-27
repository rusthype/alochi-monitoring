import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_header_bar.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bar({int? grade, String classLabel = ''}) => MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DiagnosticHeaderBar(
          subjectLabel: 'Matematika',
          subjectIcon: Icons.calculate,
          subjectColor: Colors.blue,
          position: 1,
          total: 5,
          studentName: 'Aliyev Ali',
          language: 'uz',
          isFixedVariant: true,
          grade: grade,
          classLabel: classLabel,
        ),
      ),
    );

void main() {
  testWidgets('shows class label with letter and no redundant grade chip',
      (tester) async {
    await tester.pumpWidget(_bar(grade: 3, classLabel: '3-B'));
    expect(find.text('3-B'), findsOneWidget);
    expect(find.text('3-sinf'), findsNothing);
  });

  testWidgets('falls back to N-sinf chip when classLabel is empty',
      (tester) async {
    await tester.pumpWidget(_bar(grade: 3));
    expect(find.text('3-sinf'), findsOneWidget);
  });
}
