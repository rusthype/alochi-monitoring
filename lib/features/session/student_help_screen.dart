// lib/features/session/student_help_screen.dart
//
// "Помощь и поддержка" (Help & Support) screen for the self-login student
// cabinet — reuses StudentShell/sidebar/header exactly like
// results_screen.dart and my_tests_screen.dart. Wired into app_router.dart
// as the live `/help` route.
//
// Real-data policy (never fabricate):
// - App version: PackageInfo.fromPlatform(), same pattern as
//   login_screen.dart's _loadAppVersion. FAQ count is derived from the
//   actual _faqItems list length, never a hand-typed number.
// - Server status ("О приложении" panel): the real `signalProvider` signal
//   (same source student_top_bar.dart uses) — genuinely means "can we reach
//   the backend", so wiring it here is correct.
// - "Поддержка: Онлайн" KPI chip is deliberately NOT wired to
//   `signalProvider` — that measures server reachability, not a support
//   desk's availability, and there is no real support-desk online signal in
//   this codebase. It stays static UI copy (reuses the existing
//   `onlineStatus` string), same treatment as the sidebar's static labels.
// - Video-instruction cards: no real video hosting exists in this app. The
//   mockup's 3 cards are rendered visually (gradient thumbnail + duration
//   badge) but tapping any of them shows the same "Скоро" (`comingSoon`)
//   SnackBar used elsewhere in this cabinet (see student_messages_screen.dart)
//   instead of claiming a real video plays — no fabricated playback.
// - Telegram-bot button: real, live deep-link to the school bot
//   (`https://t.me/alochipoll_bot`, `@alochipoll_bot`) via url_launcher.
// - Admin contact card (name/email/phone/hours): product decision, approved
//   by the user, to hard-code this as static UI copy matching the mockup
//   exactly — it is NOT sourced from a real backend record, so it is written
//   as plain literals below rather than routed through AppLocalizations.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/models/models.dart';
import '../../core/network/connectivity_provider.dart';
import '../../core/network/connectivity_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/student_palette.dart';

const _kTelegramBotUrl = 'https://t.me/alochipoll_bot';

// Static admin contact card content (see file-header note) — a fixed
// product decision, not real backend data, so it is not localized.
const _kAdminRole = 'Школьный администратор';
const _kAdminName = 'Dilnoza Karimova';
const _kAdminEmail = 'admin@school123.uz';
const _kAdminPhone = '+998 90 123 45 67';
const _kAdminHours = 'Пн–Сб, 09:00–18:00';

class _VideoTutorial {
  final IconData icon;
  final String Function(AppLocalizations) title;
  final String Function(AppLocalizations) subtitle;
  final String duration;
  const _VideoTutorial(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.duration});
}

final List<_VideoTutorial> _videoTutorials = [
  _VideoTutorial(
      icon: Icons.fact_check_rounded,
      title: (l10n) => l10n.helpVideo1Title,
      subtitle: (l10n) => l10n.helpVideo1Subtitle,
      duration: '2:35'),
  _VideoTutorial(
      icon: Icons.bar_chart_rounded,
      title: (l10n) => l10n.helpVideo2Title,
      subtitle: (l10n) => l10n.helpVideo2Subtitle,
      duration: '1:48'),
  _VideoTutorial(
      icon: Icons.workspace_premium_rounded,
      title: (l10n) => l10n.helpVideo3Title,
      subtitle: (l10n) => l10n.helpVideo3Subtitle,
      duration: '2:10'),
];

class _FaqItem {
  final IconData icon;
  final String Function(AppLocalizations) question;
  final String Function(AppLocalizations) answer;
  _FaqItem(
      {required this.icon, required this.question, required this.answer});
}

