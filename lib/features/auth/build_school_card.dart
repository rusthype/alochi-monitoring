import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

Widget buildSchoolCardPremium(
  BuildContext context,
  String schoolCode,
  String label,
  dynamic entry,
  VoidCallback onTap,
) {
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
    ),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.school_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
