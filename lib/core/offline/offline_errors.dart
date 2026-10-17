// lib/core/offline/offline_errors.dart
//
// Stable error codes for offline-pack failures. `ApiException.message` for
// these is an internal English string (logs only); the UI layer translates by
// `code` through l10n so no user-facing text lives in the API layer.
import 'package:alochi_monitoring/l10n/app_localizations.dart';

import '../api/api_client.dart' show ApiException;

const String kOfflineUnsupported = 'offline_unsupported';
const String kOfflineNotFound = 'not_found';

/// Localized text for a known offline error code, or null (caller falls back
/// to its own generic message).
String? localizeOfflineError(AppLocalizations l10n, Object error) {
  if (error is ApiException && error.code == kOfflineUnsupported) {
    return l10n.usbErrUnsupported;
  }
  return null;
}
