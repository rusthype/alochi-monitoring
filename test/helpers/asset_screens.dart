// Shared MaterialApp wrapper for the offline asset widget tests.
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Widget assetTestApp(Widget child, {Locale locale = const Locale('uz')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
