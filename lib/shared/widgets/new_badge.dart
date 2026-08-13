// lib/shared/widgets/new_badge.dart
//
// Minimal "NEW"/"Yangi" pill. Extracted verbatim (byte-identical) from two
// previously-duplicated private copies: my_tests_screen.dart's `_NewBadge`
// and group_select_screen.dart's `_NewBadge` — both call sites now import
// this single public widget instead.
import 'package:flutter/material.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class NewBadge extends StatelessWidget {
  const NewBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        AppLocalizations.of(context)!.newBadge,
        style: AppTextStyles.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 9.5,
        ),
      ),
    );
  }
}
