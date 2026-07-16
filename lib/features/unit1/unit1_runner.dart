// lib/features/unit1/unit1_runner.dart
// Offline English test runner — Grade 1, Unit 1 (49 questions, 49 minutes)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../core/db/history_db.dart';
import '../../core/db/offline_queue.dart';
import '../../core/api/api_client.dart';
import '../../core/sync/sync_service.dart';
import '../../core/services/pdf_service.dart';
import 'package:printing/printing.dart';
import 'unit1_data.dart';
import '../../shared/widgets/app_network_image.dart';
import '../../core/utils/topic_format.dart';

// ── Unit1 blue accent (distinct from brand orange) ────────────────────────────
const Color _kBlue = Color(0xFF3B82F6);
const Color _kBlueMuted = Color(0xFFEFF6FF);
const Color _kBlueBorder = Color(0xFFBFDBFE);

// ── Score color per project rules ─────────────────────────────────────────────
Color _scoreColor(double pct) {
  if (pct >= 90) return Colors.green;
  if (pct >= 75) return Colors.white;
  if (pct >= 60) return Colors.yellow;
  return Colors.red;
}

// ─────────────────────────────────────────────────────────────────────────────
// Unit1Runner
// ─────────────────────────────────────────────────────────────────────────────

class Unit1Runner extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String school;
  final int variant; // 1–15
  final Unit1TestData testData;

  const Unit1Runner({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.school,
    required this.variant,
    required this.testData,
  });

  @override
  State<Unit1Runner> createState() => _Unit1RunnerState();
}

