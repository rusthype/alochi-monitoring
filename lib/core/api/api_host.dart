/// `--dart-define=API_BASE_URL=...` may carry a trailing slash (or stray
/// spaces); every URL is built as `$host/api/...`, so strip them once here.
String normalizeApiHost(String raw) =>
    raw.trim().replaceFirst(RegExp(r'/+$'), '');
