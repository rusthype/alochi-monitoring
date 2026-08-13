// lib/features/session/student_settings_screen.dart
//
// Student cabinet — "Настройки" (mock5.jpg). Reuses StudentShell/Pill/
// KpiTile from the shared student-cabinet widget set (see student_shell.dart
// / student_pill.dart) instead of re-declaring chrome. Not yet wired into
// app_router.dart — routing happens centrally afterward.
//
// DARK THEME SCOPE: AppTheme.darkTheme + themeModeProvider
// (core/theme/app_prefs_provider.dart) are wired at the MaterialApp root
// (main.dart), so Theme.of(context) genuinely flips app-wide. But nearly
// every existing screen — including StudentShell's own sidebar/top bar —
// paints from the static light `AppColors`/`AppTextStyles` constants
// directly rather than Theme.of(context), so only Material-default chrome
// and screens that opt in repaint automatically. THIS screen's own body
// (everything below StudentShell's header/sidebar) opts in: it reads
// `Theme.of(context).brightness` and switches between AppColors' light
// tokens and its new dark tokens for its own backgrounds/borders/text. The
// shared shell chrome (sidebar + top header bar) stays light regardless —
// that's shared infrastructure other screens also render through and is
// out of scope for this screen to repaint.
//
// FONT SIZE: fontScaleProvider drives a MediaQuery textScaler override at
// the MaterialApp root (main.dart) — real, app-wide, not scoped to this
// screen only.
//
// NOTIFICATION TOGGLES: "Звук при завершении теста" / "Напоминания о новых
// тестах" persist real device-local preferences (shared_preferences via
// soundOnCompleteProvider/testReminderProvider), but this kiosk app has no
// completion-sound playback and no local/push reminder system today — there
// is nothing yet for these to gate. They are not fake: the value is real and
// persisted, ready for a future feature to read; today no feature does.
//
// SECURITY SECTION — no self-service reset/multi-device endpoint exists for
// kiosk StudentCredential accounts (confirmed by prior backend
// investigation): "Сбросить пароль" is a static informational row (contact
// teacher/admin), not a fake reset flow. "Выйти со всех устройств" is shown
// per the mockup layout but disabled with an honest subtitle — only this
// device's local logout is real. "Выйти из аккаунта" calls the shared
// `logoutStudentSession()` (core/session/logout.dart) — the same
// kiosk-security clear-session + hard-navigation-reset every student-cabinet
// screen uses, not a per-screen reimplementation.
//
// OMITTED vs mock5.jpg (would require fabricating data/flows that don't
// exist — see "never fabricate" rule): avatar upload, "Редактировать
// профиль", "Регион" dropdown, "Последний вход"/"Устройство" (no such
// backend field), and the mockup's cross-device "settings sync" tip wording
// (shared_preferences is local-only — the tip text here says so honestly).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/locale/locale_provider.dart';
import '../../core/models/models.dart';
import '../../core/session/logout.dart';
import '../../core/theme/app_prefs_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/hover_region.dart';
import '../../shared/widgets/student_shell.dart';

/// Palette that switches with Theme.of(context).brightness — see file
/// header for why only this screen's own body opts in.
class _Palette {
  final bool isDark;
  const _Palette(this.isDark);

  Color get surface => isDark ? AppColors.darkSurface : AppColors.surface;
  Color get border => isDark ? AppColors.darkBorder : AppColors.border;
  Color get ink1 => isDark ? AppColors.darkInk1 : AppColors.ink1;
  Color get ink2 => isDark ? AppColors.darkInk2 : AppColors.ink2;
  Color get ink3 => isDark ? AppColors.darkInk3 : AppColors.ink3;
  Color get chipBg => isDark ? AppColors.darkBg : AppColors.pageBg;
  Color get hoverBg =>
      isDark ? AppColors.darkBorder.withValues(alpha: 0.5) : AppColors.hoverBg;
}

class StudentSettingsScreen extends ConsumerWidget {
  final StudentSession session;

  const StudentSettingsScreen({super.key, required this.session});

  Future<void> _logoutNow(BuildContext context) => logoutStudentSession(context);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final pal = _Palette(Theme.of(context).brightness == Brightness.dark);

