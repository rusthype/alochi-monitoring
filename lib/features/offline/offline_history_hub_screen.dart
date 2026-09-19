// lib/features/offline/offline_history_hub_screen.dart
//
// Task 4, locked navigation decision: the existing "Оффлайн история" entry
// point (login_screen.dart's button -> '/history' route) now opens THIS
// 2-tab hub instead of HistoryScreen directly — no new button anywhere.
// Tab 1 "Umumiy" hosts the existing HistoryScreen (embedded, unmodified
// internally beyond the `embedded` flag that strips its own Scaffold/AppBar
// so it can live inside this shared one). Tab 2 "Diagnostika" hosts the new
// per-attempt diagnostic history.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../local_test/history_screen.dart';
import '../diagnostic/screens/diagnostic_history_screen.dart';

class OfflineHistoryHubScreen extends StatelessWidget {
  const OfflineHistoryHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 1,
          title: Text(
            l10n.offlineHistoryTitle,
            style: const TextStyle(
                color: AppColors.ink1,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: AppColors.ink1),
          bottom: TabBar(
            labelColor: AppColors.brand,
            unselectedLabelColor: AppColors.ink3,
            indicatorColor: AppColors.brand,
            tabs: [
              Tab(text: l10n.offlineHistoryTabGeneral),
              Tab(text: l10n.offlineHistoryTabDiagnostic),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            HistoryScreen(embedded: true),
            DiagnosticHistoryScreen(),
          ],
        ),
      ),
    );
  }
}
