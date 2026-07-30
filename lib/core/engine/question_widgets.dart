// lib/core/engine/question_widgets.dart
// Reusable question widgets for all 7 question types.
// Extracted and generalised from interhouse_runner.dart.
// Engine-agnostic: works with Question model from test_models.dart.

import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

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
  double height = 270,
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
            color: selected ? AppColors.secondaryMuted : AppColors.surface,
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
                color: selected ? AppColors.brand : AppColors.chipBg,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? AppColors.brand : AppColors.chipBorder,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: selected ? Colors.white : AppColors.chipIcon,
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
                      selected ? AppColors.amberInk : AppColors.ink1,
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

/// Splits a `sentence_order` question's `words` field ('/'-delimited,
/// segments trimmed) into its display segments. Shared by
/// [SentenceOrderWidget] (tap-to-order UI) and [SentenceFreeTextWidget]
/// (free-text UI, English World "Writing") — both consume the same
/// backend `words` contract, so the parsing lives in one place.
List<String> _splitWords(String s) => s
    .split('/')
    .map((p) => p.trim())
    .where((p) => p.isNotEmpty)
    .toList();

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
          _buildQuestionImage(question.img!, height: 270),
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
        const SizedBox(height: 12),
        if (question.img != null && question.img!.isNotEmpty)
          _buildQuestionImage(question.img!, height: 270),
        if (question.img != null && question.img!.isNotEmpty)
          const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.violetMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.violetBorder),
          ),
          child: Text(
            question.scramble ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.violetInk,
              letterSpacing: 4,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          onChanged: (v) => onChanged(v.toLowerCase()),
          // Grade the pupil's answer as typed — autocorrect / suggestions would
          // silently rewrite a valid Uzbek word before it is ever scored.
          autocorrect: false,
          enableSuggestions: false,
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

/// Chronology / word-order question. The scrambled segments (from
/// [Question.words], split on '/') are shown as tappable rows; the pupil taps
/// them into the correct order instead of RE-TYPING long phrases by hand. The
/// old free-text field made a knowledge question fail on any typo, spacing or
/// apostrophe drift, so a pupil who knew the order still scored 0 — this is
/// acute for History chronology, whose segments are long event phrases.
///
/// The chosen order is written back to [controller] as the segments joined by
/// a plain space (and pushed via [onChanged]) — matching the stored
/// natural-sentence correct answer format (e.g. "It is a doll.") — so the
/// engine's controller-flush + scoring path compares like-for-like. State is
/// re-derived from the persisted [controller] text on init / widget-recycle
/// (via [_restoreOrdered], which matches known pool segments against the
/// saved text rather than splitting on a delimiter, since segments — e.g.
/// History chronology event phrases — may themselves contain spaces), so a
/// partly-built answer survives section switches.
class SentenceOrderWidget extends StatefulWidget {
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
  State<SentenceOrderWidget> createState() => _SentenceOrderWidgetState();
}

class _SentenceOrderWidgetState extends State<SentenceOrderWidget> {
  late List<String> _pool; // all segments (scrambled display order)
  late List<String> _ordered; // current selection, in chosen order

  // Splits the source [Question.words] pool, which is always '/'-delimited
  // regardless of segment content (segments may be single words or, for
  // History chronology, long multi-word event phrases). Delegates to the
  // top-level [_splitWords] shared with [SentenceFreeTextWidget].
  static List<String> _split(String s) => _splitWords(s);

  /// Reconstructs a previously-chosen order from the persisted, plain-space
  /// -joined answer text (see [_emit]). Cannot simply split [saved] on
  /// whitespace, since a [pool] segment may itself contain internal spaces
  /// (e.g. "Napoleon crowned emperor") — instead greedily matches the
  /// longest remaining pool segment against the front of the remaining text.
  /// Any unparsable leftover (e.g. answer text from a stale/incompatible
  /// format) is dropped rather than crashing.
  static List<String> _restoreOrdered(String saved, List<String> pool) {
    var rest = saved.trim();
    if (rest.isEmpty) return [];
    final remainingPool = List<String>.from(pool)
      ..sort((a, b) => b.length.compareTo(a.length));
    final result = <String>[];
    while (rest.isNotEmpty) {
      String? matched;
      for (final seg in remainingPool) {
        if (rest == seg || rest.startsWith('$seg ')) {
          matched = seg;
          break;
        }
      }
      if (matched == null) break;
      result.add(matched);
      remainingPool.remove(matched);
      rest = rest.length == matched.length
          ? ''
          : rest.substring(matched.length + 1);
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SentenceOrderWidget old) {
    super.didUpdateWidget(old);
    // Widget recycled for a different question/controller — re-derive state.
    if (old.question != widget.question ||
        old.controller != widget.controller) {
      _sync();
    }
  }

  void _sync() {
    _pool = _split(widget.question.words ?? '');
    // Restore any previously-chosen order from the persisted controller text.
    _ordered = _restoreOrdered(widget.controller.text, _pool);
  }

  List<String> get _remaining =>
      _pool.where((s) => !_ordered.contains(s)).toList();

  void _emit() {
    final joined = _ordered.join(' ');
    widget.controller.text = joined;
    widget.onChanged(joined);
  }

  void _add(String seg) {
    setState(() => _ordered = [..._ordered, seg]);
    _emit();
  }

  void _removeAt(int i) {
    setState(() => _ordered = [..._ordered]..removeAt(i));
    _emit();
  }

  void _clear() {
    setState(() => _ordered = []);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    assert(widget.question.type == QuestionType.sentenceOrder,
        'SentenceOrderWidget received wrong type: ${widget.question.type}');

    final remaining = _remaining;

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
          EngineQNum(widget.index),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Voqealarni to\'g\'ri tartibda belgilang',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink2,
              ),
            ),
          ),
          if (_ordered.isNotEmpty)
            GestureDetector(
              onTap: _clear,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  'Tozalash',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 12),

        // Chosen order — numbered, tap ✕ to remove.
        if (_ordered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'Quyidagi variantlarni to\'g\'ri ketma-ketlikda tanlang',
              style: TextStyle(fontSize: 13, color: AppColors.ink3),
            ),
          )
        else
          ...List.generate(
            _ordered.length,
            (i) => _OrderedRow(
              position: i + 1,
              text: _ordered[i],
              onRemove: () => _removeAt(i),
            ),
          ),

        // Remaining scrambled segments — tap + to append.
        if (remaining.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'VARIANTLAR',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: .5,
              color: AppColors.ink3,
            ),
          ),
          const SizedBox(height: 6),
          ...remaining.map((seg) => _ChoiceRow(
                text: seg,
                onTap: () => _add(seg),
              )),
        ],
      ]),
    );
  }
}

