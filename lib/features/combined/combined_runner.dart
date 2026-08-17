// lib/features/combined/combined_runner.dart
// Combined Monitoring Test runner: Math (30 MCQ) + English Unit 1 (49 Qs) = 79 total
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/exit_confirmation_scope.dart';
import '../../core/engine/answer_normalization.dart';
import '../../core/db/history_db.dart';
import '../../core/db/offline_queue.dart';
import '../../core/api/api_client.dart';
import '../../core/services/pdf_service.dart';
import '../../features/local_test/local_data.dart';
import '../../features/unit1/unit1_data.dart';
import '../../shared/widgets/app_network_image.dart';
import 'package:printing/printing.dart';
import '../../core/utils/topic_format.dart';

// ── Color accents ──────────────────────────────────────────────────────────────
const Color _kPurple = AppColors.violet;
const Color _kPurpleMuted = AppColors.violetMuted;
const Color _kPurpleBorder = AppColors.violetBorder;
const Color _kBlue = AppColors.blue;
const Color _kBlueMuted = AppColors.blueMuted;
const Color _kBlueBorder = AppColors.blueBorder;
// Math section uses green accent
const Color _kGreen = AppColors.emerald;
const Color _kGreenMuted = AppColors.emeraldMuted;

// ── Score color per project rules ─────────────────────────────────────────────
Color _scoreColor(double pct) {
  if (pct >= 90) return Colors.green;
  if (pct >= 75) return Colors.white;
  if (pct >= 60) return Colors.yellow;
  return Colors.red;
}

// ── Section indices ────────────────────────────────────────────────────────────
// 0=Matematika, 1=Vocabulary, 2=Grammar, 3=Spelling, 4=Sentences, 5=Reading
const int _kMathIdx = 0;
const int _kVocabIdx = 1;
const int _kGrammarIdx = 2;
const int _kSpellingIdx = 3;
const int _kSentencesIdx = 4;
const int _kReadingIdx = 5;
const int _kTotalSections = 6;

const int _kTotalQs = 79;

const List<String> _kSectionNames = [
  'Matematika',
  'Vocabulary',
  'Grammar',
  'Spelling',
  'Sentences',
  'Reading',
];

const List<int> _kSectionCounts = [30, 25, 6, 6, 6, 6];

// ─────────────────────────────────────────────────────────────────────────────
// CombinedRunner
// ─────────────────────────────────────────────────────────────────────────────

class CombinedRunner extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String school;
  final int variant; // 1–15
  final List<LocalQuestion> mathQuestions; // 30 math MCQ
  final Unit1TestData testData;

  const CombinedRunner({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.school,
    required this.variant,
    required this.mathQuestions,
    required this.testData,
  });

  @override
  State<CombinedRunner> createState() => _CombinedRunnerState();
}

