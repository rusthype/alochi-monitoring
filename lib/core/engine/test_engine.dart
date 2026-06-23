// lib/core/engine/test_engine.dart
// Generic JSON-driven test runner widget (Faza 3).
// Accepts a TestSpec + variant, renders all question types, tracks answers,
// runs a countdown timer, and returns a ScoredResult via onComplete.
// Does NOT touch offline_queue / sync_service / pdf_service — those are
// wired by entry screens in Faza 4.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';
import 'test_models.dart';
import 'test_scorer.dart';
import 'question_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TestEngine
// ─────────────────────────────────────────────────────────────────────────────

class TestEngine extends StatefulWidget {
  final TestSpec spec;
  final int variant;
  final String firstName;
  final String lastName;
  final String school;
  final String? group;

  /// Test duration. Countdown starts immediately.
  final Duration duration;

  /// Called when the user finishes (submit) or when the timer hits 0.
  /// The entry screen / Faza 4 integration should call offline_queue / pdf / nav
  /// from inside this callback.
  final void Function(ScoredResult result) onComplete;

  const TestEngine({
    super.key,
    required this.spec,
    required this.variant,
    required this.firstName,
    required this.lastName,
    required this.school,
    this.group,
    required this.duration,
    required this.onComplete,
  });

  @override
  State<TestEngine> createState() => _TestEngineState();
}

