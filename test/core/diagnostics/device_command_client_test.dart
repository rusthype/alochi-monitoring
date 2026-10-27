import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/diagnostics/active_test_gate.dart';
import 'package:alochi_monitoring/core/diagnostics/device_command_client.dart';
import 'package:alochi_monitoring/core/diagnostics/kiosk_command_auth.dart';
import 'package:alochi_monitoring/core/services/update_service.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeChannel implements CommandChannel {
  final incoming = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  void add(String message) => sent.add(jsonDecode(message));
  @override
  Future<void> close() async {
    if (!incoming.isClosed) await incoming.close();
  }

  void server(Object? m) => incoming.add(m is String ? m : jsonEncode(m));
  List<String> get acks => [for (final s in sent) s['status'] as String];
}

const _info = UpdateInfo(
  latestVersion: '9.9.9',
  currentVersion: '1.0.0',
  downloadUrl: 'https://example.invalid/x',
);

final _key = Uint8List.fromList(List.filled(32, 9));

/// Stand-in for Ed25519 that still binds the signature to key + message, so
/// tampering is detectable: sig = sha256(key || msg) repeated to 64 bytes.
Uint8List _fakeSig(Uint8List key, Uint8List msg) {
  final h = crypto.sha256.convert([...key, ...msg]).bytes;
  return Uint8List.fromList([...h, ...h]);
}

Future<bool> _fakeVerify(Uint8List key, Uint8List msg, Uint8List sig) async {
  final e = _fakeSig(key, msg);
  if (sig.length != e.length) return false;
  for (var i = 0; i < e.length; i++) {
    if (sig[i] != e[i]) return false;
  }
  return true;
}

/// A correctly "signed" command for device 'd'. [tamper] changes a field
/// AFTER signing.
Map<String, dynamic> cmd(
  String id, {
  String command = 'force_update',
  String device = 'd',
  Duration sentAgo = Duration.zero,
  Duration validFor = const Duration(hours: 1),
  Map<String, dynamic> tamper = const {},
  bool sign = true,
}) {
  final now = DateTime.now().toUtc();
  final sent = now.subtract(sentAgo).toIso8601String();
  final exp = now.add(validFor).toIso8601String();
  final canon = kioskCommandCanonical(
      command: command,
      requestId: id,
      deviceId: device,
      sentAt: sent,
      expiresAt: exp);
  final m = <String, dynamic>{
    'type': 'command',
    'command': command,
    'request_id': id,
    'device_id': device,
    'sent_at': sent,
    'expires_at': exp,
    if (sign)
      'sig': base64Url
          .encode(_fakeSig(_key, Uint8List.fromList(utf8.encode(canon)))),
  };
  return {...m, ...tamper};
}

