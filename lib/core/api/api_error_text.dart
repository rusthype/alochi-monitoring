// lib/core/api/api_error_text.dart
//
// The single place that turns a failed API call into text a student may see.
// `ApiException.message` is a debug string (and `toString()` returns it), so a
// screen must never show it; it calls [localizedApiError] instead.
import 'dart:async';
import 'dart:io';

import 'package:alochi_monitoring/l10n/app_localizations.dart';

import '../offline/offline_errors.dart';
import 'api_client.dart';

String localizedApiError(AppLocalizations l10n, Object e) {
  final offline = localizeOfflineError(l10n, e);
  if (offline != null) return offline;
  if (e is ApiException) {
    switch (e.code) {
      case kApiTimeout:
      case kApiNetwork:
      case kApiTls:
        return l10n.connectionError;
      case kApiBadResponse:
        return l10n.serverErrorRetry;
    }
    if (e.statusCode == 429) return l10n.tooManyAttempts;
    if (e.statusCode >= 500) return l10n.serverErrorRetry;
    if (e.statusCode == 0) return l10n.connectionError;
    return l10n.loadFailed;
  }
  if (e is SocketException || e is TimeoutException || e is IOException) {
    return l10n.connectionError;
  }
  return l10n.loadFailed;
}
