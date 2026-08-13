// lib/shared/widgets/student_top_bar.dart
//
// Generalized (public) version of my_tests_screen.dart's private
// `_TopHeaderBar` — title, online/offline signal indicator (`signalProvider`,
// same source as login_screen.dart), language pill, logout pill. Extracted
// so every student-cabinet screen (via StudentShell) shares one header.
//
// [title] is new (the original always hardcoded `l10n.myTestsTitle`) — now
// each screen passes its own title so the header reads correctly wherever
// it's used; my_tests_screen.dart passes the exact same `l10n.myTestsTitle`
// it always did, so its own rendering is unchanged.
//
// [onResultsTap] keeps the exact same meaning as before: only passed when
// the sidebar (the normal way to reach `/results`) is hidden — narrow
// viewport — so `/results` always has at least one reachable entry point.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/network/connectivity_provider.dart';
import '../../core/network/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../theme/student_palette.dart';
import 'hover_region.dart';
import 'student_pill.dart';

class StudentTopHeaderBar extends ConsumerWidget {
  final String title;
  final VoidCallback onLogout;
  final VoidCallback? onResultsTap;

  const StudentTopHeaderBar({
    super.key,
    required this.title,
    required this.onLogout,
    this.onResultsTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    final signal = ref.watch(signalProvider);
    final isOnline = !signal.checking && signal.tier != SignalTier.none;
    final signalLabel = signal.checking
        ? l10n.serverChecking
        : (isOnline ? l10n.onlineStatus : l10n.offlineMode);
    final signalColor = signal.checking
        ? AppColors.brand
        : (isOnline ? AppColors.ok : pal.ink3);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: AppTextStyles.titleLarge
                    .copyWith(fontWeight: FontWeight.w800, color: pal.ink1)),
          ),
          Pill(children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: signalColor,
                  shape: BoxShape.circle,
                )),
            const SizedBox(width: 6),
            Text(signalLabel,
                style: AppTextStyles.caption
                    .copyWith(color: signalColor, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(width: 8),
          if (onResultsTap != null) ...[
            IconButton(
              icon: Icon(Icons.bar_chart_rounded, color: pal.ink2),
              tooltip: l10n.sidebarResults,
              onPressed: onResultsTap,
            ),
            const SizedBox(width: 4),
          ],
          const LanguagePill(),
          const SizedBox(width: 8),
          HoverRegion(
            builder: (context, isHovered) => GestureDetector(
              onTap: onLogout,
              child: Pill(
                color: isHovered ? pal.hoverBg : pal.surface,
                children: [
                  Icon(Icons.logout_rounded, size: 16, color: pal.ink2),
                  const SizedBox(width: 6),
                  Text(l10n.logout,
                      style:
                          AppTextStyles.labelMedium.copyWith(color: pal.ink1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
