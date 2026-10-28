import 'dart:convert';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';

void main() {
  final key = enc.Key.fromSecureRandom(32);

  test('decryptWithKey reverses encryptWithKey for the same key', () {
    const original = '{"student_id":"A26-473","score":87}';
    final ciphertext = QueueCrypto.encryptWithKey(original, key);

    expect(ciphertext, isNot(equals(original)));
    expect(ciphertext.startsWith('ENC1:'), isTrue);
    expect(QueueCrypto.decryptWithKey(ciphertext, key), equals(original));
  });

  test('decryptWithKey returns legacy plaintext rows unchanged', () {
    const legacyRow = '{"student_id":"A26-473","score":87}'; // no ENC1: prefix
    expect(QueueCrypto.decryptWithKey(legacyRow, key), equals(legacyRow));
  });

  test('tampering with ciphertext makes decryption fail loudly', () {
    final ciphertext = QueueCrypto.encryptWithKey('{"score":100}', key);
    final tampered = '${ciphertext.substring(0, ciphertext.length - 4)}XXXX';
    expect(() => QueueCrypto.decryptWithKey(tampered, key), throwsA(anything));
  });

  group('resolveKeys (F3: never lose the key of queued results)', () {
    String b64(enc.Key k) => base64Encode(k.bytes);

    // In-memory stand-ins for the keychain and the fallback file.
    late String? store;
    late String? file;
    late bool storeThrows;
    late bool fileThrows;
    late List<String> writes;

    Future<QueueKeys> resolve() => QueueCrypto.resolveKeys(
          readStore: () async {
            if (storeThrows) throw StateError('keychain ACL');
            return store;
          },
          writeStore: (v) async {
            writes.add('store');
            store = v;
          },
          readFile: () async {
            if (fileThrows) throw StateError('no dir');
            return file;
          },
          writeFile: (v) async {
            writes.add('file');
            file = v;
          },
        );

    setUp(() {
      store = null;
      file = null;
      storeThrows = false;
      fileThrows = false;
      writes = [];
    });

    test('fresh install: one new key written to BOTH places', () async {
      final k = await resolve();
      expect(store, isNotNull);
      expect(file, store);
      expect(b64(k.primary), store);
    });

    test('keychain read fails: the old key from the file is used and the '
        'keychain is NOT overwritten', () async {
      final old = enc.Key.fromSecureRandom(32);
      file = b64(old);
      storeThrows = true;
      final row = QueueCrypto.encryptWithKey('{"s":1}', old);
      final k = await resolve();
      expect(QueueCrypto.decryptWithKeys(row, k.all), '{"s":1}');
      expect(writes, isEmpty);
    });

    test('only the keychain has the key: the file is re-created from it',
        () async {
      final old = enc.Key.fromSecureRandom(32);
      store = b64(old);
      final k = await resolve();
      expect(file, store);
      expect(b64(k.primary), store);
    });

    test('both places readable but different: rows of either decrypt',
        () async {
      final a = enc.Key.fromSecureRandom(32);
      final b = enc.Key.fromSecureRandom(32);
      store = b64(a);
      file = b64(b);
      final k = await resolve();
      expect(QueueCrypto.decryptWithKeys(QueueCrypto.encryptWithKey('A', a), k.all), 'A');
      expect(QueueCrypto.decryptWithKeys(QueueCrypto.encryptWithKey('B', b), k.all), 'B');
      expect(writes, isEmpty);
    });

    test('keychain unreadable + no file: new key goes to the file only; when '
        'the keychain returns, both keys decrypt', () async {
      final original = enc.Key.fromSecureRandom(32);
      final rowOld = QueueCrypto.encryptWithKey('old', original);
      storeThrows = true;
      final first = await resolve();
      expect(writes, ['file']);
      final rowNew = QueueCrypto.encryptWithKey('new', first.primary);

      storeThrows = false;
      store = b64(original); // keychain works again with the ORIGINAL key
      final second = await resolve();
      expect(QueueCrypto.decryptWithKeys(rowOld, second.all), 'old');
      expect(QueueCrypto.decryptWithKeys(rowNew, second.all), 'new');
    });

    test('nothing reachable: ephemeral key, nothing written, no throw',
        () async {
      storeThrows = true;
      fileThrows = true;
      final k = await resolve();
      expect(k.all, hasLength(1));
      expect(writes, isEmpty);
    });

    test('a row no key can decrypt throws (caller keeps the row)', () {
      final other = enc.Key.fromSecureRandom(32);
      final row = QueueCrypto.encryptWithKey('x', other);
      expect(() => QueueCrypto.decryptWithKeys(row, [key]), throwsA(anything));
    });
  });
}
