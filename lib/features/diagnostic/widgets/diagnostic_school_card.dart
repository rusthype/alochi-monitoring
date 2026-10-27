// lib/features/diagnostic/widgets/diagnostic_school_card.dart
//
// Kiosk school card: big number badge, short name, optional city subtitle and
// an optional "last chosen" marker. Separate from DiagnosticPillButton (the
// class-select screen depends on that one's pill shape).
import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

class DiagnosticSchoolCard extends StatelessWidget {
  final int? number;
  final String title;
  final String? subtitle;
  final String? marker;
  final VoidCallback onTap;

  const DiagnosticSchoolCard({
    super.key,
    required this.number,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.marker,
  });

  @override
  Widget build(BuildContext context) {
    final pinned = marker != null;
    return SizedBox(
      width: 240,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: pinned ? AppColors.brand : AppColors.border,
                width: pinned ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (marker != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      marker!,
                      style: const TextStyle(
                        color: AppColors.brand,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: number == null
                          ? const Icon(
                              Icons.school_rounded,
                              color: AppColors.brand,
                              size: 28,
                            )
                          : FittedBox(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Text(
                                  '$number',
                                  style: const TextStyle(
                                    color: AppColors.brand,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ink1,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.ink2,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