final List<_FaqItem> _faqItems = [
  _FaqItem(
      icon: Icons.play_circle_outline_rounded,
      question: (l10n) => l10n.helpFaqQ1,
      answer: (l10n) => l10n.helpFaqA1),
  _FaqItem(
      icon: Icons.wifi_off_rounded,
      question: (l10n) => l10n.helpFaqQ2,
      answer: (l10n) => l10n.helpFaqA2),
  _FaqItem(
      icon: Icons.bar_chart_rounded,
      question: (l10n) => l10n.helpFaqQ3,
      answer: (l10n) => l10n.helpFaqA3),
  _FaqItem(
      icon: Icons.lock_reset_rounded,
      question: (l10n) => l10n.helpFaqQ4,
      answer: (l10n) => l10n.helpFaqA4),
  _FaqItem(
      icon: Icons.workspace_premium_rounded,
      question: (l10n) => l10n.helpFaqQ5,
      answer: (l10n) => l10n.helpFaqA5),
];

class StudentHelpScreen extends ConsumerStatefulWidget {
  final StudentSession session;

  const StudentHelpScreen({super.key, required this.session});

  @override
  ConsumerState<StudentHelpScreen> createState() => _StudentHelpScreenState();
}

class _StudentHelpScreenState extends ConsumerState<StudentHelpScreen> {
  String? _appVersion; // null until PackageInfo resolves — never guessed
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {
      // silent — version chip simply won't render, same as login_screen.dart
    }
  }

  List<_FaqItem> _filteredFaq(AppLocalizations l10n) {
    if (_query.isEmpty) return _faqItems;
    return _faqItems
        .where((item) =>
            item.question(l10n).toLowerCase().contains(_query) ||
            item.answer(l10n).toLowerCase().contains(_query))
        .toList();
  }

  /// Opens [url] in the system browser/app, matching update_service.dart's
  /// try/catch convention but surfacing failure via a SnackBar (same
  /// pattern as sync_images_button.dart) instead of swallowing it, since
  /// this is a user-initiated tap, not a background operation.
  Future<void> _launchUrl(String url, AppLocalizations l10n) async {
    try {
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.helpLinkOpenError),
              backgroundColor: AppColors.err),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.helpLinkOpenError),
              backgroundColor: AppColors.err),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pal = StudentPalette(Theme.of(context).brightness == Brightness.dark);
    return _body(l10n, pal);
  }

  Widget _body(AppLocalizations l10n, StudentPalette pal) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _banner(l10n),
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            final left = _leftColumn(l10n, pal);
            final right = _rightColumn(l10n, pal);
            if (!isWide) {
              return Column(children: [left, const SizedBox(height: 20), right]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: left),
                const SizedBox(width: 20),
                Expanded(flex: 1, child: right),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _banner(AppLocalizations l10n) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.helpBannerTitle,
            style: AppTextStyles.titleLarge.copyWith(
                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
        const SizedBox(height: 8),
        Text(l10n.helpBannerSubtitle,
            style: AppTextStyles.bodyMedium
                .copyWith(color: Colors.white.withValues(alpha: 0.9))),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _BannerKpi(
              icon: Icons.help_outline_rounded,
              label: l10n.helpKpiFaqLabel,
              value: l10n.helpKpiFaqValue(_faqItems.length),
            ),
            _BannerKpi(
              icon: Icons.headset_mic_rounded,
              label: l10n.helpKpiSupportLabel,
              value: l10n.onlineStatus,
            ),
            _BannerKpi(
              icon: Icons.info_outline_rounded,
              label: l10n.helpKpiVersionLabel,
              value: _appVersion != null ? 'v$_appVersion' : '—',
            ),
          ],
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.secondary, AppColors.flame],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadii.roundedXl,
      ),
      // dark6.jpg has a decorative headset/chat illustration on the right —
      // no real illustration asset exists, so it's approximated with layered
      // icon badges (only shown once there's room for it).
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 640) return content;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: content),
            const SizedBox(width: 16),
            const _BannerIllustration(),
          ],
        );
      }),
    );
  }

  Widget _leftColumn(AppLocalizations l10n, StudentPalette pal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          pal: pal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.helpFaqSectionTitle,
                  style: AppTextStyles.titleMedium
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.helpFaqSearchHint,
                  prefixIcon: Icon(Icons.search_rounded,
                      color: pal.ink3, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final items = _filteredFaq(l10n);
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(l10n.helpFaqNoResults,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: pal.ink3)),
                    ),
                  );
                }
                return Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        ExpansionTile(
                          // Keyed on the FAQ item's own (stable, module-level
                          // singleton) identity, not the loop index — so
                          // Flutter doesn't reuse expanded/collapsed state
                          // across different questions when search
                          // filtering changes the list's size/order.
                          key: ObjectKey(items[i]),
                          initiallyExpanded: i == 0 && _query.isEmpty,
                          tilePadding: EdgeInsets.zero,
                          childrenPadding:
                              const EdgeInsets.only(bottom: 12, right: 4),
                          leading:
                              Icon(items[i].icon, color: AppColors.brand, size: 20),
                          title: Text(items[i].question(l10n),
                              style: AppTextStyles.bodyLarge
                                  .copyWith(fontWeight: FontWeight.w600)),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 32),
                              child: Text(items[i].answer(l10n),
                                  style: AppTextStyles.bodyMedium),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _card(
          pal: pal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.helpVideoSectionTitle,
                  style: AppTextStyles.titleMedium
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final tutorial in _videoTutorials)
                    _VideoCard(
                      tutorial: tutorial,
                      pal: pal,
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.comingSoon))),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _card(
          pal: pal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.helpTroubleshootSectionTitle,
                  style: AppTextStyles.titleMedium
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _TipTile(
                    icon: Icons.wifi_rounded,
                    title: l10n.helpTroubleshootInternetTitle,
                    desc: l10n.helpTroubleshootInternetDesc,
                    pal: pal,
                  ),
                  _TipTile(
                    icon: Icons.refresh_rounded,
                    title: l10n.helpTroubleshootRestartTitle,
                    desc: l10n.helpTroubleshootRestartDesc,
                    pal: pal,
                  ),
                  _TipTile(
                    icon: Icons.person_outline_rounded,
                    title: l10n.helpTroubleshootTeacherTitle,
                    desc: l10n.helpTroubleshootTeacherDesc,
                    pal: pal,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rightColumn(AppLocalizations l10n, StudentPalette pal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _contactCard(l10n, pal),
        const SizedBox(height: 20),
        _card(
          pal: pal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.helpAboutSectionTitle,
                  style: AppTextStyles.titleMedium
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _infoRow(l10n.helpAboutVersionLabel,
                  _appVersion != null ? 'v$_appVersion' : '—', pal),
              const Divider(height: 20),
              Consumer(builder: (context, ref, _) {
                final signal = ref.watch(signalProvider);
                final isOnline =
                    !signal.checking && signal.tier != SignalTier.none;
                final label = signal.checking
                    ? l10n.serverChecking
                    : (isOnline ? l10n.onlineStatus : l10n.offlineMode);
                final color = signal.checking
                    ? AppColors.brand
                    : (isOnline ? AppColors.ok : pal.ink3);
                return _infoRow(l10n.helpAboutServerLabel, label, pal,
                    valueColor: color);
              }),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _card(
          pal: pal,
          color: AppColors.secondaryMuted,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.helpNoAnswerTitle,
                  style: AppTextStyles.titleMedium.copyWith(
                      fontWeight: FontWeight.w700, color: AppColors.amberInk)),
              const SizedBox(height: 8),
              Text(l10n.helpNoAnswerDesc,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.amberInk)),
            ],
          ),
        ),
      ],
    );
  }

  /// "Связаться с поддержкой" card (dark6.jpg) — the real Telegram bot
  /// deep-link + generic support contact row (no fabricated personal
  /// name/phone/email, see file-header note).
  Widget _contactCard(AppLocalizations l10n, StudentPalette pal) {
    return _card(
      pal: pal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.helpContactSectionTitle,
              style:
                  AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _launchUrl(_kTelegramBotUrl, l10n),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(l10n.helpOpenTelegramBot),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const RoundedRectangleBorder(
                    borderRadius: AppRadii.roundedMd),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.secondaryMuted,
                child: Icon(Icons.person_rounded,
                    color: AppColors.brand, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_kAdminRole,
                        style: AppTextStyles.caption.copyWith(color: pal.ink3)),
                    Text(_kAdminName,
                        style: AppTextStyles.labelLarge.copyWith(
                            fontWeight: FontWeight.w700, color: pal.ink1)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _contactInfoRow(Icons.email_rounded, _kAdminEmail, pal),
          const SizedBox(height: 8),
          _contactInfoRow(Icons.phone_rounded, _kAdminPhone, pal),
          const SizedBox(height: 8),
          _contactInfoRow(Icons.schedule_rounded, _kAdminHours, pal),
        ],
      ),
    );
  }

  Widget _contactInfoRow(IconData icon, String text, StudentPalette pal) {
    return Row(
      children: [
        Icon(icon, size: 16, color: pal.ink3),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: AppTextStyles.bodyMedium.copyWith(color: pal.ink2)),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value, StudentPalette pal,
      {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTextStyles.bodyMedium.copyWith(color: pal.ink2)),
        Text(value,
            style: AppTextStyles.labelLarge.copyWith(
                color: valueColor ?? pal.ink1, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _card(
      {required Widget child, required StudentPalette pal, Color? color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? pal.surface,
        borderRadius: AppRadii.roundedXl,
        border: Border.all(color: pal.border),
      ),
      child: child,
    );
  }
}

class _BannerKpi extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _BannerKpi(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: AppRadii.roundedMd,
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.caption
                        .copyWith(color: Colors.white.withValues(alpha: 0.85))),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelLarge.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final StudentPalette pal;

  const _TipTile(
      {required this.icon,
      required this.title,
      required this.desc,
      required this.pal});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.chipBg,
        borderRadius: AppRadii.roundedMd,
        border: Border.all(color: pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.brand, size: 20),
          const SizedBox(height: 8),
          Text(title,
              style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.w700, color: pal.ink1)),
          const SizedBox(height: 4),
          Text(desc,
              style: AppTextStyles.caption.copyWith(color: pal.ink2)),
        ],
      ),
    );
  }
}

