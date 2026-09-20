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

  // Regression for the score-loss half of the same incident family: an
  // offline retry that hits "already yakunlangan" is correctly classified
  // as synced+permanent above, but that 400 body carries no score — so
  // without recovery, DiagnosticHistoryDb.markSent() permanently wrote
  // null scores over a real server-side result. withRecoveredScore is the
  // pure merge step submitFinishOffline uses after a best-effort
  // kiosk/peek/ call to backfill the real score in that case.
  group('withRecoveredScore', () {
    final classified = {'synced': true, 'permanent': true};

    test('merges score_math/score_english from a finished peek result', () {
      final result = withRecoveredScore(classified, {
        'finished': true,
        'score_math': 6,
        'score_english': 3,
      });
      expect(result['synced'], true);
      expect(result['permanent'], true);
      expect(result['score_math'], 6);
      expect(result['score_english'], 3);
    });

    test('leaves classified unchanged when peek result is null (peek threw)',
        () {
      final result = withRecoveredScore(classified, null);
      expect(result, classified);
      expect(result.containsKey('score_math'), false);
    });

    test('leaves classified unchanged when peek did not report finished', () {
      final result = withRecoveredScore(classified, {'finished': false});
      expect(result, classified);
      expect(result.containsKey('score_math'), false);
    });
  });
}
