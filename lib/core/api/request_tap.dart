// lib/core/api/request_tap.dart
//
// Remembers "METHOD /path" of the request a `_send()` put on the wire so a
// timeout can be logged with its endpoint. Host and query are never kept
// (tokens / ids may live in them); ErrorLog.sanitizeErrorMessage still masks
// long ids in the path.
import 'package:http/http.dart' as http;

class RequestTap extends http.BaseClient {
  RequestTap(this._inner);
  final http.Client _inner;
  String? _label;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    _label = '${request.method} ${request.url.path}';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();

  /// Runs [req] (a `http.get/post/...` closure) through this tap.
  Future<http.Response> run(Future<http.Response> Function() req) =>
      http.runWithClient(req, () => this);

  /// [error] plus the tapped endpoint, e.g. `TimeoutException ... [GET /x/]`.
  Object describe(Object error) => _label == null ? error : '$error [$_label]';
}
