import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/services/diagnostic_export_service.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:archive/archive.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

late AppLocalizations uz;

String passport(Map<String, dynamic> r) =>
    DiagnosticExportService.generateStudentPassportHtml(r, l10n: uz);

Uint8List zip(List<Map<String, dynamic>> r,
        {void Function(int done)? onProgress}) =>
    DiagnosticExportService.buildZipBytes(r, l10n: uz, onProgress: onProgress);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    uz = await AppLocalizations.delegate.load(const Locale('uz'));
  });

  group('DiagnosticExportService.generateStudentPassportHtml', () {
    test('a "sent" record with both scores renders full passport with scores',
        () {
      final html = passport({
        'attempt_id': 'a1b2c3d4-0000',
        'student_name': 'Aliyev Ali',
        'class_label': '4-A',
        'school': '56-maktab',
        'math_score': 25,
        'english_score': 28,
        'status': 'sent',
        'date_taken': 1735689600000,
      });

      expect(html, contains('Aliyev Ali'));
      expect(html, contains('4-A'));
      expect(html, contains('56-maktab'));
      expect(html, contains('25/30'));
      expect(html, contains('28/30'));
      // 53/60 = 88% -> "A'lo" band
      expect(html, contains('88%'));
      expect(html, contains("A'lo"));
      expect(html, isNot(contains('Natija hali serverga yuborilmagan')));
    });

    test('a low-scoring "sent" record gets the "Qayta mashq kerak" verdict',
        () {
      final html = passport({
        'attempt_id': 'low0000-0000',
        'student_name': 'Valiyev Vali',
        'class_label': '3-B',
        'school': '12-maktab',
        'math_score': 5,
        'english_score': 3,
        'status': 'sent',
        'date_taken': 1735689600000,
      });

      // (5+3)/60 = 13% -> below 60
      expect(html, contains('13%'));
      expect(html, contains('Qayta mashq kerak'));
    });

    test(
        'a "pending" record (both scores null) renders the pending status block, no score UI',
        () {
      final html = passport({
        'attempt_id': 'p1',
        'student_name': 'Karimov Karim',
        'class_label': '5-C',
        'school': '7-maktab',
        'math_score': null,
        'english_score': null,
        'status': 'pending',
        'date_taken': 1735689600000,
      });

      expect(html, contains('Karimov Karim'));
      expect(html, contains('Natija hali serverga yuborilmagan'));
      expect(html, isNot(contains('AI xulosa')));
      expect(html, isNot(contains('14 Kunlik reja')));
    });

    test('handles a null date_taken without throwing', () {
      expect(
        () => passport({
          'attempt_id': 'x1',
          'student_name': 'No Date',
          'class_label': '1-A',
          'school': 'Test',
          'math_score': null,
          'english_score': null,
          'status': 'pending',
          'date_taken': null,
        }),
        returnsNormally,
      );
    });

    test(
        'a locally-estimated "pending" record shows the unofficial-estimate banner',
        () {
      final html = passport({
        'attempt_id': 'est1',
        'student_name': 'Estimated Student',
        'class_label': '3-A',
        'school': '7-maktab',
        'math_score': 20,
        'english_score': 22,
        'status': 'pending',
        'date_taken': 1735689600000,
        '_local_estimate': true,
      });

      expect(html, contains('Estimated Student'));
      expect(html, contains('20/30'));
      expect(html, contains('22/30'));
      expect(html, contains('Taxminiy natija'));
      expect(html, isNot(contains('Natija hali serverga yuborilmagan')));
    });
  });

  group('DiagnosticExportService.buildZipBytes', () {
    test('produces one HTML entry per record, named collision-safely', () {
      final bytes = zip([
        {
          'attempt_id': 'aaaa1111-xxxx',
          'student_name': 'Aliyev Ali',
          'class_label': '4-A',
          'school': '56-maktab',
          'math_score': 20,
          'english_score': 22,
          'status': 'sent',
          'date_taken': 1735689600000,
        },
        {
          'attempt_id': 'bbbb2222-xxxx',
          'student_name': 'Aliyev Ali', // same name+class, different attempt
          'class_label': '4-A',
          'school': '56-maktab',
          'math_score': null,
          'english_score': null,
          'status': 'pending',
          'date_taken': 1735689600000,
        },
      ]);

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.length, equals(2));
      final names = archive.map((f) => f.name).toSet();
      expect(names.length, equals(2)); // no filename collision
      for (final name in names) {
        expect(name, endsWith('.html'));
      }
    });

    test('reports progress once per record via onProgress', () {
      final progressCalls = <int>[];
      zip(
        [
          {
            'attempt_id': 'a1',
            'student_name': 'A',
            'class_label': '1-A',
            'school': 'S',
            'math_score': 10,
            'english_score': 10,
            'status': 'sent',
            'date_taken': 1,
          },
          {
            'attempt_id': 'a2',
            'student_name': 'B',
            'class_label': '1-A',
            'school': 'S',
            'math_score': null,
            'english_score': null,
            'status': 'pending',
            'date_taken': 2,
          },
        ],
        onProgress: progressCalls.add,
      );

      expect(progressCalls, equals([1, 2]));
    });

    test('an empty record list produces a valid, empty zip', () {
      final bytes = zip(const []);
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.length, equals(0));
    });
  });

  group('DiagnosticExportService.withLocalEstimates', () {
    test('scores a pending record from its queued diagnostic_finish payloads',
        () {
      final records = [
        {
          'attempt_id': 'att-1',
          'student_name': 'Karimov Karim',
          'class_label': '3-A',
          'school': '7-maktab',
          'math_score': null,
          'english_score': null,
          'status': 'pending',
          'date_taken': 1735689600000,
        },
      ];
      final queued = [
        {
          '_offlineKind': 'diagnostic_finish',
          'attempt_id': 'att-1',
          'answers': [
            {'question_id': 'q1', 'selected': 'A'},
            {'question_id': 'q2', 'selected': 'B'},
          ],
          '_offline_answer_key': {
            'subject': 'math',
            'answers': {'q1': 'A', 'q2': 'C'},
          },
        },
      ];

      final result =
          DiagnosticExportService.withLocalEstimates(records, queued);

      expect(result.length, equals(1));
      expect(result.first['math_score'], equals(1)); // q1 correct, q2 wrong
      expect(result.first['english_score'], isNull); // no english row queued
      expect(result.first['_local_estimate'], isTrue);
      expect(result.first['status'], equals('pending')); // status unchanged
    });

    test('combines separate math and english queued rows for the same attempt',
        () {
      final records = [
        {
          'attempt_id': 'att-2',
          'student_name': 'X',
          'class_label': '3-A',
          'school': 'S',
          'math_score': null,
          'english_score': null,
          'status': 'pending',
          'date_taken': 1,
        },
      ];
      final queued = [
        {
          '_offlineKind': 'diagnostic_finish',
          'attempt_id': 'att-2',
          'answers': [
            {'question_id': 'm1', 'selected': 'A'},
          ],
          '_offline_answer_key': {
            'subject': 'math',
            'answers': {'m1': 'A'},
          },
        },
        {
          '_offlineKind': 'diagnostic_finish',
          'attempt_id': 'att-2',
          'answers': [
            {'question_id': 'e1', 'selected': 'B'},
            {'question_id': 'e2', 'selected': 'B'},
          ],
          '_offline_answer_key': {
            'subject': 'english',
            'answers': {'e1': 'A', 'e2': 'B'},
          },
        },
      ];

      final result =
          DiagnosticExportService.withLocalEstimates(records, queued);

      expect(result.first['math_score'], equals(1));
      expect(result.first['english_score'], equals(1));
    });

    test(
        'an empty answer-key map (subject started from a peeked/dry_run '
        'fallback package, never carries correct_display_letter) must not '
        'report a false 0 score', () {
      final records = [
        {
          'attempt_id': 'att-peek-fallback',
          'student_name': 'Q',
          'class_label': '3-A',
          'school': 'S',
          'math_score': null,
          'english_score': null,
          'status': 'pending',
          'date_taken': 1,
        },
      ];
      final queued = [
        {
          '_offlineKind': 'diagnostic_finish',
          'attempt_id': 'att-peek-fallback',
          'answers': [
            {'question_id': 'q1', 'selected': 'A'},
            {'question_id': 'q2', 'selected': 'B'},
          ],
          '_offline_answer_key': {
            'subject': 'math',
            'answers': <String, String>{}, // peeked package: no key data at all
          },
        },
      ];

      final result =
          DiagnosticExportService.withLocalEstimates(records, queued);

      expect(result.first['math_score'], isNull);
      expect(result.first.containsKey('_local_estimate'), isFalse);
    });

    test('leaves a pending record untouched when no matching queue data exists',
        () {
      final records = [
        {
          'attempt_id': 'att-3',
          'student_name': 'Y',
          'class_label': '3-A',
          'school': 'S',
          'math_score': null,
          'english_score': null,
          'status': 'pending',
          'date_taken': 1,
        },
      ];

      final result =
          DiagnosticExportService.withLocalEstimates(records, const []);

      expect(result.first['math_score'], isNull);
      expect(result.first['english_score'], isNull);
      expect(result.first.containsKey('_local_estimate'), isFalse);
    });

    test(
        'never touches an already-"sent" record even if stale queue data exists',
        () {
      final records = [
        {
          'attempt_id': 'att-4',
          'student_name': 'Z',
          'class_label': '3-A',
          'school': 'S',
          'math_score': 25,
          'english_score': 28,
          'status': 'sent',
          'date_taken': 1,
        },
      ];
      final queued = [
        {
          '_offlineKind': 'diagnostic_finish',
          'attempt_id': 'att-4',
          'answers': [
            {'question_id': 'q1', 'selected': 'A'},
          ],
          '_offline_answer_key': {
            'subject': 'math',
            'answers': {'q1': 'A'},
          },
        },
      ];

      final result =
          DiagnosticExportService.withLocalEstimates(records, queued);

      expect(
          result.first['math_score'], equals(25)); // official score, unchanged
      expect(result.first.containsKey('_local_estimate'), isFalse);
    });

    test(
        'ignores queue rows that are not diagnostic_finish or belong to a different attempt',
        () {
      final records = [
        {
          'attempt_id': 'att-5',
          'student_name': 'W',
          'class_label': '3-A',
          'school': 'S',
          'math_score': null,
          'english_score': null,
          'status': 'pending',
          'date_taken': 1,
        },
      ];
      final queued = [
        {
          '_offlineKind': 'question_report',
          'attempt_id': 'att-5',
          'answers': []
        },
        {
          '_offlineKind': 'diagnostic_finish',
          'attempt_id': 'some-other-attempt',
          'answers': [
            {'question_id': 'q1', 'selected': 'A'}
          ],
          '_offline_answer_key': {
            'subject': 'math',
            'answers': {'q1': 'A'},
          },
        },
      ];

      final result =
          DiagnosticExportService.withLocalEstimates(records, queued);

      expect(result.first['math_score'], isNull);
    });

    test(
        'a subject already sent officially keeps its score when the queue only '
        'estimates the other subject (math sent=18, english pending=25)', () {
      final records = [
        {
          'attempt_id': 'att-mixed',
          'student_name': 'M',
          'class_label': '3-A',
          'school': 'S',
          'math_score': 18,
          'english_score': null,
          'status': 'pending',
          'date_taken': 1,
        },
      ];
      final queued = [
        {
          '_offlineKind': 'diagnostic_finish',
          'attempt_id': 'att-mixed',
          'answers': [
            for (var i = 1; i <= 25; i++)
              {'question_id': 'e$i', 'selected': 'A'},
          ],
          '_offline_answer_key': {
            'subject': 'english',
            'answers': {for (var i = 1; i <= 25; i++) 'e$i': 'A'},
          },
        },
      ];

      final result =
          DiagnosticExportService.withLocalEstimates(records, queued);

      expect(result.first['math_score'], equals(18)); // official, not null
      expect(result.first['english_score'], equals(25));
      expect(result.first['_local_estimate'], isTrue);
      final html = passport(result.first);
      expect(html, contains('18/'));
      expect(html, contains('25/'));
    });
  });

  group('DiagnosticExportService hardening', () {
    const hostile = {
      'attempt_id': 'att-xss-0001',
      'student_name': '<script>alert(1)</script>',
      'class_label': '4-<b>A',
      'school': 'A&B "maktab"',
      'date_taken': 1735689600000,
    };

    test('sent passport HTML-escapes name, class and school, title included',
        () {
      final html = passport({
        ...hostile,
        'math_score': 20,
        'english_score': 10,
        'status': 'sent',
      });
      expect(html, isNot(contains('<script>')));
      expect(html, isNot(contains('<b>A')));
      expect(html, contains('&lt;script&gt;'));
      expect(html, contains('4-&lt;b&gt;A'));
      expect(html, contains('A&amp;B'));
      expect(html, contains("<title>A'lochi"));
      expect(RegExp(r'<title>[^<]*&lt;script&gt;').hasMatch(html), isTrue);
    });

    test('pending passport HTML-escapes name, class and school', () {
      final html = passport({
        ...hostile,
        'math_score': null,
        'english_score': null,
        'status': 'pending',
      });
      expect(html, isNot(contains('<script>')));
      expect(html, isNot(contains('<b>A')));
      expect(html, contains('&lt;script&gt;'));
      expect(html, contains('A&amp;B'));
    });

    test('zip entry names never contain separators, .. or control chars', () {
      final bytes = zip([
        {
          'attempt_id': 'a/b\\..c-0001',
          'student_name': 'a/b\\..c\u0007d',
          'class_label': '4-A',
          'school': 's',
          'math_score': 1,
          'english_score': 1,
          'status': 'sent',
          'date_taken': 1,
        },
      ]);
      final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name);
      expect(names, hasLength(1));
      for (final n in names) {
        expect(n, isNot(contains('/')));
        expect(n, isNot(contains('\\')));
        expect(n, isNot(contains('..')));
        expect(n.codeUnits.any((c) => c < 0x20 || c == 0x7f), isFalse);
      }
    });

    test('saving twice at the same instant never overwrites the first file',
        () async {
      final dir = await Directory.systemTemp.createTemp('diag_zip_');
      addTearDown(() => dir.delete(recursive: true));
      final now = DateTime(2026, 11, 5, 9, 30, 15);
      final a = await DiagnosticExportService.saveZipUnique(
          dir, Uint8List.fromList([1, 2, 3]), now);
      final b = await DiagnosticExportService.saveZipUnique(
          dir, Uint8List.fromList([9, 9]), now);
      expect(a, isNot(b));
      expect(File(a).readAsBytesSync(), [1, 2, 3]);
      expect(File(b).readAsBytesSync(), [9, 9]);
      expect(a, contains('2026-11-05_093015'));
      // Atomic write: no .tmp leftover.
      expect(dir.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    test('puts the sanitised school label into the file name', () async {
      final dir = await Directory.systemTemp.createTemp('diag_zip_');
      addTearDown(() => dir.delete(recursive: true));
      final now = DateTime(2026, 11, 5, 9, 30, 15);
      final a = await DiagnosticExportService.saveZipUnique(
          dir, Uint8List.fromList([1]), now,
          label: '56');
      final b = await DiagnosticExportService.saveZipUnique(
          dir, Uint8List.fromList([1]), now,
          label: 'Bir / Ikki: ../maktab');
      expect(a.split('/').last, 'alochi_diagnostika_56_2026-11-05_093015.zip');
      final bName = b.split('/').last;
      expect(bName, startsWith('alochi_diagnostika_Bir_Ikki_'));
      expect(bName, isNot(contains('..')));
      expect(bName, endsWith('_2026-11-05_093015.zip'));
    });

    group('retention (kExportKeepPerSchool)', () {
      Future<Directory> tmp() async {
        final d = await Directory.systemTemp.createTemp('diag_prune_');
        addTearDown(() => d.delete(recursive: true));
        return d;
      }

      File seed(Directory d, String name) {
        final f = File('${d.path}/$name')..writeAsBytesSync([0]);
        return f;
      }

      String nm(String label, int day, {String t = '090000', String x = ''}) =>
          'alochi_diagnostika_${label}_2026-10-${day.toString().padLeft(2, '0')}_$t$x.zip';

      test('keeps the 5 newest of the label incl. the new one; foreign untouched',
          () async {
        final dir = await tmp();
        for (var d = 1; d <= 7; d++) {
          seed(dir, nm('A', d));
        }
        seed(dir, nm('B', 1));
        seed(dir, 'alochi_diagnostika_A_notadate.zip');
        seed(dir, 'alochi_diagnostika_A_2026-10-01_090000.zip.bak');
        seed(dir, 'notes.zip');
        Directory('${dir.path}/${nm('A', 2, t: '010101')}').createSync();
        Link('${dir.path}/${nm('A', 3, t: '010101')}')
            .createSync('${dir.path}/notes.zip');

        final out = await DiagnosticExportService.saveZipUnique(
            dir, Uint8List.fromList([1]), DateTime(2026, 11, 5, 9, 30, 15),
            label: 'A');

        final names = dir.listSync().map((e) => e.path.split('/').last).toSet();
        // New + days 7,6,5,4 survive; days 1-3 pruned.
        for (final d in [4, 5, 6, 7]) {
          expect(names, contains(nm('A', d)));
        }
        for (final d in [1, 2, 3]) {
          expect(names, isNot(contains(nm('A', d))));
        }
        expect(names, contains(out.split('/').last));
        expect(names, contains(nm('B', 1)));
        expect(names, contains('alochi_diagnostika_A_notadate.zip'));
        expect(names,
            contains('alochi_diagnostika_A_2026-10-01_090000.zip.bak'));
        expect(names, contains('notes.zip'));
        // subdirectory and symlink with a matching name are never touched.
        expect(Directory('${dir.path}/${nm('A', 2, t: '010101')}').existsSync(),
            isTrue);
        expect(
            FileSystemEntity.isLinkSync('${dir.path}/${nm('A', 3, t: '010101')}'),
            isTrue);
      });

      test('orders by name timestamp, -N suffix is newer than the bare name',
          () async {
        final dir = await tmp();
        final now = DateTime(2026, 11, 5, 9, 30, 15);
        for (var i = 0; i < 6; i++) {
          await DiagnosticExportService.saveZipUnique(
              dir, Uint8List.fromList([i]), now,
              label: 'A');
        }
        final names = dir.listSync().map((e) => e.path.split('/').last).toList()
          ..sort();
        expect(names, hasLength(5));
        // oldest (bare name) pruned, -2..-6 kept
        expect(names, isNot(contains('alochi_diagnostika_A_2026-11-05_093015.zip')));
        expect(names, contains('alochi_diagnostika_A_2026-11-05_093015-6.zip'));
      });

      test('no label -> no pruning', () async {
        final dir = await tmp();
        for (var d = 1; d <= 7; d++) {
          seed(dir, 'alochi_diagnostika_2026-10-0${d}_090000.zip');
        }
        await DiagnosticExportService.saveZipUnique(
            dir, Uint8List.fromList([1]), DateTime(2026, 11, 5, 9, 30, 15));
        expect(dir.listSync(), hasLength(8));
      });

      test('failing delete never fails the export and keeps the new file',
          () async {
        final dir = await tmp();
        for (var d = 1; d <= 7; d++) {
          seed(dir, nm('A', d));
        }
        DiagnosticExportService.deleteExportFile = (f) async {
          throw const FileSystemException('denied');
        };
        addTearDown(() => DiagnosticExportService.deleteExportFile =
            DiagnosticExportService.defaultDeleteExportFile);
        final out = await DiagnosticExportService.saveZipUnique(
            dir, Uint8List.fromList([1]), DateTime(2026, 11, 5, 9, 30, 15),
            label: 'A');
        expect(File(out).existsSync(), isTrue);
        expect(dir.listSync(), hasLength(8));
      });

      test('prunes only the directory written to', () async {
        final a = await tmp();
        final b = await tmp();
        for (var d = 1; d <= 7; d++) {
          seed(a, nm('A', d));
          seed(b, nm('A', d));
        }
        await DiagnosticExportService.saveZipUnique(
            a, Uint8List.fromList([1]), DateTime(2026, 11, 5, 9, 30, 15),
            label: 'A');
        expect(a.listSync(), hasLength(5));
        expect(b.listSync(), hasLength(7));
      });

      test('label with regex metacharacters matches literally', () async {
        final dir = await tmp();
        // sanitised label "5.6" must not match "5x6" files.
        for (var d = 1; d <= 6; d++) {
          seed(dir, nm('5x6', d));
        }
        await DiagnosticExportService.saveZipUnique(
            dir, Uint8List.fromList([1]), DateTime(2026, 11, 5, 9, 30, 15),
            label: '5.6');
        expect(dir.listSync(), hasLength(7));
      });
    });
  });
}
