// lib/core/diagnostics/kiosk_command_auth.dart
//
// Authenticity checks for admin commands received over the device WebSocket.
// Fail-closed: no key / bad key / bad signature / wrong device / expired /
// replayed => the command is ignored. Build the app with
//
//   --dart-define=KIOSK_COMMAND_PUBKEY_B64=$(base64 -w0 < kiosk_cmd_public.pem)
//
// Without that define the remote-command feature is inert.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Ed25519 verification primitive: true iff [sig] (64 bytes) is a valid
/// signature of [message] under [publicKey] (32 bytes).
typedef Ed25519Verify = Future<bool> Function(
    Uint8List publicKey, Uint8List message, Uint8List sig);

const String _pubKeyB64 = String.fromEnvironment('KIOSK_COMMAND_PUBKEY_B64');

/// Canonical signed string. SINGLE source of truth, must stay byte-identical
/// to the backend: `kiosk-cmd-v1|<command>|<request_id>|<device_id>|<sent_at>|<expires_at>`
/// (UTF-8; timestamps are the exact strings from the message).
String kioskCommandCanonical({
  required String command,
  required String requestId,
  required String deviceId,
  required String sentAt,
  required String expiresAt,
}) =>
    'kiosk-cmd-v1|$command|$requestId|$deviceId|$sentAt|$expiresAt';

/// 32-byte Ed25519 key from an SPKI PEM (raw PEM or base64(PEM)); null if the
/// input is empty or not an Ed25519 SubjectPublicKeyInfo.
Uint8List? parseEd25519PublicKey(String raw) {
  try {
    var v = raw.trim();
    if (v.isEmpty) return null;
    if (!v.startsWith('-----')) {
      v = utf8.decode(base64.decode(base64.normalize(v)));
    }
    final der = base64.decode(v
        .replaceAll(RegExp(r'-----(BEGIN|END)[^-]*-----'), '')
        .replaceAll(RegExp(r'\s+'), ''));
    // 302a 3005 0603 2b6570 0321 00 || key(32)
    const prefix = [
      0x30,
      0x2a,
      0x30,
      0x05,
      0x06,
      0x03,
      0x2b,
      0x65,
      0x70,
      0x03,
      0x21,
      0x00
    ];
    if (der.length != 44) return null;
    for (var i = 0; i < prefix.length; i++) {
      if (der[i] != prefix[i]) return null;
    }
    return Uint8List.fromList(der.sublist(12));
  } catch (_) {
    return null;
  }
}

/// Production key from the dart-define (null = feature inert).
Uint8List? kioskCommandPublicKeyFromEnvironment() =>
    parseEd25519PublicKey(_pubKeyB64);

/// Real Ed25519 verification (pure Dart, package:cryptography).
Future<bool> ed25519Verify(
        Uint8List publicKey, Uint8List message, Uint8List sig) =>
    Ed25519().verify(
      message,
      signature: Signature(
        sig,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );

/// Returns null if [msg] is an authentic, current command for [ownDeviceId];
/// otherwise a short reason code (safe to log). Does not check replays.
Future<String?> checkCommandAuth(
  Map msg, {
  required Uint8List? publicKey,
  required String ownDeviceId,
  required DateTime now,
  required Ed25519Verify verify,
  Duration maxFutureSkew = const Duration(minutes: 10),
}) async {
  if (publicKey == null) return 'no_pubkey';
  final command = msg['command'];
  final requestId = msg['request_id'];
  final deviceId = msg['device_id'];
  final sentAt = msg['sent_at'];
  final expiresAt = msg['expires_at'];
  final sig = msg['sig'];
  if (command is! String ||
      requestId is! String ||
      deviceId is! String ||
      sentAt is! String ||
      expiresAt is! String ||
      sig is! String) {
    return 'missing_field';
  }
  if (ownDeviceId.isEmpty || deviceId != ownDeviceId) return 'device_mismatch';
  final sent = DateTime.tryParse(sentAt);
  final exp = DateTime.tryParse(expiresAt);
  if (sent == null || exp == null) return 'bad_time';
  final n = now.toUtc();
  if (!exp.toUtc().isAfter(n)) return 'expired';
  if (sent.toUtc().isAfter(n.add(maxFutureSkew))) return 'sent_in_future';
  Uint8List sigBytes;
  try {
    sigBytes = base64Url.decode(base64Url.normalize(sig));
  } catch (_) {
    return 'bad_sig_encoding';
  }
  if (sigBytes.length != 64) return 'bad_sig_length';
  final canonical = kioskCommandCanonical(
    command: command,
    requestId: requestId,
    deviceId: deviceId,
    sentAt: sentAt,
    expiresAt: expiresAt,
  );
  try {
    if (!await verify(
        publicKey, Uint8List.fromList(utf8.encode(canonical)), sigBytes)) {
      return 'bad_signature';
    }
  } catch (_) {
    return 'verify_error';
  }
  return null;
}
