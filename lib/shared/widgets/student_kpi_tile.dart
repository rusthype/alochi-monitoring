// lib/shared/widgets/student_kpi_tile.dart
//
// Generalized (public) version of my_tests_screen.dart's private
// `_StudentProfileCard._kpiTile` instance method, extracted into a
// standalone StatelessWidget. Visuals unchanged.
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class KpiTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;

  const KpiTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: const BoxDecoration(
          color: AppColors.pageBg, borderRadius: AppRadii.roundedMd),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: AppTextStyles.titleLarge
                        .copyWith(fontWeight: FontWeight.w800, fontSize: 18)),
                Text(label,
                    style:
                        AppTextStyles.caption.copyWith(color: AppColors.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
