import 'dart:async';

import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('background calls give up after 8s, interactive ones keep 20s',
      (tester) async {
    {
      final hang = MockClient((_) => Completer<http.Response>().future);
      final done = <String, bool>{};
      http.runWithClient(() {
        for (final e in <String, Future<Object?> Function()>{
          'ping': () =>
              diagnosticKioskApi.pingElapsed(attemptId: 'a', elapsedSeconds: 1),
          'sync': () =>
              diagnosticKioskApi.syncAnswers(attemptId: 'a', answers: const []),
          'finish': () => diagnosticKioskApi
              .finishAttempt(attemptId: 'a', answers: const []),
        }.entries) {
          e.value().then<void>((_) {}, onError: (_) => done[e.key] = true);
        }
      }, () => hang);
      await tester.pump(const Duration(seconds: 7));
      expect(done, isEmpty);
      await tester.pump(const Duration(seconds: 2)); // 9s
      expect(done.keys.toSet(), {'ping', 'sync'});
      await tester.pump(const Duration(seconds: 12)); // 21s
      expect(done.keys.toSet(), {'ping', 'sync', 'finish'});
    }
  });
}
