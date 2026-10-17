// Cross-language test: the backend-generated golden `.alochipack`
// (PIN 12345678) must open and match golden.expected.json byte for byte.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/offline/offline_crypto.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/fixtures/offline';

Uint8List _bytes(String name) => File('$_dir/$name').readAsBytesSync();

Uint8List _repack(Map<String, Uint8List?> overrides) {
  final src = ZipDecoder().decodeBytes(_bytes('golden.alochipack'));
  final out = Archive();
  for (final f in src.files) {
    if (!f.isFile) continue;
    final o = overrides.containsKey(f.name) ? overrides[f.name] : f.readBytes();
    if (o == null) continue; // removed
    out.addFile(ArchiveFile.noCompress(f.name, o.length, o));
  }
  for (final e in overrides.entries) {
    if (src.files.every((f) => f.name != e.key) && e.value != null) {
      out.addFile(ArchiveFile.noCompress(e.key, e.value!.length, e.value!));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}

void main() {
  final keys = OfflineKeys(
    signingPem: File('$_dir/test_signing_public.pem').readAsStringSync(),
    resultsPem: File('$_dir/test_results_public.pem').readAsStringSync(),
  );
  final expected =
      jsonDecode(File('$_dir/golden.expected.json').readAsStringSync())
          as Map<String, dynamic>;
  PackLoader loader({DateTime? now}) =>
      PackLoader(keys: keys, now: now == null ? null : () => now);

  test('PBKDF2 matches the Python reference vector', () {
    // python: hashlib.pbkdf2_hmac('sha256', b'12345678', bytes(range(16)), 1000, 32)
    final k = OfflineCrypto.deriveKey(
        '12345678', Uint8List.fromList(List.generate(16, (i) => i)), 1000);
    expect(k.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '42b99a197a7d9cafa9fa5b60091da410edb6f3c1cc4e159a5f901b5348abb716');
  });

  test('golden pack opens with PIN 12345678 and matches expected content',
      () async {
    final tmp = Directory.systemTemp.createTempSync('pack_media_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final pack = await loader()
        .open(_bytes('golden.alochipack'), '12345678', mediaDir: tmp);

    expect(pack.packUuid, expected['pack_uuid']);
    expect(pack.schoolCode, '999');
    final content = expected['content'] as Map<String, dynamic>;
    expect(pack.tests, content['tests']);
    expect(pack.groups, content['groups']);
    expect(pack.students, content['students']);
    expect(pack.chainKey.length, 32);

    final mediaName = (expected['media_member'] as String).split('/').last;
    expect(File('${tmp.path}/$mediaName').existsSync(), isTrue);
    // No answer key leaked into the decrypted content.
    expect(jsonEncode(pack.tests).contains('"ans"'), isFalse);
  });

  test('wrong PIN is rejected with wrongPin', () async {
    final archive = loader().inspect(_bytes('golden.alochipack'));
    expect(
      () => loader().unlock(archive, '00000000'),
      throwsA(isA<PackException>()
          .having((e) => e.code, 'code', PackError.wrongPin)),
    );
  });

  test('tampered manifest -> badSignature', () {
    final m = _bytes('golden.alochipack');
    final zip = ZipDecoder().decodeBytes(m);
    final manifest = zip.files.firstWhere((f) => f.name == 'manifest.json');
    final text = utf8.decode(manifest.readBytes()!).replaceAll('999', '998');
    final bad =
        _repack({'manifest.json': Uint8List.fromList(utf8.encode(text))});
    expect(
      () => loader().inspect(bad),
      throwsA(isA<PackException>()
          .having((e) => e.code, 'code', PackError.badSignature)),
    );
  });

  test('corrupted signature -> badSignature', () {
    final sig = Uint8List.fromList(ZipDecoder()
        .decodeBytes(_bytes('golden.alochipack'))
        .files
        .firstWhere((f) => f.name == 'manifest.sig')
        .readBytes()!);
    sig[10] ^= 0xff;
    expect(
      () => loader().inspect(_repack({'manifest.sig': sig})),
      throwsA(isA<PackException>()
          .having((e) => e.code, 'code', PackError.badSignature)),
    );
  });

  test('expired pack -> expired (signature is valid)', () {
    expect(
      () => loader(now: DateTime.utc(2100, 1, 1))
          .inspect(_bytes('golden.alochipack')),
      throwsA(isA<PackException>()
          .having((e) => e.code, 'code', PackError.expired)),
    );
  });

  test('tampered content.json.enc -> hashMismatch', () {
    final enc = Uint8List.fromList(ZipDecoder()
        .decodeBytes(_bytes('golden.alochipack'))
        .files
        .firstWhere((f) => f.name == 'content.json.enc')
        .readBytes()!);
    enc[20] ^= 0x01;
    expect(
      () => loader().inspect(_repack({'content.json.enc': enc})),
      throwsA(isA<PackException>()
          .having((e) => e.code, 'code', PackError.hashMismatch)),
    );
  });

  test('unknown / path-traversal member name -> unsafeName', () {
    expect(
      () => loader().inspect(_repack({
        '../evil.txt': Uint8List.fromList([1, 2, 3])
      })),
      throwsA(isA<PackException>()
          .having((e) => e.code, 'code', PackError.unsafeName)),
    );
  });

  test('no keys configured -> notConfigured', () {
    expect(
      () => PackLoader(keys: const OfflineKeys())
          .inspect(_bytes('golden.alochipack')),
      throwsA(isA<PackException>()
          .having((e) => e.code, 'code', PackError.notConfigured)),
    );
    expect(const OfflineKeys().isConfigured, isFalse);
    expect(keys.isConfigured, isTrue);
  });
}
