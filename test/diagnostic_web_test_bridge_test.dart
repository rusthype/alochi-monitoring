import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';

void main() {
  group('parseDiagnosticClassRow', () {
    test('reads has_web_test/web_test_key when present', () {
      final row = parseDiagnosticClassRow({
        'class_label': '4-A',
        'language': 'uz',
        'has_web_test': true,
        'web_test_key': 'diag-bridge-whole-school',
      });
      expect(row['class_label'], '4-A');
      expect(row['has_web_test'], true);
      expect(row['web_test_key'], 'diag-bridge-whole-school');
    });

    test('defaults has_web_test to false and web_test_key to empty when absent',
        () {
      final row = parseDiagnosticClassRow({
        'class_label': '4-B',
        'language': 'uz',
      });
      expect(row['has_web_test'], false);
      expect(row['web_test_key'], '');
    });

    test('defaults safely for the legacy bare-string row shape', () {
      final row = parseDiagnosticClassRow('4-C');
      expect(row['class_label'], '4-C');
      expect(row['language'], 'uz');
      expect(row['has_web_test'], false);
      expect(row['web_test_key'], '');
    });
  });
}
