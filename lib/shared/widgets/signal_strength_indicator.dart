// lib/shared/widgets/signal_strength_indicator.dart
//
// Dumb, presentation-only 4-bar cell-signal-style indicator. Purely a
// function of the SignalTier passed in — all measurement/polling lives in
// ConnectivityService, all reactive wiring lives in connectivity_provider.
import 'package:flutter/material.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/theme/app_colors.dart';

class SignalStrengthIndicator extends StatelessWidget {
  final SignalTier tier;
  final double barWidth;
  final double maxHeight;
  final double gap;

  const SignalStrengthIndicator({
    super.key,
    required this.tier,
    this.barWidth = 3,
    this.maxHeight = 12,
    this.gap = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (tier == SignalTier.none) {
      return Icon(Icons.close_rounded, size: maxHeight, color: AppColors.err);
    }

    // SignalTier.index: none=0, weak=1, fair=2, good=3, excellent=4 —
    // doubles directly as the filled-bar count.
    final filledBars = tier.index;

    return SizedBox(
      height: maxHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          final barHeight = maxHeight * ((i + 1) / 4);
          final filled = i < filledBars;
          return Padding(
            padding: EdgeInsets.only(right: i == 3 ? 0 : gap),
            child: Container(
              width: barWidth,
              height: barHeight,
              decoration: BoxDecoration(
                color: filled ? AppColors.ok : AppColors.ink3,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }),
      ),
    );
  }
}
