// AddStudentDialog: validation, success, the 409 "Bu shumi?" candidates step
// (choose one / "other child" resend) and error handling.
import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/models/add_student.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/widgets/add_student_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Call {
  final AddStudentDraft draft;
  final bool confirmNew;
  _Call(this.draft, this.confirmNew);
}

AddStudentResult _created(AddStudentDraft d) => AddStudentResult(
    id: 'srv-1', name: '${d.lastName} ${d.firstName}', pending: true);

const _sim = SimilarStudentsException([
  SimilarStudent(id: '7', name: 'Valiyev Ali', grade: 4, groupName: '4-B'),
  SimilarStudent(id: '8', name: 'Valiyev Alisher', grade: 5, groupName: '5-A'),
]);

void main() {
  late AppLocalizations l10n;
  AddStudentOutcome? outcome;
  var closed = false;

  Future<void> open(WidgetTester tester, AddStudentSubmit onSubmit) async {
    outcome = null;
    closed = false;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              outcome = await showAddStudentDialog(ctx, onSubmit: onSubmit);
              closed = true;
            },
            child: const Text('OPEN'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    l10n = AppLocalizations.of(tester.element(find.byType(AddStudentDialog)))!;
  }

  Future<void> fill(WidgetTester tester,
      {String last = 'Valiyev', String first = 'Ali'}) async {
    await tester.enterText(find.byKey(const Key('addStudentLastName')), last);
    await tester.enterText(find.byKey(const Key('addStudentFirstName')), first);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('addStudentSubmit')));
    await tester.tap(find.byKey(const Key('addStudentSubmit')));
    await tester.pumpAndSettle();
  }

  testWidgets('required + length + charset validation blocks submit',
      (tester) async {
    final calls = <_Call>[];
    await open(tester, (d, {required confirmNew}) async {
      calls.add(_Call(d, confirmNew));
      return _created(d);
    });

    await submit(tester); // both empty
    expect(find.text(l10n.addStudentRequired), findsNWidgets(2));

    await fill(tester, last: 'V', first: 'Ali1');
    await submit(tester);
    expect(find.text(l10n.addStudentNameLength), findsOneWidget);
    expect(find.text(l10n.addStudentNameChars), findsOneWidget);

    expect(calls, isEmpty);
    expect(closed, isFalse);
  });

  testWidgets('success: trimmed names + stable new:<uuid>, dialog resolves',
      (tester) async {
    final calls = <_Call>[];
    await open(tester, (d, {required confirmNew}) async {
      calls.add(_Call(d, confirmNew));
      return _created(d);
    });

    await fill(tester, last: '  Valiyev   ', first: " G'ulom  Ali ");
    await tester.enterText(
        find.byKey(const Key('addStudentParentFio')), '  Valiyev Karim ');
    await submit(tester);

    expect(calls, hasLength(1));
    expect(calls.single.confirmNew, isFalse);
    expect(calls.single.draft.lastName, 'Valiyev');
    expect(calls.single.draft.firstName, "G'ulom Ali");
    expect(calls.single.draft.parentFio, 'Valiyev Karim');
    expect(calls.single.draft.birthDate, isNull);
    expect(calls.single.draft.clientTempId, startsWith('new:'));
    expect(closed, isTrue);
    expect(outcome, isA<AddStudentCreated>());
    expect((outcome as AddStudentCreated).result.id, 'srv-1');
  });

  testWidgets(
      '409 -> "Bu shumi?" list; "Yo\'q, boshqa bola" resends confirm_new with '
      'the SAME temp id', (tester) async {
    final calls = <_Call>[];
    await open(tester, (d, {required confirmNew}) async {
      calls.add(_Call(d, confirmNew));
      if (!confirmNew) throw _sim;
      return _created(d);
    });
    await fill(tester);
    await submit(tester);

    expect(find.text(l10n.addStudentSimilarTitle), findsOneWidget);
    expect(find.text('Valiyev Ali'), findsOneWidget);
    expect(find.text('Valiyev Alisher'), findsOneWidget);
    expect(find.text('4-B'), findsOneWidget);
    expect(closed, isFalse);

    await tester.tap(find.byKey(const Key('addStudentNotThem')));
    await tester.pumpAndSettle();

    expect(calls.map((c) => c.confirmNew), [false, true]);
    expect(calls[1].draft.clientTempId, calls[0].draft.clientTempId);
    expect(outcome, isA<AddStudentCreated>());
  });

  testWidgets('409 -> picking a candidate uses the existing student, no resend',
      (tester) async {
    var n = 0;
    await open(tester, (d, {required confirmNew}) async {
      n++;
      throw _sim;
    });
    await fill(tester);
    await submit(tester);

    await tester.tap(find.text('Valiyev Alisher'));
    await tester.pumpAndSettle();

    expect(n, 1);
    expect(closed, isTrue);
    expect(outcome, isA<AddStudentUseExisting>());
    expect((outcome as AddStudentUseExisting).student.id, '8');
  });

  testWidgets('candidates step: back returns to the filled form',
      (tester) async {
    await open(tester, (d, {required confirmNew}) async => throw _sim);
    await fill(tester);
    await submit(tester);
    await tester.tap(find.byKey(const Key('addStudentBackToForm')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.addStudentTitle), findsOneWidget);
    expect(find.text('Valiyev'), findsOneWidget); // controller kept its text
  });

  testWidgets('server error is shown inline and a retry reuses the temp id',
      (tester) async {
    final calls = <_Call>[];
    await open(tester, (d, {required confirmNew}) async {
      calls.add(_Call(d, confirmNew));
      if (calls.length == 1) {
        throw const ApiException(409, 'x', code: 'pending_limit');
      }
      return _created(d);
    });
    await fill(tester);
    await submit(tester);

    expect(find.text(l10n.addStudentErrPendingLimit), findsOneWidget);
    expect(closed, isFalse);

    await submit(tester);
    expect(calls, hasLength(2));
    expect(calls[1].draft.clientTempId, calls[0].draft.clientTempId);
    expect(outcome, isA<AddStudentCreated>());
  });

  testWidgets('network error text from the api is shown', (tester) async {
    await open(tester, (d, {required confirmNew}) async {
      throw const ApiException(0, "Internet aloqasi yo'q.");
    });
    await fill(tester);
    await submit(tester);
    expect(find.text("Internet aloqasi yo'q."), findsOneWidget);
  });

  testWidgets('cancel closes with null', (tester) async {
    await open(tester, (d, {required confirmNew}) async => _created(d));
    await tester.tap(find.byKey(const Key('addStudentCancel')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(outcome, isNull);
  });
}