    return StudentShell(
      currentRoute: '/settings',
      session: session,
      title: l10n.sidebarSettings,
      onLogout: () => _logoutNow(context),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 900;
            final left = _leftColumn(l10n, pal);
            final right = _rightColumn(context, l10n, pal);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Hero(l10n: l10n),
                const SizedBox(height: 16),
                if (isNarrow)
                  Column(children: [left, const SizedBox(height: 16), right])
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: left),
                      const SizedBox(width: 16),
                      Expanded(child: right),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _leftColumn(AppLocalizations l10n, _Palette pal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AccountCard(session: session, l10n: l10n, pal: pal),
        const SizedBox(height: 16),
        _PersonalizationCard(l10n: l10n, pal: pal),
        const SizedBox(height: 16),
        _LanguageCard(l10n: l10n, pal: pal),
        const SizedBox(height: 16),
        _NotificationsCard(l10n: l10n, pal: pal),
      ],
    );
  }

  Widget _rightColumn(BuildContext context, AppLocalizations l10n, _Palette pal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SecurityCard(l10n: l10n, pal: pal, onLogout: () => _logoutNow(context)),
        const SizedBox(height: 16),
        _SummaryCard(l10n: l10n, pal: pal),
        const SizedBox(height: 16),
        _TipsCard(l10n: l10n, pal: pal),
      ],
    );
  }
}

// ── Card shell ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final _Palette pal;
  final List<Widget> children;
  const _Card({required this.title, required this.pal, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTextStyles.titleMedium
                  .copyWith(color: pal.ink1, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// Two-option segmented toggle row (theme / font size / interface language).
class _SegmentedRow extends StatelessWidget {
  final String label;
  final List<(String, bool, VoidCallback)> options; // (text, selected, onTap)
  final _Palette pal;
  const _SegmentedRow(
      {required this.label, required this.options, required this.pal});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: AppTextStyles.bodyLarge.copyWith(color: pal.ink1)),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final (text, selected, onTap) in options)
                _SegmentButton(
                    text: text, selected: selected, onTap: onTap, pal: pal),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  final _Palette pal;
  const _SegmentButton(
      {required this.text,
      required this.selected,
      required this.onTap,
      required this.pal});

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      builder: (context, isHovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brandLight
                : (isHovered ? pal.hoverBg : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? AppColors.brand : pal.border,
                width: selected ? 1.5 : 1),
          ),
          child: Text(text,
              style: AppTextStyles.labelMedium.copyWith(
                color: selected ? AppColors.brand : pal.ink2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              )),
        ),
      ),
    );
  }
}

// ── Hero banner ──────────────────────────────────────────────────────────

class _Hero extends ConsumerWidget {
  final AppLocalizations l10n;
  const _Hero({required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final notifsOn =
        ref.watch(soundOnCompleteProvider) || ref.watch(testReminderProvider);
    final localeCode = ref.watch(localeProvider).languageCode;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.secondary, Color(0xFFF4A860)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadii.roundedXl,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20,
        runSpacing: 16,
        children: [
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.settingsHeroTitle,
                    style: AppTextStyles.titleLarge.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(l10n.settingsHeroSubtitle,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: Colors.white.withValues(alpha: 0.9))),
              ],
            ),
          ),
          _HeroChip(
            icon: Icons.language_rounded,
            label: l10n.settingsHeroCurrentLanguage,
            value: localeCode == 'ru' ? l10n.languageRussian : l10n.languageUzbek,
          ),
          _HeroChip(
            icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            label: l10n.themeLabel,
            value: isDark ? l10n.themeDark : l10n.themeLight,
          ),
          _HeroChip(
            icon: Icons.notifications_rounded,
            label: l10n.notificationsSectionTitle,
            value:
                notifsOn ? l10n.notificationsStatusOn : l10n.notificationsStatusOff,
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _HeroChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: AppRadii.roundedLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption
                      .copyWith(color: Colors.white.withValues(alpha: 0.85))),
            ),
          ]),
          const SizedBox(height: 4),
          Text(value,
              style: AppTextStyles.labelLarge
                  .copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Account card ─────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  final StudentSession session;
  final AppLocalizations l10n;
  final _Palette pal;
  const _AccountCard(
      {required this.session, required this.l10n, required this.pal});

  @override
  Widget build(BuildContext context) {
    final letter = session.studentName.trim().isNotEmpty
        ? session.studentName.trim()[0].toUpperCase()
        : '?';

    return _Card(title: l10n.accountSectionTitle, pal: pal, children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration:
                const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(letter,
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(session.studentName,
                style: AppTextStyles.titleMedium
                    .copyWith(color: pal.ink1, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      const SizedBox(height: 16),
      // Same grade/group/school display fields as my_tests_screen.dart's
      // _StudentProfileCard — no /my-profile/ fetch here, so no school-name
      // override; schoolCode is shown directly (that screen's own fallback
      // value when profile data isn't available).
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (session.grade != null)
            _InfoTile(
                icon: Icons.school_rounded,
                caption: l10n.classLabelCaption,
                value: '${session.grade}-${l10n.gradeShort}',
                pal: pal),
          if ((session.groupName ?? '').isNotEmpty)
            _InfoTile(
                icon: Icons.groups_2_rounded,
                caption: l10n.groupLabelCaption,
                value: session.groupName!,
                pal: pal),
          if (session.schoolCode.isNotEmpty)
            _InfoTile(
                icon: Icons.apartment_rounded,
                caption: l10n.schoolLabel,
                value: session.schoolCode,
                pal: pal),
        ],
      ),
    ]);
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String caption;
  final String value;
  final _Palette pal;
  const _InfoTile(
      {required this.icon,
      required this.caption,
      required this.value,
      required this.pal});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: pal.chipBg, borderRadius: AppRadii.roundedMd),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: pal.ink3),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: AppTextStyles.labelLarge
                    .copyWith(color: pal.ink1, fontWeight: FontWeight.w700)),
            Text(caption, style: AppTextStyles.caption.copyWith(color: pal.ink3)),
          ],
        ),
      ]),
    );
  }
}

