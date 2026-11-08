import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/locale/locale_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';

/// Row height of the opened language menu (>= kMinInteractiveDimension).
const double kLanguageMenuItemHeight = 48;

class LanguageSwitcher extends ConsumerWidget {
  final Color? foregroundColor;
  final Color? iconColor;
  final Color? dropdownColor;
  final EdgeInsetsGeometry? padding;

  const LanguageSwitcher({
    super.key,
    this.foregroundColor,
    this.iconColor,
    this.dropdownColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);

    // Soft brand tint for the selected/focused row (focusColor) and a lighter
    // one for hover, instead of the default flat gray block. The dropdown
    // route captures this Theme, so the opened menu picks it up too.
    return Theme(
      data: Theme.of(context).copyWith(
        focusColor: AppColors.brand.withValues(alpha: .10),
        hoverColor: AppColors.brand.withValues(alpha: .05),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentLocale.languageCode,
          borderRadius: AppRadii.roundedXl2,
          padding: padding,
          focusColor: Colors.transparent,
          itemHeight: kLanguageMenuItemHeight,
          elevation: 12,
          icon: Icon(
            Icons.language_rounded,
            size: 20,
            color: iconColor ?? AppColors.ink2,
          ),
          dropdownColor: dropdownColor ?? AppColors.surface,
          style: TextStyle(
            color: foregroundColor ?? AppColors.ink1,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          onChanged: (String? newValue) {
            if (newValue != null) {
              ref.read(localeProvider.notifier).setLocale(Locale(newValue));
            }
          },
          items: const [
            DropdownMenuItem(
              value: 'uz',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: Text('UZ'),
              ),
            ),
            DropdownMenuItem(
              value: 'ru',
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: Text('RU'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
