import 'package:alochi_monitoring/features/offline/safe_file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hasLinuxDialogTool finds qarma/zenity/kdialog on PATH only', () {
    bool only(String path) => path == '/usr/bin/zenity';
    expect(hasLinuxDialogTool('/bin:/usr/bin', exists: only), isTrue);
    expect(hasLinuxDialogTool('/bin:/usr/local/bin', exists: only), isFalse);
    expect(hasLinuxDialogTool('', exists: (_) => true), isFalse);
    expect(hasLinuxDialogTool(null, exists: (_) => true), isFalse);
    expect(
        hasLinuxDialogTool('/usr/bin', exists: (f) => f == '/usr/bin/kdialog'),
        isTrue);
  });
}
