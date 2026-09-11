// lib/features/diagnostic/widgets/diagnostic_question_dots.dart
//
// Horizontal scrolling question-number carousel for a fixed-variant
// attempt — replaces the old in-line dot row that used to live inside
// DiagnosticBottomNav. Only rendered when
// DiagnosticTestRunnerScreen._isFixedVariantAttempt is true; never shown
// for the CAT/adaptive flow.
import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

class DiagnosticQuestionDots extends StatefulWidget {
  final int total;
  final int currentIndex; // 0-based
  final Set<int> answeredIndexes; // 0-based
  final ValueChanged<int> onSelectIndex;

  const DiagnosticQuestionDots({
    super.key,
    required this.total,
    required this.currentIndex,
    required this.answeredIndexes,
    required this.onSelectIndex,
  });

  @override
  State<DiagnosticQuestionDots> createState() =>
      _DiagnosticQuestionDotsState();
}

class _DiagnosticQuestionDotsState extends State<DiagnosticQuestionDots> {
  static const double _itemWidth = 40;
  static const double _gap = 8;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(
          widget.currentIndex,
          animate: false,
        ));
  }

  @override
  void didUpdateWidget(covariant DiagnosticQuestionDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollTo(widget.currentIndex));
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollTo(int index, {bool animate = true}) {
    if (!_scrollCtrl.hasClients) return;
    final viewport = _scrollCtrl.position.viewportDimension;
    final target = (index * (_itemWidth + _gap) - viewport / 2 + _itemWidth / 2)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    if (animate) {
      _scrollCtrl.animateTo(target,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _scrollCtrl.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        itemCount: widget.total,
        separatorBuilder: (_, __) => const SizedBox(width: _gap),
        itemBuilder: (context, index) {
          final isCurrent = index == widget.currentIndex;
          final isAnswered = widget.answeredIndexes.contains(index);
          final Color bg;
          final Color fg;
          if (isCurrent) {
            bg = AppColors.brand;
            fg = Colors.white;
          } else if (isAnswered) {
            bg = AppColors.emeraldMuted;
            fg = AppColors.emeraldInk;
          } else {
            bg = AppColors.pageBg;
            fg = AppColors.ink3;
          }
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => widget.onSelectIndex(index),
            child: Container(
              width: _itemWidth,
              height: _itemWidth,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: isCurrent || isAnswered
                    ? null
                    : Border.all(color: AppColors.border),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: AppColors.brand.withValues(alpha: 0.35),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                '${index + 1}'.padLeft(2, '0'),
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          );
        },
      ),
    );
  }
}