class _TestEngineState extends State<TestEngine> with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────

  int _sectionIdx = 0;
  late int _secs;
  Timer? _timer;

  /// All answers: key = "SectionName/questionIndex", value = int | String
  final Map<String, dynamic> _answers = {};

  /// Controllers for text-input questions (spelling, sentence_order).
  /// Key = "SectionName/questionIndex".
  final Map<String, TextEditingController> _controllers = {};

  late final AnimationController _fadeCtrl;
  bool _finishing = false;

  // ── Derived state ──────────────────────────────────────────────────────────

  String get _variantKey => widget.variant.toString();

  List<SectionData> get _sections =>
      widget.spec.sectionsForVariant(_variantKey);

  int get _totalQuestions =>
      _sections.fold(0, (sum, s) => sum + s.questionCount);

  int get _answeredCount {
    int count = 0;
    for (final section in _sections) {
      if (section.isReading) {
        final container = section.readingContainer!;
        for (int i = 0; i < container.qs.length; i++) {
          final key = '${section.name}/$i';
          final v = _answers[key];
          if (_hasValue(v)) count++;
        }
      } else {
        for (int i = 0; i < section.questions.length; i++) {
          final key = '${section.name}/$i';
          final v = _answers[key];
          if (_hasValue(v)) count++;
        }
      }
    }
    return count;
  }

  int _answeredInSection(int sectionIndex) {
    if (sectionIndex >= _sections.length) return 0;
    final section = _sections[sectionIndex];
    int count = 0;
    if (section.isReading) {
      final container = section.readingContainer!;
      for (int i = 0; i < container.qs.length; i++) {
        final key = '${section.name}/$i';
        if (_hasValue(_answers[key])) count++;
      }
    } else {
      for (int i = 0; i < section.questions.length; i++) {
        final key = '${section.name}/$i';
        if (_hasValue(_answers[key])) count++;
      }
    }
    return count;
  }

  static bool _hasValue(dynamic v) {
    if (v == null) return false;
    if (v is String) return v.trim().isNotEmpty;
    return true; // int
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _secs = widget.duration.inSeconds;

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();

    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secs > 0) {
          _secs--;
        } else {
          _timer?.cancel();
          _finishNow();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeCtrl.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Timer display ──────────────────────────────────────────────────────────

  String get _timerText {
    final m = (_secs ~/ 60).toString().padLeft(2, '0');
    final s = (_secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _timerHot => _secs < 120;

  // ── Controller helpers ─────────────────────────────────────────────────────

  TextEditingController _ctrl(String key) =>
      _controllers.putIfAbsent(key, TextEditingController.new);

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goSection(int idx) {
    if (idx < 0 || idx >= _sections.length) return;
    _syncTextAnswers(); // flush typed values before switching
    _fadeCtrl.forward(from: 0);
    setState(() => _sectionIdx = idx);
  }

  /// Sync controller text into _answers so scorer sees latest input.
  void _syncTextAnswers() {
    for (final entry in _controllers.entries) {
      final current = entry.value.text;
      _answers[entry.key] = current;
    }
  }

  // ── Finish flow ────────────────────────────────────────────────────────────

  Future<void> _requestFinish() async {
    if (_finishing) return;
    _timer?.cancel();

    final unanswered = _totalQuestions - _answeredCount;
    if (unanswered > 0) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Tugatish?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content:
              Text('$unanswered ta savol javobsiz. Tugatmoqchimisiz?'),
          actions: [
            TextButton(
              onPressed: () {
                _startTimer();
                Navigator.pop(context, false);
              },
              child: const Text('Orqaga'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                minimumSize: const Size(100, 40),
              ),
              child: const Text('Tugatish'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    _finishNow();
  }

  void _finishNow() {
    if (_finishing) return;
    _finishing = true;
    _timer?.cancel();
    _syncTextAnswers();

    final result = TestScorer.score(widget.spec, _variantKey, _answers);
    widget.onComplete(result);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    if (sections.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text(
            'Test ma\'lumotlari topilmadi',
            style: TextStyle(color: AppColors.ink2),
          ),
        ),
      );
    }

    final progress = _totalQuestions > 0
        ? _answeredCount / _totalQuestions
        : 0.0;
    final isLast = _sectionIdx == sections.length - 1;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        // ── Progress bar ─────────────────────────────────────────────────────
        SizedBox(
          height: 4,
          child: Stack(children: [
            Container(
              width: double.infinity,
              height: 4,
              color: AppColors.border,
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: MediaQuery.sizeOf(context).width * progress,
              height: 4,
              decoration: BoxDecoration(
                color:
                    progress >= 1.0 ? AppColors.ok : AppColors.brand,
                borderRadius:
                    const BorderRadius.horizontal(right: Radius.circular(3)),
              ),
            ),
          ]),
        ),

        // ── Top bar ──────────────────────────────────────────────────────────
        _TopBar(
          studentName: _studentName(),
          testTitle: widget.spec.title,
          variant: widget.variant,
          answered: _answeredCount,
          total: _totalQuestions,
          timerText: _timerText,
          timerHot: _timerHot,
        ),

        // ── Section tabs ─────────────────────────────────────────────────────
        _SectionTabBar(
          sections: sections,
          activeIndex: _sectionIdx,
          answeredInSection: _answeredInSection,
          onTap: _goSection,
        ),

        const Divider(height: 1),

        // ── Section body ─────────────────────────────────────────────────────
        Expanded(
          child: FadeTransition(
            opacity: _fadeCtrl,
            child: _buildSectionBody(sections[_sectionIdx]),
          ),
        ),

        // ── Bottom navigation ─────────────────────────────────────────────────
        _BottomNav(
          sectionIdx: _sectionIdx,
          sectionCount: sections.length,
          isLast: isLast,
          onPrev: () => _goSection(_sectionIdx - 1),
          onNext: () => _goSection(_sectionIdx + 1),
          onFinish: _requestFinish,
        ),
      ]),
    );
  }

  String _studentName() {
    final last = widget.lastName.trim();
    final first = widget.firstName.trim();
    return '$last $first'.trim();
  }

  // ── Section body dispatch ──────────────────────────────────────────────────

  Widget _buildSectionBody(SectionData section) {
    return _SectionScroll(
      child: Builder(builder: (ctx) {
        if (section.isReading) {
          return _buildReadingBody(section);
        }
        return _buildQuestionListBody(section);
      }),
    );
  }

  Widget _buildQuestionListBody(SectionData section) {
    final qs = section.questions;
    if (qs.isEmpty) {
      return const Center(
        child: Text('Bu bo\'lim bo\'sh.',
            style: TextStyle(color: AppColors.ink3)),
      );
    }
    return Column(
      children: List.generate(qs.length, (i) {
        final q = qs[i];
        final key = '${section.name}/$i';
        return _buildQuestionWidget(q, i, key, section.name);
      }),
    );
  }

  Widget _buildReadingBody(SectionData section) {
    // Build local sub-answer map (index → value) for ReadingSectionWidget
    final container = section.readingContainer!;
    final Map<String, dynamic> subAnswers = {};
    for (int i = 0; i < container.qs.length; i++) {
      final fullKey = '${section.name}/$i';
      subAnswers[i.toString()] = _answers[fullKey];
    }

    return ReadingSectionWidget(
      section: section,
      answers: subAnswers,
      onAnswer: (subIdx, value) {
        final fullKey = '${section.name}/$subIdx';
        // For fill_blank, also sync controller
        if (value is String) {
          _ctrl(fullKey).text = value;
        }
        setState(() => _answers[fullKey] = value);
      },
    );
  }

  Widget _buildQuestionWidget(
      Question q, int i, String key, String sectionName) {
    switch (q.type) {
      case QuestionType.textChoice:
        return TextChoiceWidget(
          index: i,
          question: q,
          answer: _answers[key] as int?,
          onSelect: (v) => setState(() => _answers[key] = v),
        );

      case QuestionType.imageChoice:
        return ImageChoiceWidget(
          index: i,
          question: q,
          answer: _answers[key] as int?,
          onSelect: (v) => setState(() => _answers[key] = v),
        );

      case QuestionType.spelling:
        return SpellingWidget(
          index: i,
          question: q,
          controller: _ctrl(key),
          onChanged: (v) => setState(() => _answers[key] = v),
        );

      case QuestionType.sentenceOrder:
        return SentenceOrderWidget(
          index: i,
          question: q,
          controller: _ctrl(key),
          onChanged: (v) => setState(() => _answers[key] = v),
        );

      case QuestionType.yesNo:
        return YesNoWidget(
          index: i,
          question: q,
          answer: _answers[key] as String?,
          onSelect: (v) => setState(() => _answers[key] = v),
        );

      case QuestionType.fillBlank:
        return FillBlankWidget(
          index: i,
          question: q,
          initialValue:
              _answers[key] is String ? _answers[key] as String : '',
          onChanged: (v) {
            _ctrl(key).text = v;
            setState(() => _answers[key] = v);
          },
        );

      case QuestionType.reading:
        // reading containers are only valid as a whole section — render nothing
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets (private to this file)
// ─────────────────────────────────────────────────────────────────────────────

class _SectionScroll extends StatelessWidget {
  final Widget child;
  const _SectionScroll({required this.child});

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: child,
          ),
        ),
      );
}

