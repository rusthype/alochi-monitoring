// Verifies the timeout-wrapping technique `AlochiImageCacheManager` uses to
// stop a hung network request from spinning forever (diagnostic-image-
// eternal-spinner root cause, Task 2). `_TimeoutHttpClient` itself is
// library-private to image_cache_manager.dart and can't be imported here, so
// this test exercises the identical `send().timeout(duration)` wrapping
// pattern against a client whose `send()` never completes — the exact shape
// production code applies with a 5s duration.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // Never completes — simulates a stuck SSL handshake / dropped socket.
    return Completer<http.StreamedResponse>().future;
  }

  @override
  void close() {}
}

class _TestTimeoutClient extends http.BaseClient {
  _TestTimeoutClient(this._inner, this._timeout);
  final http.Client _inner;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).timeout(_timeout);
  }

  @override
  void close() => _inner.close();
}

void main() {
  test('wrapping a hanging client with a timeout throws TimeoutException '
      'instead of hanging forever', () async {
    final client = _TestTimeoutClient(_HangingClient(), const Duration(milliseconds: 200));
    final request = http.Request('GET', Uri.parse('https://api.alochi.org/media/x.png'));

    await expectLater(
      client.send(request),
      throwsA(isA<TimeoutException>()),
    );
  });
}