// ── Personalization card (theme + font size) ────────────────────────────────

class _PersonalizationCard extends ConsumerWidget {
  final AppLocalizations l10n;
  final _Palette pal;
  const _PersonalizationCard({required this.l10n, required this.pal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final isLarge = ref.watch(fontScaleProvider) == FontScaleNotifier.large;

    return _Card(title: l10n.personalizationSectionTitle, pal: pal, children: [
      _SegmentedRow(
        label: l10n.themeLabel,
        pal: pal,
        options: [
          (l10n.themeLight, !isDark,
              () => ref.read(themeModeProvider.notifier).setDark(false)),
          (l10n.themeDark, isDark,
              () => ref.read(themeModeProvider.notifier).setDark(true)),
        ],
      ),
      _SegmentedRow(
        label: l10n.fontSizeLabel,
        pal: pal,
        options: [
          (l10n.fontSizeNormal, !isLarge,
              () => ref.read(fontScaleProvider.notifier).setLarge(false)),
          (l10n.fontSizeLarge, isLarge,
              () => ref.read(fontScaleProvider.notifier).setLarge(true)),
        ],
      ),
    ]);
  }
}

// ── Language card ───────────────────────────────────────────────────────

class _LanguageCard extends ConsumerWidget {
  final AppLocalizations l10n;
  final _Palette pal;
  const _LanguageCard({required this.l10n, required this.pal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(localeProvider).languageCode;
    return _Card(title: l10n.languageRegionSectionTitle, pal: pal, children: [
      _SegmentedRow(
        label: l10n.interfaceLanguageLabel,
        pal: pal,
        options: [
          (l10n.languageUzbek, code == 'uz',
              () => ref.read(localeProvider.notifier).setLocale(const Locale('uz'))),
          (l10n.languageRussian, code == 'ru',
              () => ref.read(localeProvider.notifier).setLocale(const Locale('ru'))),
        ],
      ),
    ]);
  }
}

// ── Notifications card ────────────────────────────────────────────────────

class _NotificationsCard extends ConsumerWidget {
  final AppLocalizations l10n;
  final _Palette pal;
  const _NotificationsCard({required this.l10n, required this.pal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soundOn = ref.watch(soundOnCompleteProvider);
    final remindersOn = ref.watch(testReminderProvider);

    return _Card(title: l10n.notificationsSectionTitle, pal: pal, children: [
      _SwitchRow(
        label: l10n.notifSoundOnComplete,
        value: soundOn,
        pal: pal,
        onChanged: (v) => ref.read(soundOnCompleteProvider.notifier).set(v),
      ),
      const SizedBox(height: 4),
      _SwitchRow(
        label: l10n.notifRemindersNewTests,
        value: remindersOn,
        pal: pal,
        onChanged: (v) => ref.read(testReminderProvider.notifier).set(v),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: pal.chipBg, borderRadius: AppRadii.roundedMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: pal.ink3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.notifHelperText,
                  style: AppTextStyles.bodyMedium.copyWith(color: pal.ink2)),
            ),
          ],
        ),
      ),
    ]);
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final _Palette pal;
  const _SwitchRow(
      {required this.label,
      required this.value,
      required this.onChanged,
      required this.pal});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppTextStyles.bodyLarge.copyWith(color: pal.ink1)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.brand,
          ),
        ],
      ),
    );
  }
}

// ── Security card ─────────────────────────────────────────────────────────

