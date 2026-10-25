import 'dart:io';

import 'package:alochi_monitoring/core/offline/usb_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('selectFlashDrives: removable, USB-bus fixed; not system/non-USB/empty',
      () {
    const types = {
      'C:\\': 3, // system, fixed, usb-looking -> excluded
      'D:\\': 3, // fixed, not usb -> excluded
      'E:\\': 2, // removable -> kept
      'F:\\': 3, // fixed on usb -> kept
      'G:\\': 3, // fixed on usb, no media -> excluded
      'H:\\': 3, // probe throws -> skipped
    };
    final got = selectFlashDrives(
      types.keys.toList(),
      driveType: (r) => types[r]!,
      hasMedia: (r) => r != 'G:\\',
      isUsbBus: (r) {
        if (r == 'H:\\') throw StateError('ioctl');
        return r != 'D:\\';
      },
      systemDrive: 'c:',
    );
    expect(got, ['E:\\', 'F:\\']);
  });

  test('listMacVolumes: keeps real dirs, drops boot symlink + hidden', () {
    final root = Directory.systemTemp.createTempSync('vols');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory(p.join(root.path, 'FLASH')).createSync();
    Directory(p.join(root.path, '.hidden')).createSync();
    Link(p.join(root.path, 'Macintosh HD')).createSync('/');
    File(p.join(root.path, 'stray.txt')).writeAsStringSync('x');

    expect(listMacVolumes(root.path), [p.join(root.path, 'FLASH')]);
    expect(listMacVolumes(p.join(root.path, 'missing')), isEmpty);
  });
}
