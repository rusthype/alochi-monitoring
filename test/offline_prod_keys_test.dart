import 'dart:io';

import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String r(String p) => File(p).readAsStringSync();

  test('production offline public keys parse and are not the test keys', () {
    final sig = r('offline_keys/signing_public.pem');
    final res = r('offline_keys/results_public.pem');
    expect(OfflineKeys(signingPem: sig, resultsPem: res).isConfigured, isTrue);
    expect(sig.trim(), isNot(r('test/fixtures/offline/test_signing_public.pem').trim()));
    expect(res.trim(), isNot(r('test/fixtures/offline/test_results_public.pem').trim()));
    expect(sig.trim(), isNot(res.trim()));
  });
}