class _TopBar extends StatelessWidget {
  final String studentName;
  final String testTitle;
  final int variant;
  final int answered;
  final int total;
  final String timerText;
  final bool timerHot;

  const _TopBar({
    required this.studentName,
    required this.testTitle,
    required this.variant,
    required this.answered,
    required this.total,
    required this.timerText,
    required this.timerHot,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                studentName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink1,
                ),
              ),
              const SizedBox(height: 2),
              Row(children: [
                _Pill(testTitle, AppColors.ink2),
                const SizedBox(width: 6),
                _Pill('Variant $variant', AppColors.brand),
              ]),
            ],
          ),
        ),
        // Progress counter
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '$answered/$total',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink1,
              ),
            ),
            const Text(
              'javoblandi',
              style: TextStyle(fontSize: 9, color: AppColors.ink3),
            ),
          ]),
        ),
        // Timer
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: timerHot
                ? const Color(0xFFFEF2F2)
                : const Color(0xFFFFF7ED),
            border: Border.all(
              color: timerHot
                  ? const Color(0xFFFCA5A5)
                  : const Color(0xFFFED7AA),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              timerText,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: timerHot
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF7C2D12),
              ),
            ),
            Text(
              'qoldi',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: timerHot ? const Color(0xFFDC2626) : AppColors.brand,
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
}

class _SectionTabBar extends StatelessWidget {
  final List<SectionData> sections;
  final int activeIndex;
  final int Function(int) answeredInSection;
  final void Function(int) onTap;

  const _SectionTabBar({
    required this.sections,
    required this.activeIndex,
    required this.answeredInSection,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(
          children: List.generate(sections.length, (i) {
            final answered = answeredInSection(i);
            final total = sections[i].questionCount;
            final isActive = i == activeIndex;
            return GestureDetector(
              onTap: () => onTap(i),
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
                  Text(
                    sections[i].name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: isActive ? AppColors.brand : AppColors.ink2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: answered == total
                          ? AppColors.ok.withValues(alpha: .15)
                          : isActive
                              ? AppColors.brandLight
                              : AppColors.bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$answered/$total',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: answered == total
                            ? AppColors.ok
                            : isActive
                                ? AppColors.brand
                                : AppColors.ink3,
                      ),
                    ),
                  ),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int sectionIdx;
  final int sectionCount;
  final bool isLast;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  const _BottomNav({
    required this.sectionIdx,
    required this.sectionCount,
    required this.isLast,
    required this.onPrev,
    required this.onNext,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: Row(children: [
        AnimatedOpacity(
          opacity: sectionIdx == 0 ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            width: 110,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: sectionIdx == 0 ? null : onPrev,
              icon: const Icon(Icons.arrow_back_rounded, size: 15),
              label: const Text(
                'Oldingi',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
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
                  onPressed: onFinish,
                  icon: const Icon(Icons.check_rounded, size: 15),
                  label: const Text(
                    'Tugatish',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ok,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: onNext,
                  icon: const Text(
                    'Keyingi',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
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
    );
  }
}