class _CombinedRunnerState extends State<CombinedRunner>
    with TickerProviderStateMixin {
  int _sectionIdx = 0;

  // Math answers — index of selected option per question (null = unanswered)
  late final List<int?> _mathAns;

  // English answers
  final List<int?> _vocabAns = List.filled(25, null);
  final List<int?> _grammarAns = List.filled(6, null);
  final List<String> _spellingAns = List.generate(6, (_) => '');
  final List<String> _sentenceAns = List.generate(6, (_) => '');
  final List<dynamic> _readingAns = List.filled(6, null);

  // Text controllers for typed sections
  late final List<TextEditingController> _spellingCtrl;
  late final List<TextEditingController> _sentenceCtrl;

  // Timer — 75 minutes
  Timer? _timer;
  int _secs = 75 * 60;
  final DateTime _testStartedAt = DateTime.now();

  // Animation
  late final AnimationController _fadeCtrl;

  Unit1Variant get _engVariant =>
      widget.testData.variants[widget.variant.toString()]!;

  @override
  void initState() {
    super.initState();

    _mathAns = List.filled(widget.mathQuestions.length, null);

    _spellingCtrl = List.generate(6, (_) => TextEditingController());
    _sentenceCtrl = List.generate(6, (_) => TextEditingController());

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

  // ── Timer helpers ──────────────────────────────────────────────────────────

  String get _timerText {
    final m = (_secs ~/ 60).toString().padLeft(2, '0');
    final s = (_secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _timerHot => _secs < 120;

  // ── Answered counts ────────────────────────────────────────────────────────

  int _answeredInSection(int idx) {
    switch (idx) {
      case _kMathIdx:
        return _mathAns.where((a) => a != null).length;
      case _kVocabIdx:
        return _vocabAns.where((a) => a != null).length;
      case _kGrammarIdx:
        return _grammarAns.where((a) => a != null).length;
      case _kSpellingIdx:
        return _spellingAns.where((s) => s.trim().isNotEmpty).length;
      case _kSentencesIdx:
        return _sentenceAns.where((s) => s.trim().isNotEmpty).length;
      case _kReadingIdx:
        return _readingAns.where((a) => a != null).length;
      default:
        return 0;
    }
  }

  int get _totalAnswered {
    int total = 0;
    for (int i = 0; i < _kTotalSections; i++) {
      total += _answeredInSection(i);
    }
    return total;
  }

  String get _studentName {
    final last = widget.lastName.trim();
    final first = widget.firstName.trim();
    return '$last $first'.trim();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goSection(int idx) {
    if (idx < 0 || idx >= _kTotalSections) return;
    _fadeCtrl.forward(from: 0);
    setState(() => _sectionIdx = idx);
  }

  // ── Finish flow ────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    _timer?.cancel();

    final l10n = AppLocalizations.of(context)!;
    final unanswered = _kTotalQs - _totalAnswered;
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
                // Resume timer
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
                  backgroundColor: _kPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(100, 40)),
              child: Text(l10n.finishBtn),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    if (!mounted) return;

    // Sync text controllers → answer lists
    for (int i = 0; i < 6; i++) {
      _spellingAns[i] = _spellingCtrl[i].text;
      _sentenceAns[i] = _sentenceCtrl[i].text;
    }

    // ── Math scoring ──────────────────────────────────────────────────────────
    int mathOk = 0;
    final mathQs = widget.mathQuestions;
    final List<Map<String, dynamic>> answers = [];
    for (int i = 0; i < mathQs.length; i++) {
      if (i >= _mathAns.length) break;
      final selectedIdx = _mathAns[i];
      // correct is 'a'|'b'|'c'|'d', options list is already remapped
      final correctIdx = 'abcd'.indexOf(mathQs[i].correct);
      final bool ok =
          selectedIdx != null && correctIdx >= 0 && selectedIdx == correctIdx;
      if (ok) mathOk++;
      answers.add({
        'section': 'Matematika',
        'q': mathQs[i].prompt,
        'topic': mathQs[i].topic,
        'chosen': (selectedIdx != null &&
                selectedIdx >= 0 &&
                selectedIdx < mathQs[i].options.length)
            ? mathQs[i].options[selectedIdx]
            : '',
        'correct': (correctIdx >= 0 && correctIdx < mathQs[i].options.length)
            ? mathQs[i].options[correctIdx]
            : '',
        'ok': ok,
      });
    }

    // ── English scoring ───────────────────────────────────────────────────────
    final eng = _engVariant;

    int vocabOk = 0;
    for (int i = 0; i < eng.vocab.length; i++) {
      final selectedIdx = i < _vocabAns.length ? _vocabAns[i] : null;
      final bool ok = selectedIdx != null && selectedIdx == eng.vocab[i].ans;
      if (ok) vocabOk++;
      answers.add({
        'section': 'Vocabulary',
        'q': eng.vocab[i].q,
        'chosen': (selectedIdx != null &&
                selectedIdx >= 0 &&
                selectedIdx < eng.vocab[i].opts.length)
            ? eng.vocab[i].opts[selectedIdx]
            : '',
        'correct': (eng.vocab[i].ans >= 0 &&
                eng.vocab[i].ans < eng.vocab[i].opts.length)
            ? eng.vocab[i].opts[eng.vocab[i].ans]
            : '',
        'ok': ok,
      });
    }

    int grammarOk = 0;
    for (int i = 0; i < eng.grammar.length; i++) {
      final selectedIdx = i < _grammarAns.length ? _grammarAns[i] : null;
      final bool ok = selectedIdx != null && selectedIdx == eng.grammar[i].ans;
      if (ok) grammarOk++;
      answers.add({
        'section': 'Grammar',
        'q': eng.grammar[i].q,
        'chosen': (selectedIdx != null &&
                selectedIdx >= 0 &&
                selectedIdx < eng.grammar[i].opts.length)
            ? eng.grammar[i].opts[selectedIdx]
            : '',
        'correct': (eng.grammar[i].ans >= 0 &&
                eng.grammar[i].ans < eng.grammar[i].opts.length)
            ? eng.grammar[i].opts[eng.grammar[i].ans]
            : '',
        'ok': ok,
      });
    }

    int spellingOk = 0;
    for (int i = 0; i < eng.spelling.length; i++) {
      final typed = i < _spellingAns.length ? _spellingAns[i].trim() : '';
      final bool ok =
          typed.toLowerCase() == eng.spelling[i].ans.trim().toLowerCase();
      if (ok) spellingOk++;
      answers.add({
        'section': 'Spelling',
        'q': 'Harflarni tartibga sol: ${eng.spelling[i].scramble}',
        'chosen': typed,
        'correct': eng.spelling[i].ans,
        'ok': ok,
      });
    }

    int sentenceOk = 0;
    for (int i = 0; i < eng.sentences.length; i++) {
      final typed = i < _sentenceAns.length ? _sentenceAns[i].trim() : '';
      String userAns = typed.toLowerCase();
      if (userAns.endsWith('.')) {
        userAns = userAns.substring(0, userAns.length - 1).trim();
      }
      String correctAns = eng.sentences[i].ans.trim().toLowerCase();
      if (correctAns.endsWith('.')) {
        correctAns = correctAns.substring(0, correctAns.length - 1).trim();
      }
      final bool ok =
          expandContractions(userAns) == expandContractions(correctAns);
      if (ok) sentenceOk++;
      answers.add({
        'section': 'Sentences',
        'q': 'Jumlani tuz: ${eng.sentences[i].words}',
        'chosen': typed,
        'correct': eng.sentences[i].ans,
        'ok': ok,
      });
    }

    int readingOk = 0;
    final reading = eng.reading;
    for (int j = 0; j < reading.qs.length; j++) {
      if (j >= _readingAns.length) break;
      final q = reading.qs[j];
      final ans = _readingAns[j];
      bool ok = false;
      String chosen = '';
      String correct = '';
      if (q.type == 'yn') {
        correct = (q.ans as String).toUpperCase();
        chosen = (ans is String) ? ans.trim().toUpperCase() : '';
        ok = ans is String &&
            ans.trim().toLowerCase() == (q.ans as String).trim().toLowerCase();
        if (ok) readingOk++;
      } else if (q.type == 'mc') {
        final correctIdx = q.ans as int;
        final opts = q.opts ?? [];
        correct = (correctIdx >= 0 && correctIdx < opts.length)
            ? opts[correctIdx]
            : '';
        chosen = (ans is int && ans >= 0 && ans < opts.length) ? opts[ans] : '';
        ok = ans is int && ans == correctIdx;
        if (ok) readingOk++;
      } else {
        // fill
        correct = (q.ans as String);
        chosen = (ans is String) ? ans.trim() : '';
        ok = ans is String &&
            ans.trim().toLowerCase() == (q.ans as String).trim().toLowerCase();
        if (ok) readingOk++;
      }
      answers.add({
        'section': 'Reading',
        'q': q.q,
        'chosen': chosen,
        'correct': correct,
        'ok': ok,
      });
    }

    final engOk = vocabOk + grammarOk + spellingOk + sentenceOk + readingOk;
    final totalOk = mathOk + engOk;
    final pct = (totalOk * 100 / _kTotalQs).round();

    // Build detail map
    final detail = {
      'test_key': 'monitoring_unit1',
      'topics': topicsFromSections([
        {'name': 'Matematika', 'cor': mathOk, 'tot': 30},
        {'name': 'Vocabulary', 'cor': vocabOk, 'tot': 25},
        {'name': 'Grammar', 'cor': grammarOk, 'tot': 6},
        {'name': 'Spelling', 'cor': spellingOk, 'tot': 6},
        {'name': 'Sentences', 'cor': sentenceOk, 'tot': 6},
        {'name': 'Reading', 'cor': readingOk, 'tot': 6},
      ]),
    };

    // Time string
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final durationSeconds = now.difference(_testStartedAt).inSeconds;

    // Save to history
    try {
      await HistoryDb.insertResult(
        firstName: widget.firstName,
        lastName: widget.lastName,
        school: widget.school.isEmpty ? '—' : widget.school,
        gradeGroup: 'Monitoring Test Unit 1',
        mathScore: mathOk,
        engScore: engOk,
        totalPct: pct.toDouble(),
      );
    } catch (e) {
      debugPrint('HistoryDb error: $e');
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CombinedResultScreen(
          studentName: _studentName,
          firstName: widget.firstName,
          lastName: widget.lastName,
          school: widget.school,
          variant: widget.variant,
          mathOk: mathOk,
          engOk: engOk,
          vocabOk: vocabOk,
          grammarOk: grammarOk,
          spellingOk: spellingOk,
          sentenceOk: sentenceOk,
          readingOk: readingOk,
          totalOk: totalOk,
          pct: pct,
          timeStr: timeStr,
          durationSeconds: durationSeconds,
          answers: answers,
          detail: detail,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = _kTotalQs > 0 ? _totalAnswered / _kTotalQs : 0.0;
    final isLast = _sectionIdx == _kTotalSections - 1;

    return ExitConfirmationScope(
        child: Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        // ── Progress bar
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
                color: progress >= 1.0 ? AppColors.ok : _kPurple,
                borderRadius:
                    const BorderRadius.horizontal(right: Radius.circular(3)),
              ),
            ),
          ]),
        ),

        // ── Top bar
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
            Image.asset('assets/logo.png',
                width: 30,
                height: 30,
                errorBuilder: (_, __, ___) => const Icon(Icons.school_outlined,
                    size: 30, color: _kPurple)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_studentName,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink1)),
                    const SizedBox(height: 2),
                    Row(children: [
                      _CPill(l10n.combinedPillLabel, _kPurple),
                      const SizedBox(width: 6),
                      _CPill(
                          l10n.variantBadge(widget.variant), AppColors.brand),
                    ]),
                  ]),
            ),
            // Answered counter
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$_totalAnswered/$_kTotalQs',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink1)),
                Text(l10n.answeredLabel,
                    style: const TextStyle(fontSize: 9, color: AppColors.ink3)),
              ]),
            ),
            // Timer
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _timerHot ? AppColors.errorMuted : _kPurpleMuted,
                border: Border.all(
                  color: _timerHot ? AppColors.dangerBorder : _kPurpleBorder,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_timerText,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _timerHot ? AppColors.error : _kPurple)),
                Text(l10n.timeLeftLabel,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _timerHot ? AppColors.error : _kPurple)),
              ]),
            ),
          ]),
        ),

        // ── Section tabs
        Container(
          color: AppColors.surface,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(
              children: List.generate(_kTotalSections, (i) {
                final answered = _answeredInSection(i);
                final total = _kSectionCounts[i];
                final isActive = i == _sectionIdx;
                final isDone = answered == total;
                final tabColor = i == _kMathIdx ? _kGreen : _kBlue;
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
                          color: isActive ? tabColor : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_kSectionNames[i],
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  isActive ? FontWeight.w800 : FontWeight.w500,
                              color: isActive ? tabColor : AppColors.ink2)),
                      const SizedBox(width: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDone
                              ? AppColors.ok.withValues(alpha: .15)
                              : isActive
                                  ? (i == _kMathIdx
                                      ? _kGreenMuted
                                      : _kBlueMuted)
                                  : AppColors.bg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$answered/$total',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isDone
                                    ? AppColors.ok
                                    : isActive
                                        ? tabColor
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

        // ── Section body
        Expanded(
          child: FadeTransition(
            opacity: _fadeCtrl,
            child: _buildSectionBody(),
          ),
        ),

        // ── Bottom nav
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
                        backgroundColor: _kPurple,
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
    ));
  }

  Widget _buildSectionBody() {
    switch (_sectionIdx) {
      case _kMathIdx:
        return _buildMathSection();
      case _kVocabIdx:
        return _buildVocabSection();
      case _kGrammarIdx:
        return _buildGrammarSection();
      case _kSpellingIdx:
        return _buildSpellingSection();
      case _kSentencesIdx:
        return _buildSentencesSection();
      case _kReadingIdx:
        return _buildReadingSection();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Matematika (30 MCQ from bob14) ────────────────────────────────────────

  Widget _buildMathSection() {
    final mathQs = widget.mathQuestions;
    if (mathQs.isEmpty) {
      return _CSectionScroll(
          child: Center(
              child: Text(AppLocalizations.of(context)!.mathQuestionsNotFound,
                  style: const TextStyle(color: AppColors.ink2))));
    }
    return _CSectionScroll(
      child: Column(
        children: List.generate(mathQs.length, (i) {
          final q = mathQs[i];
          return _MathMcQuestion(
            index: i,
            question: q,
            selected: _mathAns[i],
            onSelect: (idx) => setState(() => _mathAns[i] = idx),
          );
        }),
      ),
    );
  }

  // ── Vocabulary (image MCQ, 25 questions) ─────────────────────────────────

  Widget _buildVocabSection() {
    final vocab = _engVariant.vocab;
    if (vocab.isEmpty) {
      return _CSectionScroll(
          child: Center(
              child: Text(
                  AppLocalizations.of(context)!.vocabularyQuestionsNotFoundMsg,
                  style: const TextStyle(color: AppColors.ink2))));
    }
    return _CSectionScroll(
      child: Column(
        children: List.generate(vocab.length, (i) {
          final q = vocab[i];
          return _CVocabImgQuestion(
            index: i,
            question: q,
            selected: _vocabAns[i],
            onSelect: (idx) => setState(() => _vocabAns[i] = idx),
          );
        }),
      ),
    );
  }

  // ── Grammar (text MCQ, 6 questions) ──────────────────────────────────────

  Widget _buildGrammarSection() {
    final grammar = _engVariant.grammar;
    if (grammar.isEmpty) {
      return _CSectionScroll(
          child: Center(
              child: Text(
                  AppLocalizations.of(context)!.grammarQuestionsNotFoundMsg,
                  style: const TextStyle(color: AppColors.ink2))));
    }
    return _CSectionScroll(
      child: Column(
        children: List.generate(grammar.length, (i) {
          final q = grammar[i];
          return _CTextMcQuestion(
            index: i,
            questionText: q.q,
            opts: q.opts,
            selected: _grammarAns[i],
            onSelect: (idx) => setState(() => _grammarAns[i] = idx),
          );
        }),
      ),
    );
  }

  // ── Spelling (scrambled letters → type word, 6 questions) ─────────────────

  Widget _buildSpellingSection() {
    final spelling = _engVariant.spelling;
    if (spelling.isEmpty) {
      return _CSectionScroll(
          child: Center(
              child: Text(
                  AppLocalizations.of(context)!.spellingQuestionsNotFoundMsg,
                  style: const TextStyle(color: AppColors.ink2))));
    }
    return _CSectionScroll(
      child: Column(
        children: List.generate(spelling.length, (i) {
          final q = spelling[i];
          return _CSpellingQuestion(
            index: i,
            scramble: q.scramble,
            controller: _spellingCtrl[i],
            onChanged: (v) => setState(() => _spellingAns[i] = v.toLowerCase()),
          );
        }),
      ),
    );
  }

  // ── Sentences (scrambled words → type sentence, 6 questions) ──────────────

  Widget _buildSentencesSection() {
    final sentences = _engVariant.sentences;
    if (sentences.isEmpty) {
      return _CSectionScroll(
          child: Center(
              child: Text(
                  AppLocalizations.of(context)!.sentencesQuestionsNotFoundMsg,
                  style: const TextStyle(color: AppColors.ink2))));
    }
    return _CSectionScroll(
      child: Column(
        children: List.generate(sentences.length, (i) {
          final q = sentences[i];
          return _CSentenceQuestion(
            index: i,
            words: q.words,
            controller: _sentenceCtrl[i],
            onChanged: (v) => setState(() => _sentenceAns[i] = v),
          );
        }),
      ),
    );
  }

  // ── Reading (passage + 6 mixed questions) ────────────────────────────────

  Widget _buildReadingSection() {
    final reading = _engVariant.reading;
    return _CSectionScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reading passage card
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
                if (reading.img.isNotEmpty)
                  reading.img.startsWith('http')
                      ? AppNetworkImage(
                          url: reading.img,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.contain,
                          borderRadius: BorderRadius.circular(10),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/unit1/img/${reading.img}',
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
                if (reading.img.isNotEmpty) const SizedBox(height: 12),
                if (reading.title.isNotEmpty)
                  Text(reading.title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink1)),
                if (reading.title.isNotEmpty) const SizedBox(height: 8),
                if (reading.text.isNotEmpty)
                  Text(reading.text,
                      style: const TextStyle(
                          fontSize: 14, height: 1.6, color: AppColors.ink2)),
              ],
            ),
          ),

          // Reading questions
          if (reading.qs.isEmpty)
            Center(
                child: Text(
                    AppLocalizations.of(context)!.readingQuestionsNotFoundMsg,
                    style: const TextStyle(color: AppColors.ink2)))
          else
            ...List.generate(reading.qs.length, (i) {
              final q = reading.qs[i];
              if (q.type == 'yn') {
                return _CYnQuestion(
                  index: i,
                  questionText: q.q,
                  selected: _readingAns[i] as String?,
                  onSelect: (v) => setState(() => _readingAns[i] = v),
                );
              } else if (q.type == 'mc') {
                final opts = q.opts ?? [];
                return _CTextMcQuestion(
                  index: i,
                  questionText: q.q,
                  opts: opts,
                  selected: _readingAns[i] as int?,
                  onSelect: (idx) => setState(() => _readingAns[i] = idx),
                );
              } else {
                // fill
                return _CFillQuestion(
                  index: i,
                  questionText: q.q,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// CombinedResultScreen
// ─────────────────────────────────────────────────────────────────────────────

class CombinedResultScreen extends StatefulWidget {
  final String studentName;
  final String firstName;
  final String lastName;
  final String school;
  final int variant;
  final int mathOk;
  final int engOk;
  final int vocabOk;
  final int grammarOk;
  final int spellingOk;
  final int sentenceOk;
  final int readingOk;
  final int totalOk;
  final int pct;
  final String timeStr;
  final int durationSeconds;
  final List<Map<String, dynamic>> answers;
  final Map<String, dynamic> detail;

  const CombinedResultScreen({
    super.key,
    required this.studentName,
    required this.firstName,
    required this.lastName,
    required this.school,
    required this.variant,
    required this.mathOk,
    required this.engOk,
    required this.vocabOk,
    required this.grammarOk,
    required this.spellingOk,
    required this.sentenceOk,
    required this.readingOk,
    required this.totalOk,
    required this.pct,
    required this.timeStr,
    required this.durationSeconds,
    required this.answers,
    required this.detail,
  });

  @override
  State<CombinedResultScreen> createState() => _CombinedResultScreenState();
}

class _CombinedResultScreenState extends State<CombinedResultScreen> {
  // null = still on the initial "sending" state; localized lazily since
  // AppLocalizations isn't available yet at field-initializer time.
  String? _sendStatus;
  bool _sent = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _submitLocal();
  }

  Future<void> _submitLocal() async {
    final payload = _buildPayload();
    final token = newIdempotencyToken();
    try {
      await OfflineQueue.enqueueLocal(payload, token);
      OfflineQueue.waitForDropReason(token).then<void>((reason) {
        if (reason == 'max_attempts_exceeded' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.maxAttemptsExceeded),
            backgroundColor: AppColors.err,
            duration: const Duration(seconds: 6),
          ));
        }
      }).catchError((e) {
        debugPrint('Combined: waitForDropReason error: $e');
        return Future<void>.value();
      });
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sendStatus = AppLocalizations.of(context)!.savedSending;
      });
    } catch (e) {
      debugPrint('Combined enqueue error: $e');
      if (!mounted) return;
      setState(() {
        _error = true;
        _sendStatus = AppLocalizations.of(context)!.saveErrorRetryMsg;
      });
    }
  }

  Map<String, dynamic> _buildPayload() {
    return {
      'name': '${widget.lastName} ${widget.firstName}'.trim(),
      'grade': 1,
      'variant': widget.variant.toString(),
      'source': 'flutter',
      'math': {'cor': widget.mathOk, 'tot': 30},
      'english': {'cor': widget.engOk, 'tot': 49},
      'vocab': {'cor': 0, 'tot': 0},
      'pct': widget.pct,
      'time': widget.timeStr,
      'school_code': widget.school,
      'answers': widget.answers,
      'detail': widget.detail,
      if (widget.durationSeconds > 0) 'duration_seconds': widget.durationSeconds,
    };
  }

  List<MapEntry<String, ({int ok, int tot})>> get _mathTopics => [
        MapEntry('Matematika', (ok: widget.mathOk, tot: 30)),
      ];

  List<MapEntry<String, ({int ok, int tot})>> get _engTopics => [
        MapEntry('Vocabulary', (ok: widget.vocabOk, tot: 25)),
        MapEntry('Grammar', (ok: widget.grammarOk, tot: 6)),
        MapEntry('Spelling', (ok: widget.spellingOk, tot: 6)),
        MapEntry('Sentences', (ok: widget.sentenceOk, tot: 6)),
        MapEntry('Reading', (ok: widget.readingOk, tot: 6)),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scoreColor = _scoreColor(widget.pct.toDouble());
    final isPass = widget.pct >= 60;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Result icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: isPass
                          ? AppColors.ok.withValues(alpha: .12)
                          : AppColors.err.withValues(alpha: .10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPass
                          ? Icons.emoji_events_rounded
                          : Icons.sentiment_dissatisfied_outlined,
                      size: 44,
                      color: isPass ? AppColors.ok : AppColors.err,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Student name
                  Text(widget.studentName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink1)),
                  const SizedBox(height: 4),
                  Text(l10n.monitoringTestUnit1,
                      style:
                          const TextStyle(fontSize: 13, color: AppColors.ink2)),
                  const SizedBox(height: 24),

                  // Score card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: .04),
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(children: [
                      // Big pct
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: scoreColor.withValues(alpha: .15),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: scoreColor.withValues(alpha: .4),
                              width: 3),
                        ),
                        child: Center(
                          child: Text('${widget.pct}%',
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: scoreColor == Colors.white
                                      ? AppColors.ink1
                                      : scoreColor)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(l10n.correctFractionLabel(widget.totalOk, _kTotalQs),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink1)),
                      const SizedBox(height: 20),

                      // Section breakdown
                      const Divider(),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(l10n.sectionsResultTitle,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink2)),
                      ),
                      const SizedBox(height: 10),
                      _CBreakdownRow(
                          label: AppLocalizations.of(context)!.mathSubject,
                          correct: widget.mathOk,
                          total: 30,
                          color: _kGreen),
                      _CBreakdownRow(
                          label: AppLocalizations.of(context)!.vocabularyTopic,
                          correct: widget.vocabOk,
                          total: 25,
                          color: _kBlue),
                      _CBreakdownRow(
                          label: AppLocalizations.of(context)!.grammarTopic,
                          correct: widget.grammarOk,
                          total: 6,
                          color: AppColors.violet),
                      _CBreakdownRow(
                          label: AppLocalizations.of(context)!.spellingTopic,
                          correct: widget.spellingOk,
                          total: 6,
                          color: AppColors.cyan),
                      _CBreakdownRow(
                          label: AppLocalizations.of(context)!.sentencesTopic,
                          correct: widget.sentenceOk,
                          total: 6,
                          color: AppColors.brand),
                      _CBreakdownRow(
                          label: AppLocalizations.of(context)!.readingTopic,
                          correct: widget.readingOk,
                          total: 6,
                          color: AppColors.ok),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Send status
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _error
                          ? AppColors.errMuted
                          : _sent
                              ? AppColors.okMuted
                              : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _error
                              ? AppColors.err.withValues(alpha: .3)
                              : _sent
                                  ? AppColors.correctBorder
                                  : AppColors.border),
                    ),
                    child: Row(children: [
                      Icon(
                        _error
                            ? Icons.warning_rounded
                            : _sent
                                ? Icons.check_circle_rounded
                                : Icons.cloud_upload_rounded,
                        color: _error
                            ? AppColors.err
                            : _sent
                                ? AppColors.ok
                                : AppColors.brand,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              _sendStatus ??
                                  AppLocalizations.of(context)!.sending,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _error
                                      ? AppColors.err
                                      : _sent
                                          ? AppColors.ok
                                          : AppColors.ink2))),
                    ]),
                  ),

                  const SizedBox(height: 16),

                  // PDF buttons
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final pdfBytes = await PdfService.generateResultPdf(
                            firstName: widget.firstName,
                            lastName: widget.lastName,
                            group: '',
                            grade: 1,
                            variant: widget.variant,
                            mathOk: widget.mathOk,
                            mathTotal: 30,
                            engOk: widget.engOk,
                            engTotal: 49,
                            pct: widget.pct,
                            mathTopics: _mathTopics,
                            engTopics: _engTopics,
                            l10n: l10n,
                          );
                          await Printing.layoutPdf(
                              onLayout: (_) => pdfBytes,
                              name:
                                  '${widget.lastName}_${widget.firstName}_Natija.pdf');
                        },
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: Text(AppLocalizations.of(context)!.printBtn),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.ink1,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final pdfBytes = await PdfService.generateResultPdf(
                            firstName: widget.firstName,
                            lastName: widget.lastName,
                            group: '',
                            grade: 1,
                            variant: widget.variant,
                            mathOk: widget.mathOk,
                            mathTotal: 30,
                            engOk: widget.engOk,
                            engTotal: 49,
                            pct: widget.pct,
                            mathTopics: _mathTopics,
                            engTopics: _engTopics,
                            l10n: l10n,
                          );
                          await Printing.sharePdf(
                              bytes: pdfBytes,
                              filename:
                                  '${widget.lastName}_${widget.firstName}_Natija.pdf');
                        },
                        icon:
                            const Icon(Icons.picture_as_pdf_rounded, size: 18),
                        label: Text(AppLocalizations.of(context)!.savePdf),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.brand,
                            side: const BorderSide(color: AppColors.brand),
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // Qaytish button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.home_outlined, size: 18),
                      label: Text(l10n.returnBtn,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink1,
                        side: const BorderSide(
                            color: AppColors.border, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Layout helpers
// ─────────────────────────────────────────────────────────────────────────────

class _CSectionScroll extends StatelessWidget {
  final Widget child;
  const _CSectionScroll({required this.child});

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

class _CPill extends StatelessWidget {
  final String text;
  final Color color;
  const _CPill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}

class _CQNum extends StatelessWidget {
  final int index;
  const _CQNum(this.index);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: _kBlueMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('${index + 1}',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: _kBlue)),
      );
}

class _CMathQNum extends StatelessWidget {
  final int index;
  const _CMathQNum(this.index);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: _kGreenMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('${index + 1}',
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: _kGreen)),
      );
}

