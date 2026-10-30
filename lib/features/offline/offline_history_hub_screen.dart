// lib/features/offline/offline_history_hub_screen.dart
//
// Task 4, locked navigation decision: the existing "Оффлайн история" entry
// point (login_screen.dart's button -> '/history' route) opens THIS 2-tab hub
// instead of HistoryScreen directly — no new button anywhere.
// Tab 1 "Umumiy" hosts HistoryScreen (embedded: no own Scaffold/AppBar), tab 2
// "Diagnostika" hosts the per-attempt diagnostic history. Chrome is the shared
// PillTopBar + rounded pill tab switcher (same chips as the diagnostic filters).
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/pill_chip.dart';
import '../../shared/widgets/pill_top_bar.dart';
import '../local_test/history_screen.dart';
import '../diagnostic/screens/diagnostic_history_screen.dart';

class OfflineHistoryHubScreen extends StatelessWidget {
  /// Test-only tab body overrides (default to the real DB-backed screens).
  final Widget? generalTab;
  final Widget? diagnosticTab;

  const OfflineHistoryHubScreen(
      {super.key, this.generalTab, this.diagnosticTab});

  static double _amount(TabController tabs, int i) =>
      1 - ((tabs.animation?.value ?? tabs.index.toDouble()) - i).abs();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: PillTopBar(
                      title: l10n.offlineHistoryTitle,
                      onBack: Navigator.canPop(context)
                          ? () => Navigator.pop(context)
                          : null,
                    ),
                  ),
                  Builder(builder: (context) {
                    final tabs = DefaultTabController.of(context);
                    // tabs.animation follows the TabBarView drag live; tabs.index
                    // only flips when the swipe ends.
                    return AnimatedBuilder(
                      animation: tabs.animation ?? tabs,
                      builder: (_, __) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Row(
                          children: [
                            PillChip(
                              label: l10n.offlineHistoryTabGeneral,
                              selectedAmount: _amount(tabs, 0),
                              onPressed: () => tabs.animateTo(0),
                            ),
                            const SizedBox(width: 8),
                            PillChip(
                              label: l10n.offlineHistoryTabDiagnostic,
                              selectedAmount: _amount(tabs, 1),
                              onPressed: () => tabs.animateTo(1),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  Expanded(
                    child: TabBarView(
                      children: [
                        generalTab ?? const HistoryScreen(embedded: true),
                        diagnosticTab ?? const DiagnosticHistoryScreen(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