class _Unit1RunnerState extends State<Unit1Runner>
    with TickerProviderStateMixin {
  // Section index: 0=vocab, 1=grammar, 2=spelling, 3=sentences, 4=reading
  int _sectionIdx = 0;

  // Answer state
  final List<int?> _vocabAns = List.filled(25, null);
  final List<int?> _grammarAns = List.filled(6, null);
  final List<String> _spellingAns = List.generate(6, (_) => '');
  final List<String> _sentenceAns = List.generate(6, (_) => '');
  final List<dynamic> _readingAns = List.filled(6, null);

  // Text controllers
  late final List<TextEditingController> _spellingCtrl;
  late final List<TextEditingController> _sentenceCtrl;

  // Timer
  Timer? _timer;
  int _secs = 49 * 60;

  // Animation
  late final AnimationController _fadeCtrl;

  static const int _totalQs = 49;

  static const List<String> _sectionNames = [
    'Vocabulary',
    'Grammar',
    'Spelling',
    'Sentences',
    'Reading',
  ];

  // Section question counts for tab badge display
  static const List<int> _sectionCounts = [25, 6, 6, 6, 6];

  Unit1Variant get _variant =>
      widget.testData.variants[widget.variant.toString()]!;

  @override
  void initState() {
    super.initState();

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
      case 0:
        return _vocabAns.where((a) => a != null).length;
      case 1:
        return _grammarAns.where((a) => a != null).length;
      case 2:
        return _spellingAns.where((s) => s.trim().isNotEmpty).length;
      case 3:
        return _sentenceAns.where((s) => s.trim().isNotEmpty).length;
      case 4:
        return _readingAns.where((a) => a != null).length;
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

  String get _studentName {
    final last = widget.lastName.trim();
    final first = widget.firstName.trim();
    return '$last $first'.trim();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goSection(int idx) {
    if (idx < 0 || idx >= 5) return;
    _fadeCtrl.forward(from: 0);
    setState(() => _sectionIdx = idx);
  }

  // ── Finish flow ────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    _timer?.cancel();

    final unanswered = _totalQs - _totalAnswered;
    if (unanswered > 0) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Tugatish?',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Text('$unanswered ta savol javobsiz. Tugatmoqchimisiz?'),
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
              child: const Text('Orqaga'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(100, 40)),
              child: const Text('Tugatish'),
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

    // Scoring
    final variant = _variant;
    final List<Map<String, dynamic>> answers = [];

    int vocabOk = 0;
    for (int i = 0; i < variant.vocab.length; i++) {
      final selectedIdx = i < _vocabAns.length ? _vocabAns[i] : null;
      final bool ok =
          selectedIdx != null && selectedIdx == variant.vocab[i].ans;
      if (ok) vocabOk++;
      answers.add({
        'section': 'Vocabulary',
        'q': variant.vocab[i].q,
        'chosen': (selectedIdx != null &&
                selectedIdx >= 0 &&
                selectedIdx < variant.vocab[i].opts.length)
            ? variant.vocab[i].opts[selectedIdx]
            : '',
        'correct': (variant.vocab[i].ans >= 0 &&
                variant.vocab[i].ans < variant.vocab[i].opts.length)
            ? variant.vocab[i].opts[variant.vocab[i].ans]
            : '',
        'ok': ok,
      });
    }

    int grammarOk = 0;
    for (int i = 0; i < variant.grammar.length; i++) {
      final selectedIdx = i < _grammarAns.length ? _grammarAns[i] : null;
      final bool ok =
          selectedIdx != null && selectedIdx == variant.grammar[i].ans;
      if (ok) grammarOk++;
      answers.add({
        'section': 'Grammar',
        'q': variant.grammar[i].q,
        'chosen': (selectedIdx != null &&
                selectedIdx >= 0 &&
                selectedIdx < variant.grammar[i].opts.length)
            ? variant.grammar[i].opts[selectedIdx]
            : '',
        'correct': (variant.grammar[i].ans >= 0 &&
                variant.grammar[i].ans < variant.grammar[i].opts.length)
            ? variant.grammar[i].opts[variant.grammar[i].ans]
            : '',
        'ok': ok,
      });
    }

    int spellingOk = 0;
    for (int i = 0; i < variant.spelling.length; i++) {
      final typed =
          i < _spellingAns.length ? _spellingAns[i].trim() : '';
      final bool ok = typed.toLowerCase() ==
          variant.spelling[i].ans.trim().toLowerCase();
      if (ok) spellingOk++;
      answers.add({
        'section': 'Spelling',
        'q': 'Harflarni tartibga sol: ${variant.spelling[i].scramble}',
        'chosen': typed,
        'correct': variant.spelling[i].ans,
        'ok': ok,
      });
    }

    int sentenceOk = 0;
    for (int i = 0; i < variant.sentences.length; i++) {
      final typed =
          i < _sentenceAns.length ? _sentenceAns[i].trim() : '';
      String userAns = typed.toLowerCase();
      // Strip trailing period if user typed one
      if (userAns.endsWith('.')) {
        userAns = userAns.substring(0, userAns.length - 1).trim();
      }
      String correctAns = variant.sentences[i].ans.trim().toLowerCase();
      if (correctAns.endsWith('.')) {
        correctAns =
            correctAns.substring(0, correctAns.length - 1).trim();
      }
      final bool ok = userAns == correctAns;
      if (ok) sentenceOk++;
      answers.add({
        'section': 'Sentences',
        'q': 'Jumlani tuz: ${variant.sentences[i].words}',
        'chosen': typed,
        'correct': variant.sentences[i].ans,
        'ok': ok,
      });
    }

    int readingOk = 0;
    final reading = variant.reading;
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
            ans.trim().toLowerCase() ==
                (q.ans as String).trim().toLowerCase();
        if (ok) readingOk++;
      } else if (q.type == 'mc') {
        final correctIdx = q.ans as int;
        final opts = q.opts ?? [];
        correct = (correctIdx >= 0 && correctIdx < opts.length)
            ? opts[correctIdx]
            : '';
        chosen = (ans is int && ans >= 0 && ans < opts.length)
            ? opts[ans]
            : '';
        ok = ans is int && ans == correctIdx;
        if (ok) readingOk++;
      } else {
        // fill
        correct = (q.ans as String);
        chosen = (ans is String) ? ans.trim() : '';
        ok = ans is String &&
            ans.trim().toLowerCase() ==
                (q.ans as String).trim().toLowerCase();
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

    final correct = vocabOk + grammarOk + spellingOk + sentenceOk + readingOk;
    final pct = (correct * 100 / _totalQs).round();

    // Build detail map
    final detail = {
      'test_key': 'unit1_eng',
      'topics': topicsFromSections([
        {'name': 'Vocabulary', 'cor': vocabOk, 'tot': 25},
        {'name': 'Grammar', 'cor': grammarOk, 'tot': 6},
        {'name': 'Spelling', 'cor': spellingOk, 'tot': 6},
        {'name': 'Sentences', 'cor': sentenceOk, 'tot': 6},
        {'name': 'Reading', 'cor': readingOk, 'tot': 6},
      ]),
    };

    // Save to history
    try {
      await HistoryDb.insertResult(
        firstName: widget.firstName,
        lastName: widget.lastName,
        school: widget.school.isEmpty ? '—' : widget.school,
        gradeGroup: '1-sinf Unit 1',
        mathScore: 0,
        engScore: correct,
        totalPct: pct.toDouble(),
      );
    } catch (e) {
      debugPrint('HistoryDb error: $e');
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => Unit1ResultScreen(
          studentName: _studentName,
          firstName: widget.firstName,
          lastName: widget.lastName,
          school: widget.school,
          variant: widget.variant,
          correct: correct,
          total: _totalQs,
          pct: pct,
          vocabOk: vocabOk,
          grammarOk: grammarOk,
          spellingOk: spellingOk,
          sentenceOk: sentenceOk,
          readingOk: readingOk,
          answers: answers,
          detail: detail,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final progress =
        _totalQs > 0 ? _totalAnswered / _totalQs : 0.0;
    final isLast = _sectionIdx == 4;

    return Scaffold(
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
                color: progress >= 1.0 ? AppColors.ok : _kBlue,
                borderRadius:
                    const BorderRadius.horizontal(right: Radius.circular(3)),
              ),
            ),
          ]),
        ),

        // ── Top bar
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                width: 30, height: 30,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.school_outlined,
                    size: 30,
                    color: _kBlue)),
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
                      const _Pill('Unit 1 G1', _kBlue),
                      const SizedBox(width: 6),
                      _Pill('Variant ${widget.variant}', AppColors.brand),
                    ]),
                  ]),
            ),
            // Answered counter
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$_totalAnswered/$_totalQs',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink1)),
                const Text('javoblandi',
                    style: TextStyle(fontSize: 9, color: AppColors.ink3)),
              ]),
            ),
            // Timer
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _timerHot
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFEFF6FF),
                border: Border.all(
                  color: _timerHot
                      ? const Color(0xFFFCA5A5)
                      : _kBlueBorder,
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
                            ? const Color(0xFFDC2626)
                            : _kBlue)),
                Text('qoldi',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _timerHot
                            ? const Color(0xFFDC2626)
                            : _kBlue)),
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
              children: List.generate(5, (i) {
                final answered = _answeredInSection(i);
                final total = _sectionCounts[i];
                final isActive = i == _sectionIdx;
                final isDone = answered == total;
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
                          color:
                              isActive ? _kBlue : Colors.transparent,
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
                                  ? _kBlue
                                  : AppColors.ink2)),
                      const SizedBox(width: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDone
                              ? AppColors.ok.withValues(alpha: .15)
                              : isActive
                                  ? _kBlueMuted
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
                                        ? _kBlue
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
            border:
                const Border(top: BorderSide(color: AppColors.border)),
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
                  label: const Text('Oldingi',
                      style: TextStyle(
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
                      label: const Text('Tugatish',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
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
                      icon: const Text('Keyingi',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      label: const Icon(
                          Icons.arrow_forward_rounded,
                          size: 15),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
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
        return _buildSentencesSection();
      case 4:
        return _buildReadingSection();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Vocabulary (image MCQ, 25 questions) ──────────────────────────────────

  Widget _buildVocabSection() {
    final vocab = _variant.vocab;
    if (vocab.isEmpty) {
      return const _SectionScroll(
          child: Center(
              child: Text('Vocabulary savollari topilmadi.',
                  style: TextStyle(color: AppColors.ink2))));
    }
    return _SectionScroll(
      child: Column(
        children: List.generate(vocab.length, (i) {
          final q = vocab[i];
          return _VocabImgQuestion(
            index: i,
            question: q,
            selected: _vocabAns[i],
            onSelect: (idx) => setState(() => _vocabAns[i] = idx),
          );
        }),
      ),
    );
  }

  // ── Grammar (text MCQ, 6 questions) ───────────────────────────────────────

  Widget _buildGrammarSection() {
    final grammar = _variant.grammar;
    if (grammar.isEmpty) {
      return const _SectionScroll(
          child: Center(
              child: Text('Grammar savollari topilmadi.',
                  style: TextStyle(color: AppColors.ink2))));
    }
    return _SectionScroll(
      child: Column(
        children: List.generate(grammar.length, (i) {
          final q = grammar[i];
          return _TextMcQuestion(
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
    final spelling = _variant.spelling;
    if (spelling.isEmpty) {
      return const _SectionScroll(
          child: Center(
              child: Text('Spelling savollari topilmadi.',
                  style: TextStyle(color: AppColors.ink2))));
    }
    return _SectionScroll(
      child: Column(
        children: List.generate(spelling.length, (i) {
          final q = spelling[i];
          return _SpellingQuestion(
            index: i,
            scramble: q.scramble,
            controller: _spellingCtrl[i],
            onChanged: (v) =>
                setState(() => _spellingAns[i] = v.toLowerCase()),
          );
        }),
      ),
    );
  }

  // ── Sentences (scrambled words → type sentence, 6 questions) ──────────────

  Widget _buildSentencesSection() {
    final sentences = _variant.sentences;
    if (sentences.isEmpty) {
      return const _SectionScroll(
          child: Center(
              child: Text('Sentences savollari topilmadi.',
                  style: TextStyle(color: AppColors.ink2))));
    }
    return _SectionScroll(
      child: Column(
        children: List.generate(sentences.length, (i) {
          final q = sentences[i];
          return _SentenceQuestion(
            index: i,
            words: q.words,
            controller: _sentenceCtrl[i],
            onChanged: (v) => setState(() => _sentenceAns[i] = v),
          );
        }),
      ),
    );
  }

  // ── Reading (scene + passage + 6 mixed questions) ─────────────────────────

  Widget _buildReadingSection() {
    final reading = _variant.reading;
    return _SectionScroll(
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
                          fontSize: 14,
                          height: 1.6,
                          color: AppColors.ink2)),
              ],
            ),
          ),

          // Reading questions
          if (reading.qs.isEmpty)
            const Center(
                child: Text('Reading savollari topilmadi.',
                    style: TextStyle(color: AppColors.ink2)))
          else
            ...List.generate(reading.qs.length, (i) {
              final q = reading.qs[i];
              if (q.type == 'yn') {
                return _YnQuestion(
                  index: i,
                  questionText: q.q,
                  selected: _readingAns[i] as String?,
                  onSelect: (v) => setState(() => _readingAns[i] = v),
                );
              } else if (q.type == 'mc') {
                final opts = q.opts ?? [];
                return _TextMcQuestion(
                  index: i,
                  questionText: q.q,
                  opts: opts,
                  selected: _readingAns[i] as int?,
                  onSelect: (idx) =>
                      setState(() => _readingAns[i] = idx),
                );
              } else {
                // fill
                return _FillQuestion(
                  index: i,
                  questionText: q.q,
                  initialValue: _readingAns[i] is String
                      ? _readingAns[i] as String
                      : '',
                  onChanged: (v) =>
                      setState(() => _readingAns[i] = v),
                );
              }
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unit1ResultScreen
// ─────────────────────────────────────────────────────────────────────────────

class Unit1ResultScreen extends StatefulWidget {
  final String studentName;
  final String firstName;
  final String lastName;
  final String school;
  final int variant;
  final int correct;
  final int total;
  final int pct;
  final int vocabOk;
  final int grammarOk;
  final int spellingOk;
  final int sentenceOk;
  final int readingOk;
  final List<Map<String, dynamic>> answers;
  final Map<String, dynamic> detail;

  const Unit1ResultScreen({
    super.key,
    required this.studentName,
    required this.firstName,
    required this.lastName,
    required this.school,
    required this.variant,
    required this.correct,
    required this.total,
    required this.pct,
    required this.vocabOk,
    required this.grammarOk,
    required this.spellingOk,
    required this.sentenceOk,
    required this.readingOk,
    required this.answers,
    required this.detail,
  });

  @override
  State<Unit1ResultScreen> createState() => _Unit1ResultScreenState();
}

class _Unit1ResultScreenState extends State<Unit1ResultScreen> {
  String _sendStatus = 'Yuborilmoqda...';
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
      SyncService.instance.flushNow();
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sendStatus = 'Saqlandi, yuborilmoqda...';
      });
    } catch (e) {
      debugPrint('Unit1 enqueue error: $e');
      if (!mounted) return;
      setState(() {
        _error = true;
        _sendStatus = 'Saqlashda xato. Qayta urinib ko\'ring.';
      });
    }
  }

  Map<String, dynamic> _buildPayload() {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return {
      'name': '${widget.lastName} ${widget.firstName}'.trim(),
      'grade': 1,
      'variant': widget.variant.toString(),
      'source': 'flutter',
      'vocab': {'cor': 0, 'tot': 0},
      'english': {'cor': widget.correct, 'tot': 49},
      'math': {'cor': 0, 'tot': 0},
      'pct': widget.pct,
      'time': time,
      'school_code': widget.school,
      'answers': widget.answers,
      'detail': widget.detail,
    };
  }

  List<MapEntry<String, ({int ok, int tot})>> get _engTopics => [
        MapEntry('Vocabulary', (ok: widget.vocabOk, tot: 25)),
        MapEntry('Grammar', (ok: widget.grammarOk, tot: 6)),
        MapEntry('Spelling', (ok: widget.spellingOk, tot: 6)),
        MapEntry('Sentences', (ok: widget.sentenceOk, tot: 6)),
        MapEntry('Reading', (ok: widget.readingOk, tot: 6)),
      ];

  @override
  Widget build(BuildContext context) {
    final pct = widget.pct;
    final correct = widget.correct;
    final total = widget.total;
    final vocabOk = widget.vocabOk;
    final grammarOk = widget.grammarOk;
    final spellingOk = widget.spellingOk;
    final sentenceOk = widget.sentenceOk;
    final readingOk = widget.readingOk;
    final studentName = widget.studentName;
    final scoreColor = _scoreColor(pct.toDouble());
    final isPass = pct >= 60;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                  Text(studentName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink1)),
                  const SizedBox(height: 4),
                  const Text('1-sinf Unit 1 — Ingliz tili',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.ink2)),
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
                          child: Text('$pct%',
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: scoreColor == Colors.white
                                      ? AppColors.ink1
                                      : scoreColor)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('$correct / $total to\'g\'ri',
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink1)),
                      const SizedBox(height: 20),

                      // Section breakdown
                      const Divider(),
                      const SizedBox(height: 12),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Bo\'limlar natijasi',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink2)),
                      ),
                      const SizedBox(height: 10),
                      _BreakdownRow(
                          label: 'Vocabulary',
                          correct: vocabOk,
                          total: 25,
                          color: _kBlue),
                      _BreakdownRow(
                          label: 'Grammar',
                          correct: grammarOk,
                          total: 6,
                          color: const Color(0xFF7C3AED)),
                      _BreakdownRow(
                          label: 'Spelling',
                          correct: spellingOk,
                          total: 6,
                          color: const Color(0xFF0891B2)),
                      _BreakdownRow(
                          label: 'Sentences',
                          correct: sentenceOk,
                          total: 6,
                          color: AppColors.brand),
                      _BreakdownRow(
                          label: 'Reading',
                          correct: readingOk,
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
                                  ? const Color(0xFF86EFAC)
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
                          child: Text(_sendStatus,
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
                            mathOk: 0,
                            mathTotal: 0,
                            engOk: widget.correct,
                            engTotal: 49,
                            pct: widget.pct,
                            mathTopics: const [],
                            engTopics: _engTopics,
                          );
                          await Printing.layoutPdf(
                              onLayout: (_) => pdfBytes,
                              name:
                                  '${widget.lastName}_${widget.firstName}_Natija.pdf');
                        },
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text('Chop etish'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.ink1,
                            side: const BorderSide(color: AppColors.border),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14)),
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
                            mathOk: 0,
                            mathTotal: 0,
                            engOk: widget.correct,
                            engTotal: 49,
                            pct: widget.pct,
                            mathTopics: const [],
                            engTopics: _engTopics,
                          );
                          await Printing.sharePdf(
                              bytes: pdfBytes,
                              filename:
                                  '${widget.lastName}_${widget.firstName}_Natija.pdf');
                        },
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                        label: Text(AppLocalizations.of(context)!.savePdf),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.brand,
                            side: const BorderSide(color: AppColors.brand),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // Qaytish button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context)
                          .popUntil((r) => r.isFirst),
                      icon:
                          const Icon(Icons.home_outlined, size: 18),
                      label: const Text('Qaytish',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
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

// ── Breakdown row ─────────────────────────────────────────────────────────────

class _BreakdownRow extends StatelessWidget {
  final String label;
  final int correct;
  final int total;
  final Color color;

  const _BreakdownRow({
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
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared layout helpers
// ─────────────────────────────────────────────────────────────────────────────

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

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

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

class _QNum extends StatelessWidget {
  final int index;
  const _QNum(this.index);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: _kBlueMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('${index + 1}',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _kBlue)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Option row (shared MC choice button)
// ─────────────────────────────────────────────────────────────────────────────

class _OptionRow extends StatelessWidget {
  final String label;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _OptionRow({
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
                color: selected ? _kBlue : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? _kBlue : const Color(0xFFD4D4D8),
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
                              : const Color(0xFFA1A1AA)))),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: selected
                            ? const Color(0xFF1E3A5F)
                            : AppColors.ink1))),
            if (selected)
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                    color: _kBlue, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    size: 12, color: Colors.white),
              ),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Question widgets
