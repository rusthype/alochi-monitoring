import 'package:alochi_monitoring/core/services/diagnostic_export_service.dart';
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
}
