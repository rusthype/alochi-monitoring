// lib/core/engine/question_widgets.dart
// Reusable question widgets for all 7 question types.
// Extracted and generalised from interhouse_runner.dart.
// Engine-agnostic: works with Question model from test_models.dart.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../shared/widgets/app_network_image.dart';
import '../../shared/theme/app_theme.dart';
import 'test_models.dart';

/// Inline SVG diagram (math geometry questions). Rendered above the options,
/// centered, in the same slot the raster image uses — keeps the monitoring look.
Widget _buildQuestionSvg(String svg, {double height = 130}) => Container(
      margin: const EdgeInsets.only(bottom: 4),
      alignment: Alignment.center,
      child: SvgPicture.string(
        svg,
        height: height,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => SizedBox(height: height),
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Image helper — dual-source: http(s) → AppNetworkImage, otherwise Image.asset
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildQuestionImage(
  String src, {
  double height = 160,
  BorderRadius? borderRadius,
}) {
  final br = borderRadius ?? BorderRadius.circular(10);
  final isNetwork =
      src.startsWith('http://') || src.startsWith('https://');

  if (isNetwork) {
    return SizedBox(
      width: double.infinity,
      child: Center(
        child: AppNetworkImage(
          url: src,
          height: height,
          fit: BoxFit.contain,
          borderRadius: br,
          errorWidget: _brokenImagePlaceholder(height),
        ),
      ),
    );
  }

  return SizedBox(
    width: double.infinity,
    child: Center(
      child: ClipRRect(
        borderRadius: br,
        child: Image.asset(
          src,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _brokenImagePlaceholder(height),
        ),
      ),
    ),
  );
}

Widget _brokenImagePlaceholder(double height) => Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.err.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: Icon(Icons.broken_image_outlined, color: AppColors.ink3),
      ),
    );

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Numbered badge (1-based label, engine passes 0-based index).
class EngineQNum extends StatelessWidget {
  final int index;
  const EngineQNum(this.index, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.brandLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.brand,
          ),
        ),
      );
}

/// Option row used by text_choice and image_choice.
class EngineOptionRow extends StatelessWidget {
  final String label;   // "A", "B", "C", "D"
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const EngineOptionRow({
    super.key,
    required this.label,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF7ED) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border,
              width: selected ? 2 : 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.brand.withValues(alpha: .12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    )
                  ]
                : null,
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? AppColors.brand : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? AppColors.brand : const Color(0xFFD4D4D8),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected ? Colors.white : const Color(0xFFA1A1AA),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color:
                      selected ? const Color(0xFF7C2D12) : AppColors.ink1,
                ),
              ),
            ),
            if (selected)
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded,
                    size: 12, color: Colors.white),
              ),
          ]),
        ),
      );
}

/// Shared text field decoration used across spelling / sentence_order /
/// fill_blank input widgets.
InputDecoration _inputDecoration({String hintText = 'Javob...'}) =>
    InputDecoration(
      hintText: hintText,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.brand, width: 2),
      ),
      filled: true,
      fillColor: AppColors.bg,
    );

// ─────────────────────────────────────────────────────────────────────────────
// 1. TextChoiceWidget — type: text_choice
// ─────────────────────────────────────────────────────────────────────────────

/// Renders a plain multiple-choice question (no image).
/// [answer] — currently selected index or null.
/// [onSelect] — called with the chosen 0-based index.
class TextChoiceWidget extends StatelessWidget {
  final int index;
  final Question question;
  final int? answer;
  final void Function(int) onSelect;

