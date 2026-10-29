// F36(b): a broken OFFLINE_*_PUBKEY_B64 define is reported, not silent.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/diagnostics/error_log.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dir = 'test/fixtures/offline';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pem = File('$_dir/test_signing_public.pem').readAsStringSync();

  test('good defines: configured, nothing reported', () {
    final problems = <String>[];
    final k = OfflineKeys.fromRaw(base64.encode(utf8.encode(pem)), pem,
        onProblem: problems.add);
    expect(k.isConfigured, isTrue);
    expect(problems, isEmpty);
  });

  test('empty defines are the documented "disabled" default: not a problem',
      () {
    final problems = <String>[];
    final k = OfflineKeys.fromRaw('', '', onProblem: problems.add);
    expect(k.isConfigured, isFalse);
    expect(problems, isEmpty);
  });

  test('bad base64 / not-a-key name the key and disable offline mode', () {
    final problems = <String>[];
    final k = OfflineKeys.fromRaw('%%%not base64%%%',
        base64.encode(utf8.encode('hello')),
        onProblem: problems.add);
    expect(k.isConfigured, isFalse);
    expect(problems, hasLength(2));
    expect(problems[0], contains('signing'));
    expect(problems[0], contains('base64'));
    expect(problems[1], contains('results'));
    expect(problems[1], contains('RSA public key'));
  });

  test('default sink lands in the device error log', () async {
    SharedPreferences.setMockInitialValues({});
    OfflineKeys.fromRaw('%%%', '');
    final snap = await ErrorLog.snapshot();
    expect(snap.entries.map((e) => e['message'].toString()),
        contains(contains('offline_keys')));
  });
}
