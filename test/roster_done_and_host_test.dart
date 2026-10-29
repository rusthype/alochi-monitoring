// F37: RosterDoneStore cap covers a real school; API_BASE_URL with a trailing
// slash must not produce `//api` URLs.
import 'package:alochi_monitoring/core/api/api_host.dart';
import 'package:alochi_monitoring/core/services/roster_done_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('normalizeApiHost', () {
    test('strips trailing slashes and surrounding whitespace', () {
      expect(normalizeApiHost('https://api.alochi.org/'),
          'https://api.alochi.org');
      expect(normalizeApiHost(' https://api.alochi.org// '),
          'https://api.alochi.org');
      expect(normalizeApiHost('http://10.0.0.5:8000/'), 'http://10.0.0.5:8000');
    });
    test('leaves a clean host (and the empty string) alone', () {
      expect(normalizeApiHost('https://api.alochi.org'),
          'https://api.alochi.org');
      expect(normalizeApiHost(''), '');
    });
    test('the joined URL has a single slash', () {
      expect('${normalizeApiHost('https://api.alochi.org/')}/api/v1/health/',
          'https://api.alochi.org/api/v1/health/');
    });
  });

  group('RosterDoneStore cap', () {
    test('keeps well over 500 finished students of one test', () async {
      SharedPreferences.setMockInitialValues({
        'roster_done_t': [for (var i = 0; i < 1500; i++) 's$i'],
      });
      await RosterDoneStore.add('t', 's1500');
      final done = await RosterDoneStore.load('t');
      expect(done.length, 1501);
      expect(done.contains('s0'), isTrue, reason: 'old marks are not dropped');
    });

    test('still bounded: oldest dropped beyond the cap, newest kept', () async {
      SharedPreferences.setMockInitialValues({
        'roster_done_t': [for (var i = 0; i < 5000; i++) 's$i'],
      });
      await RosterDoneStore.add('t', 'new');
      final done = await RosterDoneStore.load('t');
      expect(done.length, 5000);
      expect(done.contains('s0'), isFalse);
      expect(done.contains('s1'), isTrue);
      expect(done.contains('new'), isTrue);
    });
  });
}
