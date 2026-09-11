// lib/features/diagnostic/widgets/diagnostic_question_card.dart
//
// Question chrome: "N-savol" counter + flag/bookmark toggle, question text,
// and the image/SVG visual — moved essentially unchanged out of
// DiagnosticTestRunnerScreen._buildQuestionView (see git history), except
// the SVG render now has an errorBuilder (malformed svg_visual previously
// rendered as a blank/black box with no fallback).
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_network_image.dart';

class DiagnosticQuestionCard extends StatelessWidget {
  final int position;
  final String questionText;
  final String imageUrl;
  final String svgVisual;
  final bool flagged;

  /// Local UI-only bookmark toggle — no backend field/API call (YAGNI, per
  /// plan): purely lets a student mark a question to revisit visually.
  final VoidCallback onToggleFlag;

  /// Optional scratchpad entry point (fixed-variant only) — null on the
  /// CAT/adaptive flow, which renders no button and is otherwise unchanged.
  final VoidCallback? onOpenScratchpad;

  const DiagnosticQuestionCard({
    super.key,
    required this.position,
    required this.questionText,
    required this.imageUrl,
    required this.svgVisual,
    required this.flagged,
    required this.onToggleFlag,
    this.onOpenScratchpad,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$position-savol',
                style: const TextStyle(
                  color: AppColors.ink3,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onToggleFlag,
                    borderRadius: BorderRadius.circular(100),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            flagged ? Icons.flag : Icons.outlined_flag,
                            size: 16,
                            color: flagged ? AppColors.amber : AppColors.ink3,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.flagQuestionButton,
                            style: TextStyle(
                              color: flagged ? AppColors.amber : AppColors.ink3,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (onOpenScratchpad != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: onOpenScratchpad,
                      icon: const Text('✏️'),
                      label: Text(l10n.diagnosticScratchpadButton),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            questionText,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.ink1,
            ),
          ),
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            AppNetworkImage(
              url: imageUrl,
              height: 260,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(12),
            ),
          ] else if (svgVisual.isNotEmpty) ...[
            const SizedBox(height: 16),
            SvgPicture.string(
              svgVisual,
              height: 130,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 130,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.err.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.image_not_supported_outlined,
                    color: AppColors.ink3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