class _CBreakdownRow extends StatelessWidget {
  final String label;
  final int correct;
  final int total;
  final Color color;

  const _CBreakdownRow({
    required this.label,
    required this.correct,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? correct / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SizedBox(
          width: 88,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink2)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.gray100,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text('$correct/$total',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Math MCQ option row (green accent)
// ─────────────────────────────────────────────────────────────────────────────

class _CMathOptionRow extends StatelessWidget {
  final String label;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _CMathOptionRow({
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
            color: selected ? _kGreenMuted : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _kGreen : AppColors.border,
              width: selected ? 2 : 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: _kGreen.withValues(alpha: .12),
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
                color: selected ? _kGreen : AppColors.chipBg,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? _kGreen : AppColors.chipBorder,
                  width: 1.5,
                ),
              ),
              child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color:
                              selected ? Colors.white : AppColors.chipIcon))),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: selected
                            ? const Color(0xFF064E3B)
                            : AppColors.ink1))),
            if (selected)
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(left: 8),
                decoration:
                    const BoxDecoration(color: _kGreen, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 12, color: Colors.white),
              ),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Math question widget
// ─────────────────────────────────────────────────────────────────────────────

class _MathMcQuestion extends StatelessWidget {
  final int index;
  final LocalQuestion question;
  final int? selected;
  final void Function(int) onSelect;