class _SecurityCard extends StatelessWidget {
  final AppLocalizations l10n;
  final _Palette pal;
  final VoidCallback onLogout;
  const _SecurityCard(
      {required this.l10n, required this.pal, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return _Card(title: l10n.securitySectionTitle, pal: pal, children: [
      // No self-service reset endpoint for kiosk StudentCredential accounts
      // — informational only, points to a human, never a fake reset flow.
      _SecurityRow(
        icon: Icons.lock_outline_rounded,
        iconColor: AppColors.primary,
        iconBg: AppColors.primaryMuted,
        title: l10n.resetPasswordLabel,
        subtitle: l10n.resetPasswordHint,
        pal: pal,
        enabled: false,
      ),
      // No multi-device/session-revocation endpoint exists — only this
      // device's local logout (below) is real. Kept in the layout per the
      // mockup but disabled with an honest subtitle rather than faking it.
      _SecurityRow(
        icon: Icons.devices_other_rounded,
        iconColor: AppColors.ink3,
        iconBg: AppColors.chipBg,
        title: l10n.logoutAllDevicesLabel,
        subtitle: l10n.logoutAllDevicesHint,
        pal: pal,
        enabled: false,
      ),
      // Real — same kiosk-security clear-session path as my_tests_screen.dart.
      _SecurityRow(
        icon: Icons.logout_rounded,
        iconColor: AppColors.error,
        iconBg: AppColors.errorMuted,
        title: l10n.logoutAccountLabel,
        subtitle: l10n.logoutAccountHint,
        pal: pal,
        enabled: true,
        titleColor: AppColors.error,
        onTap: onLogout,
      ),
    ]);
  }
}

class _SecurityRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final _Palette pal;
  final bool enabled;
  final Color? titleColor;
  final VoidCallback? onTap;
  const _SecurityRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.pal,
    required this.enabled,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: iconBg, borderRadius: AppRadii.roundedMd),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.bodyLarge.copyWith(
                        color: titleColor ?? pal.ink1, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: AppTextStyles.caption.copyWith(color: pal.ink3)),
              ],
            ),
          ),
          if (enabled)
            Icon(Icons.chevron_right_rounded, color: pal.ink3)
          else
            Icon(Icons.lock_outline_rounded, size: 16, color: pal.ink3),
        ],
      ),
    );

    if (!enabled) {
      return Tooltip(message: subtitle, child: Opacity(opacity: 0.75, child: row));
    }
    return HoverRegion(
      builder: (context, isHovered) => Material(
        color: isHovered ? pal.hoverBg : Colors.transparent,
        borderRadius: AppRadii.roundedMd,
        child: InkWell(
          borderRadius: AppRadii.roundedMd,
          onTap: onTap,
          child: row,
        ),
      ),
    );
  }
}

// ── Summary card ─────────────────────────────────────────────────────────

class _SummaryCard extends ConsumerWidget {
  final AppLocalizations l10n;
  final _Palette pal;
  const _SummaryCard({required this.l10n, required this.pal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final isLarge = ref.watch(fontScaleProvider) == FontScaleNotifier.large;
    final code = ref.watch(localeProvider).languageCode;
    final notifsOn =
        ref.watch(soundOnCompleteProvider) || ref.watch(testReminderProvider);

    return _Card(title: l10n.summarySectionTitle, pal: pal, children: [
      _SummaryRow(
          label: l10n.themeLabel,
          value: isDark ? l10n.themeDark : l10n.themeLight,
          color: AppColors.brand,
          pal: pal),
      _SummaryRow(
          label: l10n.fontSizeLabel,
          value: isLarge ? l10n.fontSizeLarge : l10n.fontSizeNormal,
          color: AppColors.amber,
          pal: pal),
      _SummaryRow(
          label: l10n.interfaceLanguageLabel,
          value: code == 'ru' ? l10n.languageRussian : l10n.languageUzbek,
          color: AppColors.violet,
          pal: pal),
      _SummaryRow(
          label: l10n.notificationsSectionTitle,
          value:
              notifsOn ? l10n.notificationsStatusOn : l10n.notificationsStatusOff,
          color: AppColors.success,
          pal: pal),
    ]);
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final _Palette pal;
  const _SummaryRow(
      {required this.label,
      required this.value,
      required this.color,
      required this.pal});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppTextStyles.bodyMedium.copyWith(color: pal.ink2)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadii.roundedSm,
            ),
            child: Text(value,
                style: AppTextStyles.labelMedium
                    .copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ── Tips card ─────────────────────────────────────────────────────────────

class _TipsCard extends StatelessWidget {
  final AppLocalizations l10n;
  final _Palette pal;
  const _TipsCard({required this.l10n, required this.pal});

  @override
  Widget build(BuildContext context) {
    return _Card(title: l10n.tipsSectionTitle, pal: pal, children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.tips_and_updates_rounded,
              size: 20, color: AppColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l10n.tipsBody,
                style: AppTextStyles.bodyMedium.copyWith(color: pal.ink2)),
          ),
        ],
      ),
    ]);
  }
}
