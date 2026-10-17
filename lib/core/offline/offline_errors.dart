// lib/core/offline/offline_errors.dart
//
// Stable error codes for offline-pack and LAN failures. `ApiException.message`
// for these is an internal English string (logs only); the UI layer translates
// by `code` through l10n so no user-facing text lives in the API layer.
import 'package:alochi_monitoring/l10n/app_localizations.dart';

import '../api/api_client.dart' show ApiException;

const String kOfflineUnsupported = 'offline_unsupported';
const String kOfflineNotFound = 'not_found';

/// LAN client: the teacher's hub did not answer.
const String kLanUnreachable = 'lan_unreachable';

/// LAN client: the hub no longer knows our token (hub restarted, or kicked us);
/// the operator must join again with the class code.
const String kLanSessionExpired = 'lan_session_expired';

/// Localized text for a known offline error code, or null (caller falls back
/// to its own generic message).
String? localizeOfflineError(AppLocalizations l10n, Object error) {
  if (error is! ApiException) return null;
  switch (error.code) {
    case kOfflineUnsupported:
      return l10n.usbErrUnsupported;
    case kLanUnreachable:
      return l10n.lanErrUnreachable;
    case kLanSessionExpired:
      return l10n.lanErrExpired;
  }
  return null;
}