  const _MathMcQuestion({
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
          _CMathQNum(index),
          const SizedBox(width: 10),
          Expanded(
              child: Text(question.prompt,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink1,
                      height: 1.4))),
        ]),
        const SizedBox(height: 10),
        if (question.options.isEmpty)
          Text(AppLocalizations.of(context)!.variantsNotFoundMsg,
              style: const TextStyle(color: AppColors.ink3))
        else
          ...List.generate(question.options.length, (i) {
            final label = String.fromCharCode(65 + i); // A B C D
            return _CMathOptionRow(
              label: label,
              text: question.options[i],
              selected: selected == i,
              onTap: () => onSelect(i),
            );
          }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// English question widgets (reusing same logic/style as unit1_runner)
// Using _C prefix to avoid duplicate class names in the compilation unit
// ─────────────────────────────────────────────────────────────────────────────

class _COptionRow extends StatelessWidget {
  final String label;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _COptionRow({
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
            color: selected ? _kBlueMuted : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _kBlue : AppColors.border,
              width: selected ? 2 : 1.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: _kBlue.withValues(alpha: .12),
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
                color: selected ? _kBlue : AppColors.chipBg,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? _kBlue : AppColors.chipBorder,
                  width: 1.5,
                ),
              ),
              child: Center(
                  child: Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color:
                              selected ? Colors.white : AppColors.chipIcon))),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: selected ? AppColors.navyInk : AppColors.ink1))),
            if (selected)
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(left: 8),
                decoration:
                    const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 12, color: Colors.white),
              ),
          ]),
        ),
      );
}

