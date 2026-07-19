// lib/features/interhouse/interhouse_runner.dart
// Section-based test runner for Interhouse Grade 2
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../core/models/models.dart';
import 'interhouse_data.dart';
import 'interhouse_scorer.dart';
import 'interhouse_result_screen.dart';

class InterhouseRunner extends StatefulWidget {
  final bool isOnline;
  final StudentSession? session;
  final String? packageId; // required when isOnline
  final String? firstName;
  final String? lastName;
  final String? school;
  final int variant;
  final IhTestData testData;

  const InterhouseRunner({
    super.key,
    required this.isOnline,
    this.session,
    this.packageId,
    this.firstName,
    this.lastName,
    this.school,
    required this.variant,
    required this.testData,
  });

  @override
  State<InterhouseRunner> createState() => _InterhouseRunnerState();
}

class _InterhouseRunnerState extends State<InterhouseRunner>
    with TickerProviderStateMixin {
  int _sectionIdx = 0;
  Timer? _timer;
  late int _secs;

  // 30 questions × 72 seconds each
  static const int _total = 30;

  // Answer state
  final List<int?> _vocabAns = List.filled(6, null);
  final List<int?> _grammarAns = List.filled(6, null);
  final List<String> _spellingAns = List.generate(6, (_) => '');
  final List<dynamic> _readingAns = List.filled(6, null);
  final List<String> _sentenceAns = List.generate(6, (_) => '');

  // Text controllers for text fields (spelling & sentences)
  late final List<TextEditingController> _spellingCtrl;
  late final List<TextEditingController> _sentenceCtrl;

  late final AnimationController _fadeCtrl;

  // Section names
  static const _sectionNames = [
    'Vocabulary',
    'Grammar',
    'Spelling',
    'Reading',
    'Writing',
  ];

  IhVariant get _variant =>
      widget.testData.variants[widget.variant.toString()]!;

  @override
  void initState() {
    super.initState();
    _secs = _total * 72;

    _spellingCtrl = List.generate(6, (i) => TextEditingController());
    _sentenceCtrl = List.generate(6, (i) => TextEditingController());

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fadeCtrl.forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secs > 0) {
          _secs--;
        } else {
          _timer?.cancel();
          _finish();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeCtrl.dispose();
    for (final c in _spellingCtrl) {
      c.dispose();
    }
    for (final c in _sentenceCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  String get _timerText {
    final m = (_secs ~/ 60).toString().padLeft(2, '0');
    final s = (_secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _timerHot => _secs < 120;

  int _answeredInSection(int idx) {
    switch (idx) {
      case 0:
        return _vocabAns.where((a) => a != null).length;
      case 1:
        return _grammarAns.where((a) => a != null).length;
      case 2:
        return _spellingAns.where((s) => s.trim().isNotEmpty).length;
      case 3:
        return _readingAns.where((a) => a != null).length;
      case 4:
        return _sentenceAns.where((s) => s.trim().isNotEmpty).length;
      default:
        return 0;
    }
  }

  int get _totalAnswered =>
      _answeredInSection(0) +
      _answeredInSection(1) +
      _answeredInSection(2) +
      _answeredInSection(3) +
      _answeredInSection(4);

  String _studentName() {
    if (widget.isOnline) return widget.session?.studentName ?? '';
    final last = widget.lastName ?? '';
    final first = widget.firstName ?? '';
    return '$last $first'.trim();
  }

  void _goSection(int idx) {
    if (idx < 0 || idx >= 5) return;
    _fadeCtrl.forward(from: 0);
    setState(() => _sectionIdx = idx);
  }

  Future<void> _finish() async {
    _timer?.cancel();
    final l10n = AppLocalizations.of(context)!;
    final unanswered = _total - _totalAnswered;
    if (unanswered > 0) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.finishConfirmTitle,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(l10n.unansweredWarning(unanswered)),
          actions: [
            TextButton(
              onPressed: () {
                // Restart timer
                _timer = Timer.periodic(const Duration(seconds: 1), (_) {
                  if (!mounted) return;
                  setState(() {
                    if (_secs > 0) {
                      _secs--;
                    } else {
                      _timer?.cancel();
                      _finish();
                    }
                  });
                });
                Navigator.pop(context, false);
              },
              child: Text(l10n.backButton),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size(100, 40)),
              child: Text(l10n.finishBtn),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    // Sync spelling/sentence text controllers to lists
    for (int i = 0; i < 6; i++) {
      _spellingAns[i] = _spellingCtrl[i].text;
      _sentenceAns[i] = _sentenceCtrl[i].text;
    }

    final answers = {
      'vocab': List<int?>.from(_vocabAns),
      'grammar': List<int?>.from(_grammarAns),
      'spelling': List<String>.from(_spellingAns),
      'reading': List<dynamic>.from(_readingAns),
      'sentences': List<String>.from(_sentenceAns),
    };

    final result = IhScorer.score(
      _variant,
      answers,
      widget.testData.levels,
    );

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => InterhouseResultScreen(
          result: result,
          testData: widget.testData,
          variant: widget.variant,
          isOnline: widget.isOnline,
          session: widget.session,
          packageId: widget.packageId,
          firstName: widget.firstName,
          lastName: widget.lastName,
          school: widget.school,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = _total > 0 ? _totalAnswered / _total : 0.0;
    final isLast = _sectionIdx == 4;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        // Progress bar
        SizedBox(
          height: 4,
          child: Stack(children: [
            Container(
                width: double.infinity, height: 4, color: AppColors.border),
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: MediaQuery.sizeOf(context).width * progress,
              height: 4,
              decoration: BoxDecoration(
                color: progress >= 1.0 ? AppColors.ok : AppColors.brand,
                borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(3)),
              ),
            ),
          ]),
        ),

        // Top bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            Image.asset('assets/logo.png', width: 30, height: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_studentName(),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink1)),
                    const SizedBox(height: 2),
                    Row(children: [
                      const _Pill('Interhouse G2', AppColors.violet),
                      const SizedBox(width: 6),
                      _Pill(
                          'Variant ${widget.variant}', AppColors.brand),
                    ]),
                  ]),
            ),
            // Progress counter
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$_totalAnswered/$_total',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink1)),
                Text(l10n.answeredLabel,
                    style:
                        const TextStyle(fontSize: 9, color: AppColors.ink3)),
              ]),
            ),
            // Timer
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _timerHot
                    ? AppColors.errorMuted
                    : AppColors.secondaryMuted,
                border: Border.all(
                  color: _timerHot
                      ? AppColors.dangerBorder
                      : AppColors.amberBorder,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_timerText,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _timerHot
                            ? AppColors.error
                            : AppColors.amberInk)),
                Text(l10n.timeLeftLabel,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _timerHot
                            ? AppColors.error
                            : AppColors.brand)),
              ]),
            ),
          ]),
        ),

        // Section tabs
        Container(
          color: AppColors.surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(
              children: List.generate(5, (i) {
                final answered = _answeredInSection(i);
                final isActive = i == _sectionIdx;
                return GestureDetector(
                  onTap: () => _goSection(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isActive
                              ? AppColors.brand
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_sectionNames[i],
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: isActive
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: isActive
                                  ? AppColors.brand
                                  : AppColors.ink2)),
                      const SizedBox(width: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: answered == 6
                              ? AppColors.ok.withValues(alpha: .15)
                              : isActive
                                  ? AppColors.brandLight
                                  : AppColors.bg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$answered/6',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: answered == 6
                                    ? AppColors.ok
                                    : isActive
                                        ? AppColors.brand
                                        : AppColors.ink3)),
                      ),
                    ]),
                  ),
                );
              }),
            ),
          ),
        ),
        const Divider(height: 1),

        // Section body
        Expanded(
          child: FadeTransition(
            opacity: _fadeCtrl,
            child: _buildSectionBody(),
          ),
        ),

        // Bottom nav
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: const Border(top: BorderSide(color: AppColors.border)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 8,
                  offset: const Offset(0, -2))
            ],
          ),
          child: Row(children: [
            AnimatedOpacity(
              opacity: _sectionIdx == 0 ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: SizedBox(
                width: 110,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _sectionIdx == 0
                      ? null
                      : () => _goSection(_sectionIdx - 1),
                  icon: const Icon(Icons.arrow_back_rounded, size: 15),
                  label: Text(l10n.previousButton,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink2,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 120,
              height: 44,
              child: isLast
                  ? ElevatedButton.icon(
                      onPressed: _finish,
                      icon: const Icon(Icons.check_rounded, size: 15),
                      label: Text(l10n.finishBtn,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.ok,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => _goSection(_sectionIdx + 1),
                      icon: Text(l10n.nextButton,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      label: const Icon(Icons.arrow_forward_rounded, size: 15),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildSectionBody() {
    switch (_sectionIdx) {
      case 0:
        return _buildVocabSection();
      case 1:
        return _buildGrammarSection();
      case 2:
        return _buildSpellingSection();
      case 3:
        return _buildReadingSection();
      case 4:
        return _buildWritingSection();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Vocabulary (mc_img) ───────────────────────────────────────────────────

  Widget _buildVocabSection() => _SectionScroll(
        child: Column(
          children: List.generate(_variant.vocab.length, (i) {
            final q = _variant.vocab[i];
            return _McImgQuestion(
              index: i,
              question: q,
              selected: _vocabAns[i],
              onSelect: (idx) => setState(() => _vocabAns[i] = idx),
            );
          }),
        ),
      );

  // ── Grammar (mc) ─────────────────────────────────────────────────────────

  Widget _buildGrammarSection() => _SectionScroll(
        child: Column(
          children: List.generate(_variant.grammar.length, (i) {
            final q = _variant.grammar[i];
            return _McQuestion(
              index: i,
              question: q,
              selected: _grammarAns[i],
              onSelect: (idx) => setState(() => _grammarAns[i] = idx),
            );
          }),
        ),
      );

  // ── Spelling (word) ────────────────────────────────────────────────────────

  Widget _buildSpellingSection() => _SectionScroll(
        child: Column(
          children: List.generate(_variant.spelling.length, (i) {
            final q = _variant.spelling[i];
            return _WordQuestion(
              index: i,
              question: q,
              controller: _spellingCtrl[i],
              onChanged: (v) => setState(() => _spellingAns[i] = v),
            );
          }),
        ),
      );

  // ── Reading ────────────────────────────────────────────────────────────────

  Widget _buildReadingSection() {
    final reading = _variant.reading;
    return _SectionScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reading passage
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/interhouse/img/${reading.img}',
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.err.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: AppColors.ink3)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(reading.title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink1)),
                const SizedBox(height: 8),
                Text(reading.text,
                    style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: AppColors.ink2)),
              ],
            ),
          ),

          // Reading questions
          ...List.generate(reading.qs.length, (i) {
            final q = reading.qs[i];
            if (q.type == 'yn') {
              return _YnQuestion(
                index: i,
                question: q,
                selected: _readingAns[i] as String?,
                onSelect: (v) => setState(() => _readingAns[i] = v),
              );
            } else if (q.type == 'mc') {
              return _McQuestion(
                index: i,
                question: q,
                selected: _readingAns[i] as int?,
                onSelect: (idx) => setState(() => _readingAns[i] = idx),
              );
            } else {
              // fill
              return _FillQuestion(
                index: i,
                question: q,
                initialValue:
                    _readingAns[i] is String ? _readingAns[i] as String : '',
                onChanged: (v) => setState(() => _readingAns[i] = v),
              );
            }
          }),
        ],
      ),
    );
  }

  // ── Writing (sentence) ─────────────────────────────────────────────────────

  Widget _buildWritingSection() => _SectionScroll(
        child: Column(
          children: List.generate(_variant.sentences.length, (i) {
            final q = _variant.sentences[i];
            return _SentenceQuestion(
              index: i,
              question: q,
              controller: _sentenceCtrl[i],
              onChanged: (v) => setState(() => _sentenceAns[i] = v),
            );
          }),
        ),
      );
}

