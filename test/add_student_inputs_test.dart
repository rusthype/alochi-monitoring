// Title-case name formatter, masked KK.OO.YYYY birth date, and their wiring
// into AddStudentDialog.
import 'package:alochi_monitoring/core/models/add_student.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/utils/form_input_formatters.dart';
import 'package:alochi_monitoring/shared/widgets/add_student_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue _v(String t, [int? caret, TextRange? composing]) =>
    TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: caret ?? t.length),
      composing: composing ?? TextRange.empty,
    );

void main() {
  group('titleCaseName', () {
    test('Latin, caps lock and lowercase', () {
      expect(titleCaseName('VALIXON ALI'), 'Valixon Ali');
      expect(titleCaseName('valixon ali'), 'Valixon Ali');
      expect(titleCaseName('vAlIxOn'), 'Valixon');
    });
    test('Cyrillic', () {
      expect(titleCaseName('ВАЛИЕВ АЛИШЕР'), 'Валиев Алишер');
      expect(titleCaseName('ўктам ғулом'), 'Ўктам Ғулом');
    });
    test('apostrophes do not start a word (all variants)', () {
      expect(titleCaseName("o'g'li"), "O'g'li");
      expect(titleCaseName("G'OFUR"), "G'ofur");
      expect(titleCaseName("SA'DULLA"), "Sa'dulla");
      for (final a in ['ʻ', '‘', '’', 'ʼ', '`']) {
        expect(titleCaseName('O${a}G${a}LI'), 'O${a}g${a}li');
      }
    });
    test('hyphen and initials start a word; spaces kept as typed', () {
      expect(titleCaseName('anna-mariya'), 'Anna-Mariya');
      expect(titleCaseName('KARIMOV A.B.'), 'Karimov A.B.');
      expect(titleCaseName('ali  '), 'Ali  ');
    });
  });

  group('TitleCaseNameFormatter', () {
    const f = TitleCaseNameFormatter();
    test('typing keeps caret and fixes case', () {
      final r = f.formatEditUpdate(_v('Vali'), _v('VaLi', 4));
      expect(r.text, 'Vali');
      expect(r.selection.baseOffset, 4);
    });
    test('mid-string insert keeps the caret where the user is', () {
      // "Ali" -> user types "X" after "A": "AXli", caret 2
      final r = f.formatEditUpdate(_v('Ali'), _v('AXli', 2));
      expect(r.text, 'Axli');
      expect(r.selection.baseOffset, 2);
    });
    test('pasted ALL CAPS name', () {
      final r = f.formatEditUpdate(_v(''), _v("O'G'LI ALI", 10));
      expect(r.text, "O'g'li Ali");
      expect(r.selection.baseOffset, 10);
    });
    test('deleting keeps caret; no change returns the same value', () {
      final nv = _v('Vali', 2);
      expect(identical(f.formatEditUpdate(_v('Valix'), nv), nv), isTrue);
    });
    test('composing region is preserved', () {
      final nv = _v('vali', 4, const TextRange(start: 0, end: 4));
      final r = f.formatEditUpdate(_v('val'), nv);
      expect(r.text, 'Vali');
      expect(r.composing, const TextRange(start: 0, end: 4));
    });
  });

  group('BirthDateMaskFormatter', () {
    const f = BirthDateMaskFormatter();
    String typed(String digits) {
      var v = _v('');
      for (final ch in digits.split('')) {
        v = f.formatEditUpdate(v, _v(v.text + ch));
      }
      return v.text;
    }

    test('typing 15032016 -> 15.03.2016', () {
      expect(typed('15'), '15');
      expect(typed('153'), '15.3');
      expect(typed('15032'), '15.03.2');
      expect(typed('15032016'), '15.03.2016');
      expect(typed('150320169999'), '15.03.2016'); // capped
    });
    test('strips non-digits (paste with dots / letters)', () {
      final r = f.formatEditUpdate(_v(''), _v('15/03-2016ab', 12));
      expect(r.text, '15.03.2016');
    });
    test('caret stays beside the same digit when editing mid-string', () {
      // "15.03.2016", user deletes the "5" (caret after "1")
      final r = f.formatEditUpdate(_v('15.03.2016'), _v('1.03.2016', 1));
      expect(r.text, '10.32.016');
      expect(r.selection.baseOffset, 1);
    });
  });

  group('checkBirthDate', () {
    final today = DateTime(2026, 10, 23);
    BirthDateError? err(String t) => checkBirthDate(t, today: today).error;

    test('valid -> date', () {
      expect(checkBirthDate('15.03.2016', today: today).date,
          DateTime(2016, 3, 15));
      expect(err('15.03.2016'), isNull);
      expect(err('01.01.1990'), isNull);
      expect(err('23.10.2026'), isNull); // today
    });
    test('empty is fine', () {
      expect(checkBirthDate('', today: today), (date: null, error: null));
    });
    test('incomplete, bad day/month (flagged while typing), not a real date',
        () {
      expect(err('15.0'), BirthDateError.incomplete);
      expect(err('3'), BirthDateError.incomplete);
      expect(err('32'), BirthDateError.invalid);
      expect(err('00'), BirthDateError.invalid);
      expect(err('15.13'), BirthDateError.invalid);
      expect(err('15.00'), BirthDateError.invalid);
      expect(err('31.02.2016'), BirthDateError.invalid);
      expect(err('29.02.2015'), BirthDateError.invalid);
      expect(err('29.02.2016'), isNull);
    });
    test('future and before 1990 (backend rule)', () {
      expect(err('24.10.2026'), BirthDateError.future);
      expect(err('01.01.2030'), BirthDateError.future);
      expect(err('31.12.1989'), BirthDateError.tooOld);
    });
  });

  group('AddStudentDialog wiring', () {
    late AppLocalizations l10n;
    final calls = <AddStudentDraft>[];

    Future<void> open(WidgetTester tester) async {
      calls.clear();
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showAddStudentDialog(ctx,
                  onSubmit: (d, {required confirmNew}) async {
                calls.add(d);
                return const AddStudentResult(
                    id: 'x', name: 'n', pending: true);
              }),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      l10n =
          AppLocalizations.of(tester.element(find.byType(AddStudentDialog)))!;
    }

    Future<void> enter(WidgetTester tester, String key, String text) async {
      await tester.enterText(find.byKey(Key(key)), text);
      await tester.pump();
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('addStudentSubmit')));
      await tester.tap(find.byKey(const Key('addStudentSubmit')));
      await tester.pumpAndSettle();
    }

    String text(WidgetTester tester, String key) =>
        tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

    testWidgets('names are title-cased and sent normalized', (tester) async {
      await open(tester);
      await enter(tester, 'addStudentLastName', 'VALIXONOV');
      await enter(tester, 'addStudentFirstName', "o'tkir  SULTON");
      await enter(tester, 'addStudentParentFio', 'valixonov KARIM');
      expect(text(tester, 'addStudentLastName'), 'Valixonov');
      expect(text(tester, 'addStudentFirstName'), "O'tkir  Sulton");
      await submit(tester);
      expect(calls.single.lastName, 'Valixonov');
      expect(calls.single.firstName, "O'tkir Sulton"); // spaces collapsed
      expect(calls.single.parentFio, 'Valixonov Karim');
      expect(calls.single.birthDate, isNull);
    });

    testWidgets('typed digits are masked and sent as the picked date',
        (tester) async {
      await open(tester);
      await enter(tester, 'addStudentLastName', 'Valiyev');
      await enter(tester, 'addStudentFirstName', 'Ali');
      await enter(tester, 'addStudentBirthDate', '15032016');
      expect(text(tester, 'addStudentBirthDate'), '15.03.2016');
      await submit(tester);
      expect(calls.single.birthDate, DateTime(2016, 3, 15));
    });

    testWidgets('empty birth date does not block submit', (tester) async {
      await open(tester);
      await enter(tester, 'addStudentLastName', 'Valiyev');
      await enter(tester, 'addStudentFirstName', 'Ali');
      await submit(tester);
      expect(calls, hasLength(1));
    });

    testWidgets('invalid / future / incomplete dates show an error and block',
        (tester) async {
      await open(tester);
      await enter(tester, 'addStudentLastName', 'Valiyev');
      await enter(tester, 'addStudentFirstName', 'Ali');

      // Incomplete: no nagging while typing, but submit is blocked + explained.
      await enter(tester, 'addStudentBirthDate', '1503');
      expect(find.text(l10n.addStudentBirthDateIncomplete), findsNothing);
      await submit(tester);
      expect(calls, isEmpty);
      expect(find.text(l10n.addStudentBirthDateIncomplete), findsOneWidget);

      await enter(tester, 'addStudentBirthDate', '3202');
      expect(find.text(l10n.addStudentErrInvalidBirthDate), findsOneWidget);

      await enter(tester, 'addStudentBirthDate', '31022016');
      expect(find.text(l10n.addStudentErrInvalidBirthDate), findsOneWidget);

      final y = DateTime.now().year + 1;
      await enter(tester, 'addStudentBirthDate', '0101$y');
      expect(find.text(l10n.addStudentBirthDateFuture), findsOneWidget);

      await enter(tester, 'addStudentBirthDate', '01011985');
      expect(find.text(l10n.addStudentBirthDateTooOld), findsOneWidget);

      await submit(tester);
      expect(calls, isEmpty);

      await enter(tester, 'addStudentBirthDate', '15032016');
      expect(find.text(l10n.addStudentBirthDateIncomplete), findsNothing);
      await submit(tester);
      expect(calls, hasLength(1));
    });

    testWidgets('calendar button opens the picker, picked date fills field',
        (tester) async {
      await open(tester);
      await enter(tester, 'addStudentBirthDate', '15032016');
      await tester
          .ensureVisible(find.byKey(const Key('addStudentBirthDatePick')));
      await tester.tap(find.byKey(const Key('addStudentBirthDatePick')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      // Year mode first; OK keeps the typed initial date.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(text(tester, 'addStudentBirthDate'), '15.03.2016');
    });
  });
}
