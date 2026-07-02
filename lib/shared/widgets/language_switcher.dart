import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/locale/locale_provider.dart';
import '../../core/theme/app_colors.dart';

class LanguageSwitcher extends ConsumerWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(localeProvider);

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: currentLocale.languageCode,
        icon: const Icon(Icons.language_rounded, size: 20, color: AppColors.ink2),
        dropdownColor: AppColors.surface,
        style: const TextStyle(
          color: AppColors.ink1,
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
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('UZ'),
            ),
          ),
          DropdownMenuItem(
            value: 'ru',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('RU'),
            ),
          ),
        ],
      ),
    );
  }
}