// ── Helper: section scroll wrapper ────────────────────────────────────────────

class _SectionScroll extends StatelessWidget {
  final Widget child;
  const _SectionScroll({required this.child});

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: child,
          ),
        ),
      );
}

// ── Pill ──────────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}

// ── Question number badge ─────────────────────────────────────────────────────

class _QNum extends StatelessWidget {
  final int index;
  const _QNum(this.index);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.brandLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('${index + 1}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.brand)),
      );
}

// ── Option row (shared between vocab/grammar/reading-mc) ──────────────────────

class _IhOptionRow extends StatelessWidget {
  final String label;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _IhOptionRow({
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color:
                selected ? AppColors.secondaryMuted : AppColors.surface,
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
                        offset: const Offset(0, 3))
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
                  color: selected
                      ? AppColors.brand
                      : AppColors.chipBorder,
                  width: 1.5,
                ),
              ),
              child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: selected
                              ? Colors.white
                              : AppColors.chipIcon))),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: selected
                            ? AppColors.amberInk
                            : AppColors.ink1))),
            if (selected)
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                    color: AppColors.brand, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 12, color: Colors.white),
              ),
          ]),
        ),
      );
}

// ── _McImgQuestion ────────────────────────────────────────────────────────────

class _McImgQuestion extends StatelessWidget {
  final int index;
  final IhQuestion question;
  final int? selected;
  final void Function(int) onSelect;

