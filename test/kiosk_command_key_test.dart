// The committed kiosk force-update PUBLIC key (baked into the build via
// --dart-define=KIOSK_COMMAND_PUBKEY_B64 by the release workflows) must be a
// well-formed Ed25519 SPKI key, and must never be a private key.
import 'dart:io';

import 'package:alochi_monitoring/core/diagnostics/kiosk_command_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pem = File('kiosk_keys/command_public.pem').readAsStringSync();

  test('kiosk_keys/command_public.pem parses to a 32-byte Ed25519 key', () {
    expect(pem, isNot(contains('PRIVATE')));
    expect(parseEd25519PublicKey(pem)?.length, 32);
  });
}
