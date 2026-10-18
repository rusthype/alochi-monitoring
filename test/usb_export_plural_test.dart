import 'package:alochi_monitoring/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usbExportDone ru plural', () {
    final l = AppLocalizationsRu();
    expect(l.usbExportDone(1, 'f'), contains('1 результат ('));
    expect(l.usbExportDone(2, 'f'), contains('2 результата'));
    expect(l.usbExportDone(5, 'f'), contains('5 результатов'));
    expect(l.usbExportDone(21, 'f'), contains('21 результат ('));
  });
}
