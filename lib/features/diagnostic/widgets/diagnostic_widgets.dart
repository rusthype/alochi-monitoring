// lib/features/diagnostic/widgets/diagnostic_widgets.dart
//
// Small shared visual pieces for the diagnostic kiosk flow screens, copied
// (never imported) from lib/features/session/group_select_screen.dart and
// student_entry_screen.dart's step-indicator / capsule-navbar / pill-button /
// avatar-card / floating-CTA patterns. Kept in one file to avoid tripling
// the same boilerplate across school/class/student select screens — this
// file itself never imports anything from lib/features/session/.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

/// Double-bordered rounded card chrome, copied from the session flow's
/// private `_DoubleBezel` widget.
class DiagnosticDoubleBezel extends StatelessWidget {
  final Widget child;
  const DiagnosticDoubleBezel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: child,
      ),
    );
  }
}

/// Floating capsule top bar: back button + centered uppercase title.
class DiagnosticTopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  const DiagnosticTopBar({super.key, required this.title, this.onBack});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DiagnosticDoubleBezel(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: onBack ??
                  () => context.canPop() ? context.pop() : context.go('/'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back_rounded,
                      size: 18, color: AppColors.brand),
                  const SizedBox(width: 6),
                  Text(
                    l10n.backBtn,
                    style: const TextStyle(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Text(
                title.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ink1,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 60),
          ],
        ),
      ),
    );
  }
}

/// "• Qadam N" step badge, copied from group_select_screen's
/// `_buildStepIndicator`.
class DiagnosticStepIndicator extends StatelessWidget {
  final String text;
  final bool active;
  const DiagnosticStepIndicator(this.text, {super.key, this.active = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppColors.brand : AppColors.gray200,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
            color: AppColors.ink3,
          ),
        ),
      ],
    );
  }
}

/// Pill-shaped selectable button, copied from group_select_screen's
/// `_buildGroupPill`.
class DiagnosticPillButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const DiagnosticPillButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brand : AppColors.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: isSelected ? AppColors.brand : AppColors.border,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: AppColors.brand.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.ink1,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 2-column avatar-initial card, copied from student_entry_screen's
/// private `_StudentCard` (context-menu/copy-name affordance dropped —
/// not part of this kiosk flow's scope).
class DiagnosticStudentCard extends StatelessWidget {
  final String name;
  final bool isSelected;
  final VoidCallback onTap;
  const DiagnosticStudentCard({
    super.key,
    required this.name,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.brand.withValues(alpha: 0.05)
                : AppColors.pageBg,
            border: Border.all(
              color: isSelected
                  ? AppColors.brand.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.brand : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.brand : AppColors.border,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.ink2,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: isSelected ? AppColors.brand : AppColors.ink1,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.brand : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.brand : Colors.grey.shade300,
                  ),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 10)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small static "O'zbek" / "Русский" language chip — shown next to a class
/// or student so a proctor never puts a student in the wrong-language test.
class DiagnosticLanguageBadge extends StatelessWidget {
  final String language; // 'uz' | 'ru'
  const DiagnosticLanguageBadge({super.key, required this.language});

  @override
  Widget build(BuildContext context) {
    final isRu = language == 'ru';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isRu ? Colors.purple : Colors.teal).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        isRu ? 'Русский' : "O'zbek",
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isRu ? Colors.purple.shade700 : Colors.teal.shade700,
        ),
      ),
    );
  }
}

/// Floating pill CTA, copied from student_entry_screen's bottom action bar.
/// Caller wraps this in a `Positioned` inside a `Stack`.
class DiagnosticBottomCta extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool loading;
  final VoidCallback? onTap;
  const DiagnosticBottomCta({
    super.key,
    required this.label,
    required this.enabled,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(30),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 56,
              decoration: BoxDecoration(
                color: enabled ? AppColors.ink1 : AppColors.border,
                borderRadius: BorderRadius.circular(30),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 32,
                          offset: const Offset(0, 16),
                        ),
                      ]
                    : [],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: enabled ? AppColors.brand : Colors.grey.shade400,
                      shape: BoxShape.circle,
                    ),
                    child: loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.arrow_forward_rounded,
                            size: 16, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
