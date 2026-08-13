// lib/shared/widgets/student_pill.dart
//
// Generalized (public) versions of my_tests_screen.dart's private `_Pill`
// and `_LanguagePill` — extracted so the shared student-cabinet shell/header
// can use them too. Visuals/behavior unchanged from the originals.
//
// [LanguagePill] deliberately does NOT merge with
// shared/widgets/language_switcher.dart (used by login_screen.dart) — that
// widget has a different look (DropdownButton) and is out of scope here.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locale/locale_provider.dart';
import '../theme/app_theme.dart';
import '../theme/student_palette.dart';

/// Shared white-pill container used for header status/language/logout
/// controls so all three share one radius/padding/border look.
class Pill extends StatelessWidget {
  final List<Widget> children;
  final Color? color;
  const Pill({super.key, required this.children, this.color});

  @override
  Widget build(BuildContext context) {
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color ?? pal.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Student-cabinet language pill — reads/writes the same `localeProvider`
/// as [Pill]'s other header controls, styled to match. Intentionally
/// separate from `LanguageSwitcher` (see file header).
class LanguagePill extends ConsumerWidget {
  const LanguagePill({super.key});

  static const _names = {'uz': 'O‘zbekcha', 'ru': 'Русский'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeProvider).languageCode;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return PopupMenuButton<String>(
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) => ref.read(localeProvider.notifier).setLocale(Locale(v)),
      itemBuilder: (context) => _names.entries
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      child: Pill(
        children: [
          Icon(Icons.language_rounded, size: 16, color: pal.ink2),
          const SizedBox(width: 6),
          Text(_names[code] ?? code.toUpperCase(),
              style: AppTextStyles.labelMedium.copyWith(color: pal.ink1)),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: pal.ink3),
        ],
      ),
    );
  }
}
