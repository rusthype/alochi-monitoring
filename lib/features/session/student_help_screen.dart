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
// - Video-instruction cards: no real video hosting exists in this app, so
//   the mockup's 3 video cards are replaced with one "Скоро"
//   (`comingSoon`, same key/visual language as student_sidebar.dart's
//   disabled-item badge) placeholder block instead of fabricated
//   thumbnails/durations.
// - Telegram-bot button: real, live deep-link to the school bot
//   (`https://t.me/alochipoll_bot`, `@alochipoll_bot`) via url_launcher.
// - Support contact card: no named admin contact record exists in this
//   codebase, so instead of a fabricated person (name/phone/email) it links
//   to the real, live generic support account `@AlochiSupport`.
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
const _kSupportTelegramUrl = 'https://t.me/AlochiSupport';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
      ),
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
              Row(
                children: [
                  Text(l10n.helpVideoSectionTitle,
                      style: AppTextStyles.titleMedium
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(l10n.comingSoon,
                        style: AppTextStyles.caption.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 9)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: pal.chipBg,
                  borderRadius: AppRadii.roundedMd,
                  border: Border.all(color: pal.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.smart_display_outlined,
                        color: pal.ink3, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(l10n.helpVideoComingSoonDesc,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: pal.ink2)),
                    ),
                  ],
                ),
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
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _launchUrl(_kSupportTelegramUrl, l10n),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pal.chipBg,
                borderRadius: AppRadii.roundedMd,
                border: Border.all(color: pal.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                        color: AppColors.secondaryMuted, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Icon(Icons.support_agent_rounded,
                        color: AppColors.brand, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.helpSupportContactLabel,
                            style: AppTextStyles.labelLarge.copyWith(
                                fontWeight: FontWeight.w700, color: pal.ink1)),
                        Text(l10n.helpSupportContactHandle,
                            style: AppTextStyles.caption
                                .copyWith(color: pal.ink3)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: pal.ink3),
                ],
              ),
            ),
          ),
        ],
      ),
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