// ─────────────────────────────────────────────────────────────────────────────

// ── Vocabulary image MCQ ──────────────────────────────────────────────────────

class _VocabImgQuestion extends StatelessWidget {
  final int index;
  final Unit1Q question;
  final int? selected;
  final void Function(int) onSelect;

  const _VocabImgQuestion({
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
          const Text('Variantlar topilmadi.',
              style: TextStyle(color: AppColors.ink3))
        else
          ...List.generate(question.opts.length, (i) {
            final label = String.fromCharCode(65 + i); // A B C D
            return _OptionRow(
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

// ── Text MCQ (grammar + reading mc) ──────────────────────────────────────────

class _TextMcQuestion extends StatelessWidget {
  final int index;
  final String questionText;
  final List<String> opts;
  final int? selected;
  final void Function(int) onSelect;

  const _TextMcQuestion({
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
          _QNum(index),
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
          const Text('Variantlar topilmadi.',
              style: TextStyle(color: AppColors.ink3))
        else
          ...List.generate(opts.length, (i) {
            final label = String.fromCharCode(65 + i);
            return _OptionRow(
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

// ── Spelling (unscramble letters) ─────────────────────────────────────────────

class _SpellingQuestion extends StatelessWidget {
  final int index;
  final String scramble;
  final TextEditingController controller;
  final void Function(String) onChanged;

  const _SpellingQuestion({
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
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDDD6FE)),
          ),
          child: Text(scramble,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6D28D9),
                  letterSpacing: 4)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          onChanged: onChanged,
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
                    const BorderSide(color: _kBlue, width: 2)),
            filled: true,
            fillColor: AppColors.bg,
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

// ── Sentence (unscramble words) ───────────────────────────────────────────────

class _SentenceQuestion extends StatelessWidget {
  final int index;
  final String words;
  final TextEditingController controller;
  final void Function(String) onChanged;

  const _SentenceQuestion({
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
            color: _kBlueMuted,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBlueBorder),
          ),
          child: Text(words,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _kBlue)),
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
                    const BorderSide(color: _kBlue, width: 2)),
            filled: true,
            fillColor: AppColors.bg,
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

// ── Yes/No question ───────────────────────────────────────────────────────────

class _YnQuestion extends StatelessWidget {
  final int index;
  final String questionText;
  final String? selected;
  final void Function(String) onSelect;

  const _YnQuestion({
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
        _QNum(index),
        const SizedBox(width: 10),
        Expanded(
            child: Text(questionText,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink1))),
        const SizedBox(width: 10),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _YnButton(
            label: 'YES',
            color: AppColors.ok,
            selected: selected == 'YES',
            onTap: () => onSelect('YES'),
          ),
          const SizedBox(width: 8),
          _YnButton(
            label: 'NO',
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

// ── Fill-in-blank question ────────────────────────────────────────────────────

class _FillQuestion extends StatefulWidget {
  final int index;
  final String questionText;
  final String initialValue;
  final void Function(String) onChanged;

  const _FillQuestion({
    required this.index,
    required this.questionText,
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
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _QNum(widget.index),
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
                    const BorderSide(color: _kBlue, width: 2)),
            filled: true,
            fillColor: AppColors.bg,
          ),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}