  const _McImgQuestion({
    required this.index,
    required this.question,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _QNum(index),
          const SizedBox(width: 10),
          Expanded(
              child: Text(question.q ?? '',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink1))),
        ]),
        const SizedBox(height: 12),
        if (question.img != null)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/interhouse/img/${question.img}',
                height: 270,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.err.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: AppColors.ink3)),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        ...List.generate(question.opts.length, (i) {
          // Strip leading "A) " prefix already in opts
          final text = question.opts[i];
          final label = String.fromCharCode(65 + i); // A,B,C,D
          return _IhOptionRow(
            label: label,
            text: text,
            selected: selected == i,
            onTap: () => onSelect(i),
          );
        }),
      ]),
    );
  }
}

// ── _McQuestion ───────────────────────────────────────────────────────────────

class _McQuestion extends StatelessWidget {
  final int index;
  final IhQuestion question;
  final int? selected;
  final void Function(int) onSelect;

  const _McQuestion({
    required this.index,
    required this.question,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _QNum(index),
          const SizedBox(width: 10),
          Expanded(
              child: Text(question.q ?? '',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink1,
                      height: 1.4))),
        ]),
        const SizedBox(height: 10),
        ...List.generate(question.opts.length, (i) {
          final label = String.fromCharCode(65 + i);
          return _IhOptionRow(
            label: label,
            text: question.opts[i],
            selected: selected == i,
            onTap: () => onSelect(i),
          );
        }),
      ]),
    );
  }
}

