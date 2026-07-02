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
}
