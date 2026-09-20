import 'package:alochi_monitoring/core/services/diagnostic_export_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticExportService.generateStudentPassportHtml', () {
    test('a "sent" record with both scores renders full passport with scores', () {
      final html = DiagnosticExportService.generateStudentPassportHtml({
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

    test('a low-scoring "sent" record gets the "Qayta mashq kerak" verdict', () {
      final html = DiagnosticExportService.generateStudentPassportHtml({
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

    test('a "pending" record (both scores null) renders the pending status block, no score UI', () {
      final html = DiagnosticExportService.generateStudentPassportHtml({
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
        () => DiagnosticExportService.generateStudentPassportHtml({
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
  });

  group('DiagnosticExportService.buildZipBytes', () {
    test('produces one HTML entry per record, named collision-safely', () {
      final bytes = DiagnosticExportService.buildZipBytes([
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
      DiagnosticExportService.buildZipBytes(
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
      final bytes = DiagnosticExportService.buildZipBytes(const []);
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.length, equals(0));
    });
  });
}