// ── _WordQuestion ─────────────────────────────────────────────────────────────

class _WordQuestion extends StatelessWidget {
  final int index;
  final IhQuestion question;
  final TextEditingController controller;
  final void Function(String) onChanged;

  const _WordQuestion({
    required this.index,
    required this.question,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
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
          _QNum(index),
          const SizedBox(width: 10),
          const Text('Harflarni to\'g\'ri joylashtiring',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink2)),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.violetMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.violetBorder),
          ),
          child: Text(question.scramble ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.violetInk,
                  letterSpacing: 4)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          onChanged: (v) => onChanged(v.toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Javob...',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppColors.brand, width: 2)),
            filled: true,
            fillColor: AppColors.bg,
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

// ── _YnQuestion ───────────────────────────────────────────────────────────────

class _YnQuestion extends StatelessWidget {
  final int index;
  final IhQuestion question;
  final String? selected;
  final void Function(String) onSelect;

  const _YnQuestion({
    required this.index,
    required this.question,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        _QNum(index),
        const SizedBox(width: 10),
        Expanded(
            child: Text(question.q ?? '',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink1))),
        const SizedBox(width: 10),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _YnButton(
            label: AppLocalizations.of(context)!.yesOption,
            color: AppColors.ok,
            selected: selected == 'YES',
            onTap: () => onSelect('YES'),
          ),
          const SizedBox(width: 8),
          _YnButton(
            label: AppLocalizations.of(context)!.noOption,
            color: AppColors.err,
            selected: selected == 'NO',
            onTap: () => onSelect('NO'),
          ),
        ]),
      ]),
    );
  }
}

class _YnButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _YnButton({
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: .3),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : color)),
        ),
      );
}

// ── _FillQuestion ─────────────────────────────────────────────────────────────

class _FillQuestion extends StatefulWidget {
  final int index;
  final IhQuestion question;
  final String initialValue;
  final void Function(String) onChanged;

  const _FillQuestion({
    required this.index,
    required this.question,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_FillQuestion> createState() => _FillQuestionState();
}

class _FillQuestionState extends State<_FillQuestion> {
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
          _QNum(widget.index),
          const SizedBox(width: 10),
          Expanded(
              child: Text(widget.question.q ?? '',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink1,
                      height: 1.4))),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _ctrl,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            hintText: 'Javob...',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppColors.brand, width: 2)),
            filled: true,
            fillColor: AppColors.bg,
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

// ── _SentenceQuestion ─────────────────────────────────────────────────────────

class _SentenceQuestion extends StatelessWidget {
  final int index;
  final IhQuestion question;
  final TextEditingController controller;
  final void Function(String) onChanged;

  const _SentenceQuestion({
    required this.index,
    required this.question,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
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
          _QNum(index),
          const SizedBox(width: 10),
          const Text('Jumlani to\'g\'ri tartibga soling',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink2)),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.brandLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.brand.withValues(alpha: .3)),
          ),
          child: Text(question.words ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'To\'liq jumlani yozing...',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppColors.brand, width: 2)),
            filled: true,
            fillColor: AppColors.bg,
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}
