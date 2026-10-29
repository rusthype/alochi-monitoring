// F26/F28: verified temp+rename writes.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/offline/atomic_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('atomic_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  final data = Uint8List.fromList(List.generate(5000, (i) => i % 251));

  test('writes the exact bytes and leaves no temp file', () async {
    final f = File(p.join(tmp.path, 'a.bin'));
    await writeFileVerified(f, data);
    expect(f.readAsBytesSync(), data);
    expect(File('${f.path}.tmp').existsSync(), isFalse);
  });

  test('a short write (full / pulled USB stick) never reaches the real name',
      () async {
    final f = File(p.join(tmp.path, 'a.bin'));
    await expectLater(
        writeFileVerified(f, data,
            write: (t, b) => t.writeAsBytes(b.sublist(0, 100), flush: true)),
        throwsA(isA<FileSystemException>()));
    expect(f.existsSync(), isFalse);
    expect(File('${f.path}.tmp').existsSync(), isFalse);
  });

  test('a corrupted write of the right length is caught by the hash',
      () async {
    final f = File(p.join(tmp.path, 'a.bin'));
    await expectLater(
        writeFileVerified(f, data, write: (t, b) {
          final c = Uint8List.fromList(b)..[10] ^= 0xff;
          return t.writeAsBytes(c, flush: true);
        }),
        throwsA(isA<FileSystemException>()));
    expect(f.existsSync(), isFalse);
  });

  test('a failed write keeps the previous file intact', () async {
    final f = File(p.join(tmp.path, 'a.bin'))..writeAsBytesSync([1, 2, 3]);
    await expectLater(
        writeFileVerified(f, data,
            write: (t, b) => t.writeAsBytes(b.sublist(0, 7), flush: true)),
        throwsA(isA<FileSystemException>()));
    expect(f.readAsBytesSync(), [1, 2, 3]);
  });

  test('cleanStrayTemps removes only .tmp files', () async {
    File(p.join(tmp.path, 'x.jpg.tmp')).writeAsBytesSync([1]);
    File(p.join(tmp.path, 'x.jpg')).writeAsBytesSync([1]);
    await cleanStrayTemps(tmp);
    expect(File(p.join(tmp.path, 'x.jpg.tmp')).existsSync(), isFalse);
    expect(File(p.join(tmp.path, 'x.jpg')).existsSync(), isTrue);
  });
}