  const TextChoiceWidget({
    super.key,
    required this.index,
    required this.question,
    required this.answer,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    assert(question.type == QuestionType.textChoice,
        'TextChoiceWidget received wrong type: ${question.type}');

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EngineQNum(index),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              question.q ?? '',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink1,
                height: 1.4,
              ),
            ),
          ),
        ]),
        if (question.svg != null && question.svg!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildQuestionSvg(question.svg!),
        ],
        const SizedBox(height: 10),
        ...List.generate(question.opts.length, (i) => EngineOptionRow(
              label: String.fromCharCode(65 + i), // A, B, C…
              text: question.opts[i],
              selected: answer == i,
              onTap: () => onSelect(i),
            )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. ImageChoiceWidget — type: image_choice
// ─────────────────────────────────────────────────────────────────────────────

/// Renders a multiple-choice question with an optional image above the options.
/// Supports both asset paths and http(s) URLs.
class ImageChoiceWidget extends StatelessWidget {
  final int index;
  final Question question;
  final int? answer;
  final void Function(int) onSelect;

  const ImageChoiceWidget({
    super.key,
    required this.index,
    required this.question,
    required this.answer,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    assert(question.type == QuestionType.imageChoice,
        'ImageChoiceWidget received wrong type: ${question.type}');

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          EngineQNum(index),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              question.q ?? '',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink1,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (question.img != null && question.img!.isNotEmpty)
          _buildQuestionImage(question.img!, height: 160),
        const SizedBox(height: 10),
        ...List.generate(question.opts.length, (i) => EngineOptionRow(
              label: String.fromCharCode(65 + i),
              text: question.opts[i],
              selected: answer == i,
              onTap: () => onSelect(i),
            )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. SpellingWidget — type: spelling
// ─────────────────────────────────────────────────────────────────────────────

/// Scrambled letters → user types the correct word.
/// Controller is managed by [TestEngine] to persist across rebuilds.
class SpellingWidget extends StatelessWidget {
  final int index;
  final Question question;
  final TextEditingController controller;
  final void Function(String) onChanged;

  const SpellingWidget({
    super.key,
    required this.index,
    required this.question,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    assert(question.type == QuestionType.spelling,
        'SpellingWidget received wrong type: ${question.type}');

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          EngineQNum(index),
          const SizedBox(width: 10),
          const Text(
            'Harflarni to\'g\'ri joylashtiring',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDDD6FE)),
          ),
          child: Text(
            question.scramble ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6D28D9),
              letterSpacing: 4,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          onChanged: (v) => onChanged(v.toLowerCase()),
          decoration: _inputDecoration(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. SentenceOrderWidget — type: sentence_order
// ─────────────────────────────────────────────────────────────────────────────

/// Scrambled words → user types the sentence in correct order.
class SentenceOrderWidget extends StatelessWidget {
  final int index;
  final Question question;
  final TextEditingController controller;
  final void Function(String) onChanged;

  const SentenceOrderWidget({
    super.key,
    required this.index,
    required this.question,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    assert(question.type == QuestionType.sentenceOrder,
        'SentenceOrderWidget received wrong type: ${question.type}');

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          EngineQNum(index),
          const SizedBox(width: 10),
          const Text(
            'Jumlani to\'g\'ri tartibga soling',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.brandLight,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: AppColors.brand.withValues(alpha: .3)),
          ),
          child: Text(
            question.words ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration:
              _inputDecoration(hintText: 'To\'liq jumlani yozing...'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. ReadingPassageWidget — renders the passage card (img + title + text)
//    Used inside ReadingSectionWidget; also exported for custom layouts.
// ─────────────────────────────────────────────────────────────────────────────

class ReadingPassageWidget extends StatelessWidget {
  final ReadingSection reading;

  const ReadingPassageWidget({super.key, required this.reading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (reading.img != null && reading.img!.isNotEmpty)
          _buildQuestionImage(reading.img!, height: 200),
        if (reading.img != null && reading.img!.isNotEmpty)
          const SizedBox(height: 12),
        Text(
          reading.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.ink1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          reading.text,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: AppColors.ink2,
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6 & 7. YesNoWidget / FillBlankWidget — rendered inside reading sections
//        but also usable stand-alone in other section types.
// ─────────────────────────────────────────────────────────────────────────────

/// Yes/No toggle — type: yes_no
/// [answer] — "YES", "NO", or null.
class YesNoWidget extends StatelessWidget {
  final int index;
  final Question question;
  final String? answer;
  final void Function(String) onSelect;

  const YesNoWidget({
    super.key,
    required this.index,
    required this.question,
    required this.answer,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    assert(question.type == QuestionType.yesNo,
        'YesNoWidget received wrong type: ${question.type}');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        EngineQNum(index),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            question.q ?? '',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _YesNoButton(
            label: 'YES',
            color: AppColors.ok,
            selected: answer == 'YES',
            onTap: () => onSelect('YES'),
          ),
          const SizedBox(width: 8),
          _YesNoButton(
            label: 'NO',
            color: AppColors.err,
            selected: answer == 'NO',
            onTap: () => onSelect('NO'),
          ),
        ]),
      ]),
    );
  }
}

class _YesNoButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _YesNoButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: .3),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : color,
            ),
          ),
        ),
      );
}

/// Fill-in-the-blank text input — type: fill_blank
/// Uses a StatefulWidget to own its TextEditingController when no external
/// controller is provided (typical for reading sub-questions).
class FillBlankWidget extends StatefulWidget {
  final int index;
  final Question question;
  final String initialValue;
  final void Function(String) onChanged;

  const FillBlankWidget({
    super.key,
    required this.index,
    required this.question,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<FillBlankWidget> createState() => _FillBlankWidgetState();
}

class _FillBlankWidgetState extends State<FillBlankWidget> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.question.type == QuestionType.fillBlank,
        'FillBlankWidget received wrong type: ${widget.question.type}');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          EngineQNum(widget.index),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.question.q ?? '',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink1,
                height: 1.4,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _ctrl,
          onChanged: widget.onChanged,
          decoration: _inputDecoration(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReadingSectionWidget — renders passage + all sub-questions
// ─────────────────────────────────────────────────────────────────────────────

/// Renders a full reading section: passage card + yes_no / text_choice /
/// fill_blank sub-questions. [answers] and [onAnswer] use keys "0", "1"…
/// (index within container.qs), NOT the full "SectionName/i" key — the engine
/// builds the full key before calling this widget.
class ReadingSectionWidget extends StatelessWidget {
  final SectionData section;

  /// answers keyed by sub-question index as string: "0", "1", …
  final Map<String, dynamic> answers;

  /// Called with (subIndex, value) — value is int for mc, String for yn/fill.
  final void Function(int subIndex, dynamic value) onAnswer;

  const ReadingSectionWidget({
    super.key,
    required this.section,
    required this.answers,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    assert(section.isReading, 'ReadingSectionWidget requires a reading section');
    final reading = section.readingContainer!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReadingPassageWidget(reading: reading),
        ...List.generate(reading.qs.length, (i) {
          final q = reading.qs[i];
          final ansKey = i.toString();

          switch (q.type) {
            case QuestionType.yesNo:
              return YesNoWidget(
                index: i,
                question: q,
                answer: answers[ansKey] as String?,
                onSelect: (v) => onAnswer(i, v),
              );

            case QuestionType.textChoice:
              return TextChoiceWidget(
                index: i,
                question: q,
                answer: answers[ansKey] as int?,
                onSelect: (v) => onAnswer(i, v),
              );

            case QuestionType.fillBlank:
              return FillBlankWidget(
                index: i,
                question: q,
                initialValue:
                    answers[ansKey] is String ? answers[ansKey] as String : '',
                onChanged: (v) => onAnswer(i, v),
              );

            default:
              // Unexpected sub-question type in reading container
              return const SizedBox.shrink();
          }
        }),
      ],
    );
  }
}
