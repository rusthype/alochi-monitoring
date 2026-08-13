// lib/shared/theme/student_palette.dart
//
// Shared light/dark color lookup for the student-cabinet screens — promoted
// from student_settings_screen.dart's private `_Palette` (same logic,
// unchanged) so the shell/sidebar/header/pill/kpi widgets can dark-mode-adapt
// too, not just the settings screen.
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class StudentPalette {
  final bool isDark;
  const StudentPalette(this.isDark);

  Color get surface => isDark ? AppColors.darkSurface : AppColors.surface;
  Color get border => isDark ? AppColors.darkBorder : AppColors.border;
  Color get ink1 => isDark ? AppColors.darkInk1 : AppColors.ink1;
  Color get ink2 => isDark ? AppColors.darkInk2 : AppColors.ink2;
  Color get ink3 => isDark ? AppColors.darkInk3 : AppColors.ink3;
  Color get chipBg => isDark ? AppColors.darkBg : AppColors.pageBg;
  Color get hoverBg =>
      isDark ? AppColors.darkBorder.withValues(alpha: 0.5) : AppColors.hoverBg;
}