Future<void> pump() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Sleep fake: zero-duration sleeps complete, everything else parks forever
/// (keeps the reconnect loop from spinning while a channel is closed).
Future<void> parkingSleep(Duration d) =>
    d == Duration.zero ? Future<void>.value() : Completer<void>().future;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('url', () {
    test('https -> wss, http -> ws, device_id query, port kept', () {
      expect(
          DeviceCommandClient.buildUri('https://api.alochi.org', 'abc-1')
              .toString(),
          'wss://api.alochi.org/ws/kiosk/device/?device_id=abc-1');
      expect(
          DeviceCommandClient.buildUri('http://10.0.0.5:8000', 'abc-1')
              .toString(),
          'ws://10.0.0.5:8000/ws/kiosk/device/?device_id=abc-1');
      expect(DeviceCommandClient.buildUri('https://api.alochi.org', ''), null);
    });

    test('connects with the device id from the injected source', () async {
      Uri? seen;
      late DeviceCommandClient c;
      c = DeviceCommandClient(
        deviceId: () async => 'dev-42',
        connect: (u) async {
          seen = u;
          unawaited(c.stop());
          throw const SocketException('x');
        },
        sleep: parkingSleep,
      );
      c.start();
      await pump();
      expect(seen.toString(),
          'wss://api.alochi.org/ws/kiosk/device/?device_id=dev-42');
    });
  });

  group('reconnect', () {
    test('backoff doubles 5s -> 300s cap and stays at the cap', () async {
      final delays = <Duration>[];
      late DeviceCommandClient c;
      c = DeviceCommandClient(
        random: () => 0,
        deviceId: () async => 'd',
        connect: (_) async => throw const SocketException('down'),
        sleep: (d) async {
          delays.add(d);
          if (delays.length == 9) await c.stop();
        },
      );
      c.start();
      await pump();
      expect(delays.map((d) => d.inSeconds).toList(),
          [5, 10, 20, 40, 80, 160, 300, 300, 300]);
    });

    test('jitter never exceeds the cap', () {
      final c = DeviceCommandClient(random: () => 0.999);
      for (var i = 0; i < 30; i++) {
        expect(c.backoff(i) <= DeviceCommandClient.maxDelay, isTrue);
      }
      expect(c.backoff(0).inMilliseconds, lessThan(5000));
    });

    test('rejected handshake goes straight to the cap, quietly', () async {
      final delays = <Duration>[];
      late DeviceCommandClient c;
      c = DeviceCommandClient(
        random: () => 0,
        deviceId: () async => 'd',
        connect: (_) async =>
            throw const WebSocketException('was not upgraded to websocket'),
        sleep: (d) async {
          delays.add(d);
          if (delays.length == 3) await c.stop();
        },
      );
      c.start();
      await pump();
      expect(delays.map((d) => d.inSeconds).toList(), [300, 300, 300]);
    });

    test('stable connection resets the backoff, flapping one does not',
        () async {
      var t = DateTime(2026);
      final delays = <Duration>[];
      final chans = <FakeChannel>[];
      late DeviceCommandClient c;
      c = DeviceCommandClient(
        random: () => 0,
        deviceId: () async => 'd',
        now: () => t,
        connect: (_) async {
          final ch = FakeChannel();
          chans.add(ch);
          return ch;
        },
        sleep: (d) async {
          delays.add(d);
          if (delays.length == 3) await c.stop();
        },
      );
      c.start();
      await pump();
      chans[0].incoming.close(); // dies instantly: attempt 0 -> 5s
      await pump();
      chans[1].incoming.close(); // dies instantly again: attempt 1 -> 10s
      await pump();
      t = t.add(const Duration(minutes: 1));
      chans[2].incoming.close(); // lived a minute: reset, next delay is 5s
      await pump();
      expect(delays.map((d) => d.inSeconds).toList(), [5, 10, 5]);
    });

    test('not connecting while shouldConnect is false (offline pack)',
        () async {
      var connects = 0;
      var sleeps = 0;
      late DeviceCommandClient c;
      c = DeviceCommandClient(
        shouldConnect: () => false,
        deviceId: () async => 'd',
        connect: (_) async {
          connects++;
          throw const SocketException('x');
        },
        sleep: (d) async {
          if (++sleeps == 3) await c.stop();
        },
      );
      c.start();
      await pump();
      expect(connects, 0);
      expect(sleeps, 3);
    });
  });

  group('commands', () {
    late FakeChannel ch;
    late ValueNotifier<bool> gate;
    late int checks;
    late List<int> installs; // sent.length at the moment of install
    UpdateInfo? available;
    UpdateResult result = const UpdateResult.success();
    late DeviceCommandClient c;

    Future<void> boot({bool testRunning = false}) async {
      ch = FakeChannel();
      gate = ValueNotifier(testRunning);
      checks = 0;
      installs = [];
      available = testRunning ? _info : null;
      result = const UpdateResult.success();
      c = DeviceCommandClient(
        deviceId: () async => 'd',
        commandPublicKey: _key,
        verifySignature: _fakeVerify,
        connect: (_) async => ch,
        sleep: parkingSleep,
        deferredGrace: Duration.zero,
        testGate: gate,
        checkUpdate: () async {
          checks++;
          return available;
        },
        installUpdate: (i) async {
          installs.add(ch.sent.length);
          return result;
        },
      );
      c.start();
      await pump();
    }

    tearDown(() async => c.stop());

    test('no newer version -> up_to_date, nothing installed', () async {
      await boot();
      ch.server(cmd('r1'));
      await pump();
      expect(ch.acks, ['up_to_date']);
      expect(ch.sent.single['request_id'], 'r1');
      expect(ch.sent.single['type'], 'ack');
      expect(installs, isEmpty);
    });

    test('newer + idle -> updating acked BEFORE a single install', () async {
      await boot();
      available = _info;
      ch.server(cmd('r2'));
      await pump();
      expect(ch.acks, ['updating']);
      expect(installs, [1]); // the ack was already sent when install ran
    });

    test('failed install -> updating then failed', () async {
      await boot();
      available = _info;
      result = const UpdateResult.failed('boom');
      ch.server(cmd('r3'));
      await pump();
      expect(ch.acks, ['updating', 'failed']);
    });

    test('newer + test running -> deferred, runs once when gate clears',
        () async {
      await boot();
      available = _info;
      gate.value = true;
      ch.server(cmd('r4'));
      await pump();
      expect(ch.acks, ['deferred']);
      expect(installs, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPendingForceUpdateKey), 'r4');

      gate.value = false;
      await pump();
      expect(installs.length, 1);
      expect(ch.acks, ['deferred', 'updating']);
      expect(prefs.getString(kPendingForceUpdateKey), isNull);

      gate.value = true;
      gate.value = false;
      await pump();
      expect(installs.length, 1);
    });

    test('redelivery of a deferred request is idempotent', () async {
      await boot();
      available = _info;
      gate.value = true;
      final m = cmd('rd1');
      ch.server(m);
      await pump();
      ch.server(m); // server resends on every reconnect while deferred
      await pump();
      ch.server(m);
      await pump();
      expect(ch.acks, ['deferred', 'deferred', 'deferred']);
      expect(installs, isEmpty);
      expect(checks, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPendingForceUpdateKey), 'rd1');

      gate.value = false; // the post-gate update must still happen, once
      await pump();
      expect(installs.length, 1);
      ch.server(m); // late redelivery after the update started
      await pump();
      expect(installs.length, 1);
      expect(ch.acks.last, 'updating');
    });

    test('redelivery after a restart while pending re-acks deferred', () async {
      SharedPreferences.setMockInitialValues({
        kPendingForceUpdateKey: 'rs1',
        kSeenCommandIdsKey: jsonEncode(['rs1']),
      });
      await boot(testRunning: true); // restored pending waits for the gate
      ch.server(cmd('rs1'));
      await pump();
      expect(ch.acks, ['deferred']);
      expect(installs, isEmpty);
    });

    test('gate flips back before the grace ends -> keeps waiting', () async {
      await boot();
      available = _info;
      gate.value = true;
      ch.server(cmd('r5'));
      await pump();
      gate.value = false;
      gate.value = true; // new test started immediately
      await pump();
      expect(installs, isEmpty);
      gate.value = false;
      await pump();
      expect(installs.length, 1);
    });

    test('duplicate request_id is ignored', () async {
      await boot();
      ch.server(cmd('dup'));
      await pump();
      ch.server(cmd('dup'));
      await pump();
      // Redelivery re-states the answer but never re-runs the check/update.
      expect(ch.acks, ['up_to_date', 'up_to_date']);
      expect(checks, 1);
      expect(installs, isEmpty);
    });

    test('malformed / unknown / oversize / binary input is ignored', () async {
      await boot();
      ch.server('not json {');
      ch.server('[1,2]');
      ch.server(cmd('x1', command: 'wipe_disk'));
      ch.server({'type': 'ack', 'request_id': 'x2'});
      ch.server({'type': 'command', 'command': 'force_update'});
      ch.server(cmd('has space and <bad>'));
      ch.server(cmd('a' * 65));
      ch.server({...cmd('big'), 'pad': 'z' * 5000});
      ch.incoming.add(<int>[1, 2, 3]);
      ch.incoming.add(42);
      // A url smuggled into a valid command must have no effect.
      ch.server({...cmd('ok'), 'url': 'https://evil.example/x.exe'});
      await pump();
      expect(ch.acks, ['up_to_date']); // only the one valid command
      expect(checks, 1);
      expect(installs, isEmpty);
    });

    test('pending command survives a restart and runs once idle', () async {
      SharedPreferences.setMockInitialValues({kPendingForceUpdateKey: 'old1'});
      ch = FakeChannel();
      gate = ValueNotifier(false);
      installs = [];
      c = DeviceCommandClient(
        deviceId: () async => 'd',
        commandPublicKey: _key,
        verifySignature: _fakeVerify,
        connect: (_) async => ch,
        sleep: parkingSleep,
        deferredGrace: Duration.zero,
        testGate: gate,
        checkUpdate: () async => _info,
        installUpdate: (i) async {
          installs.add(1);
          return const UpdateResult.success();
        },
      );
      c.start();
      await pump();
      expect(installs.length, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPendingForceUpdateKey), isNull);
    });
  });

  group('authenticity (fail-closed)', () {
    late FakeChannel ch;
    late int checks;
    late DeviceCommandClient c;

    Future<void> boot({bool withKey = true}) async {
      ch = FakeChannel();
      checks = 0;
      c = DeviceCommandClient(
        deviceId: () async => 'd',
        commandPublicKey: withKey ? _key : null,
        verifySignature: _fakeVerify,
        connect: (_) async => ch,
        sleep: parkingSleep,
        deferredGrace: Duration.zero,
        testGate: ValueNotifier(false),
        checkUpdate: () async {
          checks++;
          return null;
        },
        installUpdate: (i) async => const UpdateResult.success(),
      );
      c.start();
      await pump();
    }

    tearDown(() async => c.stop());

    Future<void> expectIgnored(Map<String, dynamic> m) async {
      ch.server(m);
      await pump();
      expect(ch.sent, isEmpty);
      expect(checks, 0);
    }

    test('valid signature accepted', () async {
      await boot();
      ch.server(cmd('ok1'));
      await pump();
      expect(ch.acks, ['up_to_date']);
    });

    test('tampered field is ignored', () async {
      await boot();
      await expectIgnored(
          cmd('t1', tamper: {'expires_at': '2099-01-01T00:00:00Z'}));
      await expectIgnored(cmd('t2', tamper: {'request_id': 't2-other'}));
    });

    test('wrong device_id is ignored (even if validly signed)', () async {
      await boot();
      await expectIgnored(cmd('w1', device: 'someone-else'));
    });

    test('expired is ignored', () async {
      await boot();
      await expectIgnored(cmd('e1',
          sentAgo: const Duration(hours: 2),
          validFor: -const Duration(hours: 1)));
    });

    test('sent_at far in the future is ignored', () async {
      await boot();
      await expectIgnored(cmd('f1', sentAgo: -const Duration(minutes: 11)));
    });

    test('bad / missing signature is ignored', () async {
      await boot();
      await expectIgnored(
          cmd('b1', tamper: {'sig': base64Url.encode(List.filled(64, 1))}));
      await expectIgnored(cmd('b2', tamper: {'sig': '!!!'}));
      await expectIgnored(cmd('b3', tamper: {'sig': 'AAAA'}));
      await expectIgnored(cmd('b4', sign: false));
    });

    test('no public key configured -> inert', () async {
      await boot(withKey: false);
      await expectIgnored(cmd('n1'));
    });

    test('default (real Ed25519) verifier rejects a non-Ed25519 signature',
        () async {
      ch = FakeChannel();
      checks = 0;
      c = DeviceCommandClient(
        deviceId: () async => 'd',
        commandPublicKey: _key,
        connect: (_) async => ch,
        sleep: parkingSleep,
        checkUpdate: () async {
          checks++;
          return null;
        },
      );
      c.start();
      await pump();
      await expectIgnored(cmd('d1'));
    });

    test('replay is ignored, also after a restart', () async {
      await boot();
      final m = cmd('rp1');
      ch.server(m);
      await pump();
      expect(ch.acks, ['up_to_date']);
      await c.stop();
      await boot(); // same prefs, fresh client
      await expectIgnored(m);
    });

    test('only the last 20 ids are remembered', () async {
      await boot();
      for (var i = 0; i < 22; i++) {
        ch.server(cmd('id$i'));
        await pump();
      }
      final p = await SharedPreferences.getInstance();
      final l = jsonDecode(p.getString(kSeenCommandIdsKey)!) as List;
      expect(l.length, 20);
      expect(l.last, 'id21');
    });
  });

  group('shared backend vector (real Ed25519)', () {
    final v = jsonDecode(
            File('test/fixtures/kiosk_cmd_vector.json').readAsStringSync())
        as Map<String, dynamic>;
    final key = parseEd25519PublicKey(v['public_key_pem'])!;
    final at = DateTime.utc(2026, 1, 3);
    Map<String, dynamic> msg() => Map<String, dynamic>.from(v['message']);
    Uint8List canon() => Uint8List.fromList(utf8.encode(v['canonical']));
    Uint8List sig() => Uint8List.fromList(
        base64Url.decode(base64Url.normalize(v['sig'] as String)));

    test('canonical string and key parsing match the backend', () {
      expect(
          kioskCommandCanonical(
              command: v['command'],
              requestId: v['request_id'],
              deviceId: v['device_id'],
              sentAt: v['sent_at'],
              expiresAt: v['expires_at']),
          v['canonical']);
      expect(key.length, 32);
      expect(parseEd25519PublicKey(v['public_key_pem_b64'])!, key);
      expect(parseEd25519PublicKey('garbage'), isNull);
      expect(parseEd25519PublicKey(''), isNull);
    });

    test('backend signature verifies; any tampering does not', () async {
      expect(await ed25519Verify(key, canon(), sig()), isTrue);
      final bad = canon()..[canon().length - 2] ^= 1;
      expect(await ed25519Verify(key, bad, sig()), isFalse);
      expect(await ed25519Verify(key, canon(), sig()..[0] ^= 1), isFalse);
      expect(await ed25519Verify(Uint8List(32), canon(), sig()), isFalse);
    });

    test('checkCommandAuth: accepted for the right device/time only', () async {
      Future<String?> chk(Map m,
              {String dev = 'dev-vector-1', DateTime? now}) =>
          checkCommandAuth(m,
              publicKey: key,
              ownDeviceId: dev,
              now: now ?? at,
              verify: ed25519Verify);
      expect(await chk(msg()), isNull);
      expect(await chk(msg(), dev: 'other'), 'device_mismatch');
      expect(await chk(msg(), now: DateTime.utc(2026, 1, 10)), 'expired');
      expect(
          await chk(msg(), now: DateTime.utc(2025, 12, 1)), 'sent_in_future');
      expect(await chk(msg()..['expires_at'] = '2026-01-09T03:04:06Z'),
          'bad_signature');
      expect(await chk(msg()..remove('sig')), 'missing_field');
    });

    test('end to end: signed message -> ack updating, then ONE update',
        () async {
      final ch = FakeChannel();
      var installs = 0;
      final c = DeviceCommandClient(
        deviceId: () async => 'dev-vector-1',
        commandPublicKey: key,
        now: () => at,
        connect: (_) async => ch,
        sleep: parkingSleep,
        testGate: ValueNotifier(false),
        checkUpdate: () async => _info,
        installUpdate: (i) async {
          installs++;
          return const UpdateResult.success();
        },
      );
      c.start();
      await pump();
      ch.server(msg());
      await pump();
      ch.server(msg()); // replay
      await pump();
      expect(ch.acks, ['updating', 'updating']);
      expect(installs, 1);
      // Unsigned / wrongly keyed variant: nothing happens.
      ch.server(msg()..['request_id'] = '99999999-2222-4333-8444-555555555555');
      await pump();
      expect(ch.sent.length, 2);
      await c.stop();
    });
  });

  group('ActiveTestGate', () {
    setUp(ActiveTestGate.resetForTest);

    test('counts holders; release is idempotent', () {
      final a = ActiveTestGate.enter();
      final b = ActiveTestGate.enter();
      expect(ActiveTestGate.active.value, isTrue);
      a();
      a();
      expect(ActiveTestGate.active.value, isTrue);
      b();
      expect(ActiveTestGate.active.value, isFalse);
    });

    testWidgets('mixin holds the gate from initState to dispose',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _Runner()));
      expect(ActiveTestGate.active.value, isTrue);
      // pushReplacement-style overlap: next runner mounts before old disposes.
      await tester.pumpWidget(const MaterialApp(home: _Runner(key: Key('b'))));
      expect(ActiveTestGate.active.value, isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(ActiveTestGate.active.value, isFalse);
    });
  });
}

class _Runner extends StatefulWidget {
  const _Runner({super.key});
  @override
  State<_Runner> createState() => _RunnerState();
}

class _RunnerState extends State<_Runner> with ActiveTestGateHold {
  @override
  Widget build(BuildContext context) => const SizedBox();
}