class _CVocabImgQuestion extends StatelessWidget {
  final int index;
  final Unit1Q question;
  final int? selected;
  final void Function(int) onSelect;

  const _CVocabImgQuestion({
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
          _CQNum(index),
          const SizedBox(width: 10),
          Expanded(
              child: Text(question.q,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink1))),
        ]),
        if (question.img != null && question.img!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Center(
            child: question.img!.startsWith('http')
                ? AppNetworkImage(
                    url: question.img,
                    height: 270,
                    fit: BoxFit.contain,
                    borderRadius: BorderRadius.circular(10),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/unit1/img/${question.img}',
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
        ],
        const SizedBox(height: 10),
        if (question.opts.isEmpty)
          Text(AppLocalizations.of(context)!.variantsNotFoundMsg,
              style: const TextStyle(color: AppColors.ink3))
        else
          ...List.generate(question.opts.length, (i) {
            final label = String.fromCharCode(65 + i);
            return _COptionRow(
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

class _CTextMcQuestion extends StatelessWidget {
  final int index;
  final String questionText;
  final List<String> opts;
  final int? selected;
  final void Function(int) onSelect;

  const _CTextMcQuestion({
    required this.index,
    required this.questionText,
    required this.opts,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _CQNum(index),
          const SizedBox(width: 10),
          Expanded(
              child: Text(questionText,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink1,
                      height: 1.4))),
        ]),
        const SizedBox(height: 10),
        if (opts.isEmpty)
          Text(AppLocalizations.of(context)!.variantsNotFoundMsg,
              style: const TextStyle(color: AppColors.ink3))
        else
          ...List.generate(opts.length, (i) {
            final label = String.fromCharCode(65 + i);
            return _COptionRow(
              label: label,
              text: opts[i],
              selected: selected == i,
              onTap: () => onSelect(i),
            );
          }),
      ]),
    );
  }
}