/// Approximated headset/chat illustration for the banner's right side
/// (dark6.jpg) — no real illustration asset exists in this app, so it's
/// built from layered Material icon badges instead of an image.
class _BannerIllustration extends StatelessWidget {
  const _BannerIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
          ),
          const Icon(Icons.headset_mic_rounded, color: Colors.white, size: 46),
          Positioned(
            right: 4,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: const Icon(Icons.chat_bubble_rounded,
                  color: AppColors.flame, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

/// Video-tutorial card (dark6.jpg "Видео-инструкции и советы") — the
/// thumbnail is an approximated gradient + play icon since no real video
/// asset/hosting exists (see file-header note); tapping shows the same
/// "Скоро" SnackBar used elsewhere in this cabinet, never a fake player.
class _VideoCard extends StatelessWidget {
  final _VideoTutorial tutorial;
  final StudentPalette pal;
  final VoidCallback onTap;

  const _VideoCard(
      {required this.tutorial, required this.pal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      borderRadius: AppRadii.roundedMd,
      onTap: onTap,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: pal.chipBg,
          borderRadius: AppRadii.roundedMd,
          border: Border.all(color: pal.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 110,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.secondaryMuted, AppColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(tutorial.icon,
                      color: Colors.white.withValues(alpha: 0.55), size: 36),
                ),
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: AppColors.brand, size: 24),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tutorial.duration,
                        style: AppTextStyles.caption.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tutorial.title(l10n),
                      style: AppTextStyles.labelLarge.copyWith(
                          fontWeight: FontWeight.w700, color: pal.ink1)),
                  const SizedBox(height: 2),
                  Text(tutorial.subtitle(l10n),
                      style: AppTextStyles.caption.copyWith(color: pal.ink3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