/// One row in the pupil's chosen order (numbered, removable).
class _OrderedRow extends StatelessWidget {
  final int position;
  final String text;
  final VoidCallback onRemove;

  const _OrderedRow({
    required this.position,
    required this.text,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.brandLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.brand.withValues(alpha: .35)),
        ),
        child: Row(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.brand,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$position',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.amberInk,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.brand),
          ),
        ]),
      );
}

/// One tappable unused segment (adds itself to the end of the chosen order).
class _ChoiceRow extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _ChoiceRow({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(children: [
            const Icon(Icons.add_circle_outline_rounded,
                size: 18, color: AppColors.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink1,
                  height: 1.35,
                ),
              ),
            ),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// 4b. SentenceFreeTextWidget — free-text alternative to SentenceOrderWidget,
//     used ONLY for the English World "Writing" section (test_engine.dart
//     _buildQuestionWidget branches on sectionName == 'Writing').
// ─────────────────────────────────────────────────────────────────────────────

/// Free-text `sentence_order` input, restricted to the English World
/// "Writing" section. [SentenceOrderWidget]'s tap-to-order chips are correct
/// for History chronology (the segments come only from the answer key, so
/// there is exactly one valid tap sequence), but they make English Writing's
/// contraction-equivalence grading (answer_normalization.dart,
/// TestScorer._normalize()) pointless: a pupil can only ever tap the
/// canonical segments, never type an equally-correct alternative form (e.g.
/// "they are" vs "They're"). This widget instead shows the
/// [Question.words] segments as a static prompt and lets the pupil type the
/// sentence freely — TestScorer grades the typed text exactly as it grades
/// any other free-text answer, contraction-equivalence included.
class SentenceFreeTextWidget extends StatelessWidget {
  final int index;
  final Question question;
  final TextEditingController controller;
  final void Function(String) onChanged;

  const SentenceFreeTextWidget({
    super.key,
    required this.index,
    required this.question,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    assert(question.type == QuestionType.sentenceOrder,
        'SentenceFreeTextWidget received wrong type: ${question.type}');

    final words = _splitWords(question.words ?? '');
    final prompt = words.join(' / ');

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
          EngineQNum(index),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              prompt,
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
          controller: controller,
          onChanged: onChanged,
          // Grade the pupil's answer as typed — autocorrect / suggestions
          // would silently rewrite a valid answer (e.g. a contraction) before
          // it is ever scored.
          autocorrect: false,
          enableSuggestions: false,
          decoration: _inputDecoration(),
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
          _buildQuestionImage(reading.img!, height: 270),
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
            label: AppLocalizations.of(context)!.yesOption,
            color: AppColors.ok,
            selected: answer == 'YES',
            onTap: () => onSelect('YES'),
          ),
          const SizedBox(width: 8),
          _YesNoButton(
            label: AppLocalizations.of(context)!.noOption,
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
          // Grade the pupil's answer as typed — autocorrect / suggestions would
          // silently rewrite a valid Uzbek word before it is ever scored.
          autocorrect: false,
          enableSuggestions: false,
          decoration: _inputDecoration(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ReadingBlockWidget — passage + sub-questions (whole-section or inline)
// ─────────────────────────────────────────────────────────────────────────────

/// Renders one reading passage + its yes_no / text_choice / fill_blank
/// sub-questions. [answers] and [onAnswer] use keys "0", "1"… (index within
/// [reading].qs), NOT the full engine key ("SectionName/i" or
/// "SectionName/i/j") — the caller builds the full key.
///
/// Reused for both shapes a reading passage can appear in:
///   - whole-section (Map-shaped) container → [ReadingSectionWidget] below,
///     [indexOffset] 0 (no sibling questions ahead of it in the section)
///   - an inline list item alongside sibling questions (Task 1.5,
///     `_buildInlineReading` in test_engine.dart) → [indexOffset] is the
///     running question count so far, so EngineQNum continues counting
///     instead of restarting at 1 for every passage.
///
/// Scope note (TZ §3/§10): the sub-question switch below only handles
/// yes_no, text_choice, fill_blank — spelling/sentence_order/image_choice
/// (and a nested reading) fall through to the SizedBox.shrink() default.
/// TZ §3 explicitly excludes image_choice from reading passages and §10
/// leaves it as an open lead decision, so this is a deliberate scope
/// boundary carried over unchanged, not something forgotten here.
class ReadingBlockWidget extends StatelessWidget {
  final ReadingSection reading;

  /// answers keyed by sub-question index as string: "0", "1", …
  final Map<String, dynamic> answers;

  /// Called with (subIndex, value) — value is int for mc, String for yn/fill.
  final void Function(int subIndex, dynamic value) onAnswer;

  /// Added to each sub-question's list index before it reaches EngineQNum —
  /// lets display numbering run continuously across the parent section.
  final int indexOffset;

  const ReadingBlockWidget({
    super.key,
    required this.reading,
    required this.answers,
    required this.onAnswer,
    this.indexOffset = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReadingPassageWidget(reading: reading),
        ...List.generate(reading.qs.length, (i) {
          final q = reading.qs[i];
          final ansKey = i.toString();
          final displayIndex = indexOffset + i;

          switch (q.type) {
            case QuestionType.yesNo:
              return YesNoWidget(
                index: displayIndex,
                question: q,
                answer: answers[ansKey] as String?,
                onSelect: (v) => onAnswer(i, v),
              );

            case QuestionType.textChoice:
              return TextChoiceWidget(
                index: displayIndex,
                question: q,
                answer: answers[ansKey] as int?,
                onSelect: (v) => onAnswer(i, v),
              );

            case QuestionType.fillBlank:
              return FillBlankWidget(
                index: displayIndex,
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

/// Renders a full reading section: passage card + sub-questions. [answers]
/// and [onAnswer] use keys "0", "1"… (index within container.qs), NOT the
/// full "SectionName/i" key — the engine builds the full key before calling
/// this widget. Thin adapter over [ReadingBlockWidget] for the whole-section
/// (Map-shaped) case — no index offset, since a whole-section reading has no
/// sibling questions ahead of it. Public API/assert/"0"/"1" sub-key contract
/// unchanged; output is identical to before this widget was split.
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
    return ReadingBlockWidget(
      reading: section.readingContainer!,
      answers: answers,
      onAnswer: onAnswer,
    );
  }
}
