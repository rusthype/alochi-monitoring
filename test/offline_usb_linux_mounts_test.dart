import 'package:alochi_monitoring/core/offline/usb_backup.dart';
import 'package:flutter_test/flutter_test.dart';

// Trimmed from a real Debian /proc/self/mountinfo (+ a typical USB stick).
const _mountinfo = r'''
31 1 8:7 / / rw,relatime shared:1 - ext4 /dev/sda7 rw,errors=remount-ro
49 31 8:6 / /boot/efi rw,relatime shared:88 - vfat /dev/sda6 rw
299 31 8:5 / /media/max/DATA rw,relatime shared:517 - ntfs3 /dev/sda5 rw
579 299 0:82 / /media/max/DATA/docker/overlayfs/abc rw - overlay overlay rw
700 31 8:17 / /media/max/FLASH\040DISK rw,nosuid,nodev - vfat /dev/sdb1 rw
701 31 8:33 / /run/media/max/STICK rw - exfat /dev/sdc1 rw
702 31 8:49 / /mnt/usb rw - ext4 /dev/sdd1 rw
703 31 8:65 / /mnt/nested/deeper rw - ext4 /dev/sde1 rw
704 31 0:90 / /media/max/NET rw - cifs //server/share rw
garbage line without separator
''';

void main() {
  test('keeps only USB/removable devices in auto-mount dirs', () {
    const flash = {'sdb1', 'sdc1', 'sdd1', 'sde1'};
    final got = parseLinuxRemovables(_mountinfo,
        isFlashDevice: (d) => flash.contains(d));
    expect(got, [
      '/media/max/FLASH DISK', // octal escape decoded
      '/mnt/usb',
      '/run/media/max/STICK',
    ]);
  });

  test('internal disk under /media is skipped when not flash', () {
    final got = parseLinuxRemovables(_mountinfo, isFlashDevice: (_) => false);
    expect(got, isEmpty);
  });

  test('a throwing probe skips that mount only', () {
    final got = parseLinuxRemovables(_mountinfo, isFlashDevice: (d) {
      if (d == 'sdb1') throw StateError('sysfs');
      return d == 'sdc1';
    });
    expect(got, ['/run/media/max/STICK']);
  });

  test('empty / unparsable input', () {
    expect(parseLinuxRemovables('', isFlashDevice: (_) => true), isEmpty);
  });
}
