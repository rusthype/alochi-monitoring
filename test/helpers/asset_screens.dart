// The built-in ("assets") RESULT screen built with realistic data, so the
// offline tests exercise the real payload builders, not hand-made copies.
import 'package:alochi_monitoring/core/offline/offline_asset_results.dart';
import 'package:alochi_monitoring/features/interhouse/interhouse_data.dart';
import 'package:alochi_monitoring/features/interhouse/interhouse_result_screen.dart';
import 'package:alochi_monitoring/features/interhouse/interhouse_scorer.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Widget assetTestApp(Widget child, {Locale locale = const Locale('uz')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Widget interhouseResult(OfflineAssetStudent? s, IhTestData data) =>
    InterhouseResultScreen(
      result: IhResult(
        parts: [
          for (var i = 0; i < 5; i++)
            IhPartScore(partName: 'P$i', score: 4, shields: 3)
        ],
        total: 20,
        totalShields: 15,
        level: data.levels.first,
      ),
      testData: data,
      variant: 4,
      isOnline: false,
      firstName: 'Ali',
      lastName: 'Valiyev',
      school: '',
      testStartedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      offlineStudent: s,
    );
