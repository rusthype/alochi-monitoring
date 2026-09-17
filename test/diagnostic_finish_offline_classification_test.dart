// Regression test for the 2026-09-17 Maktab 56 incident: a queued
// kiosk/finish retry that got ANY non-429 400 back used to be treated as
// "permanent" and deleted from the offline queue with no further retry,
// silently destroying real, already-answered test data. Only a genuine
// "already finished" 400 (idempotent no-op success) should be treated as
// permanent now — everything else must stay queued for another retry.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';

void main() {
  group('classifyFinishOfflineResponse', () {
    test('already-finished 400 is synced and permanent (safe no-op)', () {
      final result = classifyFinishOfflineResponse(
        400,
        jsonEncode({'detail': 'Bu test allaqachon yakunlangan.'}),
      );
      expect(result['synced'], true);
      expect(result['permanent'], true);
    });

    test('an unknown/unexpected 400 stays retryable, not permanent', () {
      final result = classifyFinishOfflineResponse(
        400,
        jsonEncode({'detail': "Noma'lum savol: abc-123"}),
      );
      expect(result['synced'], false);
      expect(result['permanent'], false);
    });

    test('a 400 with no parseable body stays retryable', () {
      final result = classifyFinishOfflineResponse(400, 'not json');
      expect(result['synced'], false);
      expect(result['permanent'], false);
    });

    test('429 rate limit is never permanent, regardless of body', () {
      final result = classifyFinishOfflineResponse(
        429,
        jsonEncode({'detail': 'Rate limited.'}),
      );
      expect(result['permanent'], false);
    });

    test('500 is retryable, not permanent', () {
      final result = classifyFinishOfflineResponse(500, 'Internal Server Error');
      expect(result['synced'], false);
      expect(result['permanent'], false);
    });
  });
}