class _CSpellingQuestion extends StatelessWidget {
  final int index;
  final String scramble;
  final TextEditingController controller;
  final void Function(String) onChanged;

  const _CSpellingQuestion({
    required this.index,
    required this.scramble,
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
          _CQNum(index),
          const SizedBox(width: 10),
          Text(AppLocalizations.of(context)!.arrangeLettersPrompt,
              style: const TextStyle(
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
          child: Text(scramble,
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
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.answerHintText,
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
                borderSide: const BorderSide(color: _kBlue, width: 2)),
            filled: true,
            fillColor: AppColors.bg,
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

class _CSentenceQuestion extends StatelessWidget {
  final int index;
  final String words;
  final TextEditingController controller;
  final void Function(String) onChanged;

  const _CSentenceQuestion({
    required this.index,
    required this.words,
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
          _CQNum(index),
          const SizedBox(width: 10),
          Text(AppLocalizations.of(context)!.arrangeSentencePrompt,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink2)),
        ]),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kBlueMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBlueBorder),
          ),
          child: Text(words,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _kBlue)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: AppLocalizations.of(context)!.fullSentenceHintText,
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
                borderSide: const BorderSide(color: _kBlue, width: 2)),
            filled: true,
            fillColor: AppColors.bg,
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

class _CYnQuestion extends StatelessWidget {
  final int index;
  final String questionText;
  final String? selected;
  final void Function(String) onSelect;

  const _CYnQuestion({
    required this.index,
    required this.questionText,
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
        _CQNum(index),
        const SizedBox(width: 10),
        Expanded(
            child: Text(questionText,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink1))),
        const SizedBox(width: 10),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _CYnButton(
            label: AppLocalizations.of(context)!.yesOption,
            color: AppColors.ok,
            selected: selected == 'YES',
            onTap: () => onSelect('YES'),
          ),
          const SizedBox(width: 8),
          _CYnButton(
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

class _CYnButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _CYnButton({
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
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : color)),
        ),
      );
}

class _CFillQuestion extends StatefulWidget {
  final int index;
  final String questionText;
  final String initialValue;
  final void Function(String) onChanged;

  const _CFillQuestion({
    required this.index,
    required this.questionText,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_CFillQuestion> createState() => _CFillQuestionState();
}

class _CFillQuestionState extends State<_CFillQuestion> {
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
          _CQNum(widget.index),
          const SizedBox(width: 10),
          Expanded(
              child: Text(widget.questionText,
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
            hintText: AppLocalizations.of(context)!.answerHintText,
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
                borderSide: const BorderSide(color: _kBlue, width: 2)),
            filled: true,
            fillColor: AppColors.bg,
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}
