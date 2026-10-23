// DiagnosticStudentSelectScreen "Bola qo'shish": created child shows up as a
// pending roster row and is selected; "Bu shumi?" -> existing selects the
// matching roster row by name (or says the child is in another class).
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/models/add_student.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_prefetch_cache.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_student_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_widgets.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _students = <Map<String, dynamic>>[
  {'attempt_id': 'att-1', 'student_name': 'Aliyev Ali', 'session_grade': 4},
];

late SharedPreferences _prefs;

Widget _wrap(
    Future<AddStudentResult> Function(AddStudentDraft,
            {required bool confirmNew})
        add) {
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(_prefs)],
    child: MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DiagnosticStudentSelectScreen(
        schoolId: 's1',
        schoolName: 'Maktab 1',
        classLabel: '4-A',
        language: 'uz',
        listStudentsOverride: (_, __) async => (_students, false),
        availableSubjectsOverride: (grade, {String language = 'uz'}) async =>
            {'subjects': <String>[]},
        addStudentOverride: add,
      ),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
    DiagnosticPrefetchCache.instance.reset();
  });

  Future<void> openAndSubmit(WidgetTester tester,
      {String last = 'Karimov', String first = 'Vali'}) async {
    await tester.tap(find.byKey(const Key('addStudentButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addStudentLastName')), last);
    await tester.enterText(find.byKey(const Key('addStudentFirstName')), first);
    await tester.ensureVisible(find.byKey(const Key('addStudentSubmit')));
    await tester.tap(find.byKey(const Key('addStudentSubmit')));
    await tester.pumpAndSettle();
  }

  bool ctaEnabled(WidgetTester tester) => tester
      .widget<DiagnosticBottomCta>(find.byType(DiagnosticBottomCta))
      .enabled;

  testWidgets('created child: pending row, selected, class + language sent',
      (tester) async {
    AddStudentDraft? got;
    await tester.pumpWidget(_wrap((draft, {required confirmNew}) async {
      got = draft;
      return const AddStudentResult(
        id: 'att-9',
        name: 'Karimov Vali',
        classLabel: '4-A',
        language: 'uz',
        status: 'not_started',
      );
    }));
    await tester.pumpAndSettle();
    expect(ctaEnabled(tester), isFalse);

    await openAndSubmit(tester);

    expect(got!.lastName, 'Karimov');
    expect(got!.clientTempId, startsWith('new:'));
    expect(find.text('Karimov Vali'), findsOneWidget);
    expect(find.byKey(const Key('pendingBadge')), findsOneWidget);
    expect(ctaEnabled(tester), isTrue);
  });

  for (final width in [190.0, 340.0]) {
    testWidgets('pending badge sits below a long name (card width $width)',
        (tester) async {
      const longName = 'Valiyevalivalixonovich Muhammadalijonovich';
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: DiagnosticStudentCard(
                name: longName,
                isSelected: true,
                onTap: () {},
                isPending: true,
                attemptStatus: 'partial',
                status: StudentPrefetchStatus.ready,
                hasOnlineOnlySubject: true,
              ),
            ),
          ),
        ),
      ));
      final nameFinder = find.text(longName);
      expect(tester.widget<Text>(nameFinder).maxLines, 2);
      final badge = find.byKey(const Key('pendingBadge'));
      expect(badge, findsOneWidget);
      expect(tester.getTopLeft(badge).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(nameFinder).dy));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('"Bu shumi?" -> same-name roster row is selected, no new row',
      (tester) async {
    await tester.pumpWidget(_wrap((draft, {required confirmNew}) async {
      throw const SimilarStudentsException([
        // reversed token order on purpose
        SimilarStudent(id: '7', name: 'Ali Aliyev', grade: 4, groupName: '4-A'),
      ]);
    }));
    await tester.pumpAndSettle();
    await openAndSubmit(tester, last: 'Aliyev', first: 'Ali');
    await tester.tap(find.descendant(
        of: find.byType(Dialog), matching: find.text('Ali Aliyev')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const Key('pendingBadge')), findsNothing);
    expect(ctaEnabled(tester), isTrue);
  });

  testWidgets('"Bu shumi?" -> candidate from another class: says where',
      (tester) async {
    final l10n = (await (() async {
      await tester.pumpWidget(_wrap((draft, {required confirmNew}) async {
        throw const SimilarStudentsException([
          SimilarStudent(
              id: '8', name: 'Rahimov Sher', grade: 4, groupName: '4-B'),
        ]);
      }));
      await tester.pumpAndSettle();
      return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
    })())!;
    await openAndSubmit(tester, last: 'Rahimov', first: 'Sher');
    await tester.tap(find.descendant(
        of: find.byType(Dialog), matching: find.text('Rahimov Sher')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.addStudentCandidateOtherClass('Rahimov Sher', '4-B')),
        findsOneWidget);
    expect(ctaEnabled(tester), isFalse);
  });
}
