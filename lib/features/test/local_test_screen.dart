// lib/features/test/local_test_screen.dart
//
// Vocab + English World 1 test ekrani.
// Savollar: API (PackCacheService) → cache → bundled fallback.
// _OptionRow: to'g'ri/noto'g'ri ko'rsatmaydi — fill bar animatsiya.
//
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/data/local_test_data.dart';
import '../../core/models/models.dart';
import '../../core/services/pack_cache.dart';
import '../../shared/theme/app_theme.dart';
import '../result/celebration_screen.dart';

// ── Local question ─────────────────────────────────────────────────────────
class _LocalQ {
  final String id;
  final String tp; // 'vo' | 'en'
  final String sect;
  final String prompt;
  final List<String> opts;
  final String ans;
  final Uint8List? imgBytes; // fallback: bundled base64
  final String? imgUrl;     // API: network image URL

  const _LocalQ({
    required this.id,
    required this.tp,
    required this.sect,
    required this.prompt,
    required this.opts,
    required this.ans,
    this.imgBytes,
    this.imgUrl,
  });

  bool get hasImage => imgUrl != null || imgBytes != null;
}

// ── Build from MonitoringPack (API / cache) ────────────────────────────────
List<_LocalQ> buildQuestionsFromPack(
  MonitoringPack pack, {
  required int grade,
}) {
  final rng = math.Random();
  final questions = <_LocalQ>[];

  // Vocab: shuffle all
  final shuffledVocab = List<PackVocabQ>.from(pack.vocab)..shuffle(rng);
  for (var i = 0; i < shuffledVocab.length; i++) {
    final vq = shuffledVocab[i];
    final allOpts = <String>[vq.ans, ...vq.wrong.take(3)]..shuffle(rng);
    Uint8List? imgBytes;
    String? imgUrl = vq.imgUrl;
    if (imgUrl == null && pack.isFallback) {
      final match = kVocabQuestions.where((q) => q.ans == vq.ans).firstOrNull;
      if (match != null && match.imgB64.isNotEmpty) {
        try { imgBytes = base64Decode(match.imgB64); } catch (_) {}
      }
    }
    questions.add(_LocalQ(
      id: 'vo_$i', tp: 'vo', sect: vq.cat, prompt: '',
      opts: allOpts, ans: vq.ans, imgBytes: imgBytes, imgUrl: imgUrl,
    ));
  }

  // English: grade bo'yicha, 25 ta
  final engQs = pack.english.where((q) => q.grade == grade).toList()..shuffle(rng);
  for (var i = 0; i < engQs.take(25).length; i++) {
    final eq = engQs[i];
    final shuffledOpts = List<String>.from(eq.opts)..shuffle(rng);
    questions.add(_LocalQ(
      id: 'en_$i', tp: 'en', sect: eq.sect,
      prompt: eq.q, opts: shuffledOpts, ans: eq.ans,
    ));
  }
  return questions;
}

// ── Build question list based on grade ──────────────────────────────────────
List<_LocalQ> buildLocalQuestions({
  required int grade,
  required String engVariant, // A/B/C/D
  required int mathVariant,   // 1-20 (not used here — math from local data if needed)
}) {
  final rng = math.Random();
  final questions = <_LocalQ>[];

  // ── 1. Vocab (58 questions, shuffled each time) ──
  final shuffledVocab = List<VocabQ>.from(kVocabQuestions)..shuffle(rng);
  for (var i = 0; i < shuffledVocab.length; i++) {
    final vq = shuffledVocab[i];
    // Decode base64 image
    Uint8List? img;
    if (vq.imgB64.isNotEmpty) {
      try {
        img = base64Decode(vq.imgB64);
      } catch (_) {}
    }
    // Build 4 options: ans + up to 3 wrong, shuffle
    final allOpts = <String>[vq.ans, ...vq.wrong.take(3)];
    allOpts.shuffle(rng);
    questions.add(_LocalQ(
      id: 'vo_$i',
      tp: 'vo',
      sect: vq.cat,
      prompt: '',
      opts: allOpts,
      ans: vq.ans,
      imgBytes: img,
    ));
  }

  // ── 2. English World 1 (25 questions, correct variant) ──
  final engQs = kEngQuestions
      .where((q) => q.variant == engVariant)
      .toList()
    ..shuffle(rng);
  final engSample = engQs.take(25).toList();
  for (var i = 0; i < engSample.length; i++) {
    final eq = engSample[i];
    // Shuffle options too
    final shuffledOpts = List<String>.from(eq.opts)..shuffle(rng);
    questions.add(_LocalQ(
      id: 'en_$i',
      tp: 'en',
      sect: eq.sect,
      prompt: eq.q,
      opts: shuffledOpts,
      ans: eq.ans,
    ));
  }

  return questions;
}

// ── LocalTestScreen ──────────────────────────────────────────────────────────
class LocalTestScreen extends StatefulWidget {
  final StudentSession session;
  final MonitoringPack? preloadedPack; // package_screen dan oldindan yuklangan

  const LocalTestScreen({
    super.key,
    required this.session,
    this.preloadedPack,
  });

  @override
  State<LocalTestScreen> createState() => _LocalTestScreenState();
}

class _LocalTestScreenState extends State<LocalTestScreen>
    with TickerProviderStateMixin {
  late final List<_LocalQ> _questions;
  int _current = 0;
  final Map<int, String> _answers = {};
  Timer? _autoAdv;
  late int _timerSecs;
  Timer? _timerTimer;

  late final AnimationController _fadeCtrl;
  // ignore: unused_field
  late final Animation<double> _fadeAnim;

  String get _engVariant {
    const map = {1: 'A', 2: 'B', 3: 'C', 4: 'D'};
    return map[widget.session.grade] ?? 'A';
  }

  _LocalQ get _q => _questions[_current];
  int get _total => _questions.length;
  bool get _isLast => _current == _total - 1;

  String get _timerDisplay {
    final m = (_timerSecs ~/ 60).toString().padLeft(2, '0');
    final s = (_timerSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _timerHot => _timerSecs < 120;

  String get _sectionLabel {
    final voEnd = _questions.indexWhere((q) => q.tp == 'en');
    if (voEnd == -1 || _current < voEnd) return "Lug'at";
    return 'Ingliz tili';
  }

  Color get _sectionColor {
    final voEnd = _questions.indexWhere((q) => q.tp == 'en');
    if (voEnd == -1 || _current < voEnd) return const Color(0xFFf59e0b);
    return const Color(0xFF0284c7);
  }

  @override
  void initState() {
    super.initState();
    // Preloaded pack bor bo'lsa undan, yo'q bo'lsa bundled fallbackdan
    if (widget.preloadedPack != null) {
      _questions = buildQuestionsFromPack(
        widget.preloadedPack!,
        grade: widget.session.grade,
      );
    } else {
      _questions = buildLocalQuestions(
        grade: widget.session.grade,
        engVariant: _engVariant,
        mathVariant: widget.session.variant,
      );
    }

    // 108 questions → ~1.5 min each = ~2.7 hours, but cap at 90 min
    _timerSecs = 90 * 60;
    _startTimer();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _timerTimer?.cancel();
    _autoAdv?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timerTimer?.cancel();
    _timerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_timerSecs > 0) {
          _timerSecs--;
        } else {
          _timerTimer?.cancel();
          _finish();
        }
      });
    });
  }

  void _navigate(int idx) {
    if (idx < 0 || idx >= _total) return;
    _autoAdv?.cancel();
    _fadeCtrl.forward(from: 0);
    setState(() => _current = idx);
  }

  void _answer(String choice) {
    if (_answers.containsKey(_current)) return;
    setState(() => _answers[_current] = choice);
    _autoAdv?.cancel();
    _autoAdv = Timer(const Duration(milliseconds: 720), () {
      if (!mounted) return;
      if (_isLast) _finish();
      else _navigate(_current + 1);
    });
  }

  void _finish() {
    _timerTimer?.cancel();
    _autoAdv?.cancel();

    // Count results
    int vCor = 0, vTot = 0, eCor = 0, eTot = 0, mCor = 0, mTot = 0;
    for (var i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final ok = _answers[i] == q.ans;
      if (q.tp == 'vo') { vTot++; if (ok) vCor++; }
      else if (q.tp == 'en') { eTot++; if (ok) eCor++; }
      else { mTot++; if (ok) mCor++; }
    }

    // Navigate to celebration screen (new page)
    final tot = vTot + eTot + mTot;
    final cor = vCor + eCor + mCor;
    final pct = tot > 0 ? (cor * 100 ~/ tot) : 0;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CelebrationScreen(
          pct: pct,
          vocabCor: vCor, vocabTot: vTot,
          engCor: eCor, engTot: eTot,
          mathCor: mCor, mathTot: mTot,
          studentName: widget.session.studentName,
          onContinue: () {
            // Could navigate to a result/PDF screen here
            Navigator.popUntil(context, (r) => r.isFirst);
          },
          onRetry: () {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => LocalTestScreen(
                  session: widget.session,
                  preloadedPack: widget.preloadedPack,
                )));
          },
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Testni to'xtatish?",
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text("Jarayondan chiqsangiz javoblar saqlanmaydi."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Davom etish')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.err,
                minimumSize: const Size(90, 40)),
            child: const Text("Chiqish"),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? _answers.length / _total : 0.0;
    final sc = _sectionColor;

    return PopScope(
      canPop: false,
      onPopInvoked: (popped) async {
        if (!popped) {
          final ok = await _onWillPop();
          if (ok && context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyA): () => _answer(_q.opts.isNotEmpty ? _q.opts[0] : ''),
            const SingleActivator(LogicalKeyboardKey.keyB): () => _answer(_q.opts.length > 1 ? _q.opts[1] : ''),
            const SingleActivator(LogicalKeyboardKey.keyC): () => _answer(_q.opts.length > 2 ? _q.opts[2] : ''),
            const SingleActivator(LogicalKeyboardKey.keyD): () => _answer(_q.opts.length > 3 ? _q.opts[3] : ''),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _navigate(_current - 1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () => _navigate(_current + 1),
          },
          child: Focus(
            autofocus: true,
            child: Column(children: [
              // ── Progress bar (4px) ──
              SizedBox(
                height: 4,
                child: Stack(children: [
                  Container(width: double.infinity, height: 4, color: AppColors.border),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                    width: MediaQuery.sizeOf(context).width * progress,
                    height: 4,
                    decoration: BoxDecoration(
                      color: progress == 1 ? AppColors.ok : sc,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                    ),
                  ),
                ]),
              ),

              // ── Header ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04),
                      blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.session.studentName,
                        style: const TextStyle(fontSize: 14,
                            fontWeight: FontWeight.w700, color: AppColors.ink1)),
                    const SizedBox(height: 2),
                    Text(_sectionLabel,
                        style: TextStyle(fontSize: 11, color: sc, fontWeight: FontWeight.w600)),
                  ])),
                  // Section pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: sc.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_sectionLabel,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sc)),
                  ),
                  const SizedBox(width: 14),
                  // Timer
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: _timerHot ? const Color(0xFFFEF2F2) : const Color(0xFFFFF7ED),
                      border: Border.all(
                          color: _timerHot ? const Color(0xFFFCA5A5) : const Color(0xFFFED7AA),
                          width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_timerDisplay,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 20, fontWeight: FontWeight.w700,
                            color: _timerHot ? const Color(0xFFDC2626) : const Color(0xFF7C2D12),
                          )),
                      Text('qoldi', style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700,
                          color: _timerHot ? const Color(0xFFDC2626) : AppColors.brand)),
                    ]),
                  ),
                ]),
              ),

              // ── Body ──
              Expanded(child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Question dots
                      SizedBox(height: 42, child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _total,
                        separatorBuilder: (_, __) => const SizedBox(width: 4),
                        itemBuilder: (_, i) {
                          final isAns = _answers.containsKey(i);
                          final isCur = i == _current;
                          final dotColor = isCur ? sc
                              : isAns ? const Color(0xFF86EFAC)
                              : const Color(0xFFD4D4D8);
                          return GestureDetector(
                            onTap: () => _navigate(i),
                            child: SizedBox(width: 30, child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: isCur ? 30 : 26,
                                  height: isCur ? 30 : 26,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isCur ? sc
                                        : isAns ? const Color(0xFFF0FDF4)
                                        : AppColors.surface,
                                    border: Border.all(color: dotColor, width: 1.5),
                                  ),
                                  child: Center(child: Text(
                                    (i + 1).toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: isCur ? 10 : 9,
                                      fontWeight: FontWeight.w700,
                                      fontFamily: 'monospace',
                                      color: isCur ? Colors.white
                                          : isAns ? const Color(0xFF16A34A)
                                          : const Color(0xFFA1A1AA),
                                    ),
                                  )),
                                ),
                                const SizedBox(height: 3),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  height: 3,
                                  width: isCur ? 18 : 0,
                                  decoration: BoxDecoration(
                                    color: sc,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ],
                            )),
                          );
                        },
                      )),
                      const SizedBox(height: 14),

                      // Question card
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 140),
                        child: _QuestionCard(
                          key: ValueKey(_current),
                          q: _q,
                          sectionColor: sc,
                          number: _current + 1,
                          total: _total,
                          selectedAns: _answers[_current],
                          onAnswer: _answer,
                        ),
                      ),
                    ]),
                  )),

                  // ── Nav bar ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(children: [
                      AnimatedOpacity(
                        opacity: _current == 0 ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: SizedBox(width: 110, height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _current == 0 ? null : () => _navigate(_current - 1),
                            icon: const Icon(Icons.arrow_back_rounded, size: 15),
                            label: const Text('Oldingi',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.ink2,
                              side: const BorderSide(color: AppColors.border),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('${_answers.length} / $_total',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                                color: AppColors.ink1)),
                        const Text('javoblandi',
                            style: TextStyle(fontSize: 11, color: AppColors.ink3)),
                      ])),
                      SizedBox(width: 110, height: 44,
                        child: _isLast
                            ? ElevatedButton.icon(
                                onPressed: _finish,
                                icon: const Icon(Icons.check_rounded, size: 15),
                                label: const Text('Tugatish',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.ok,
                                  foregroundColor: Colors.white, elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: () => _navigate(_current + 1),
                                icon: const Text('Keyingi',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                label: const Icon(Icons.arrow_forward_rounded, size: 15),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: sc,
                                  foregroundColor: Colors.white, elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                      ),
                    ]),
                  ),
                ]),
              ))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Question card ────────────────────────────────────────────────────────────
class _QuestionCard extends StatelessWidget {
  final _LocalQ q;
  final Color sectionColor;
  final int number, total;
  final String? selectedAns;
  final void Function(String) onAnswer;

  const _QuestionCard({
    super.key,
    required this.q,
    required this.sectionColor,
    required this.number,
    required this.total,
    required this.selectedAns,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final sc = sectionColor;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Card
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .05),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Stack(children: [
          Positioned(left: 0, top: 0, bottom: 0,
            child: Container(width: 4,
              decoration: BoxDecoration(
                color: sc,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: sc, borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$number / $total',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 11)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.bg, borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(q.tp == 'vo' ? "Lug'at" : q.tp == 'en' ? 'Ingliz' : 'Matematika',
                      style: const TextStyle(fontSize: 11, color: AppColors.ink2,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 14),

              // Vocab: show image
              if (q.hasImage) ...[  
              ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: q.imgUrl != null
                    ? Image.network(
                          q.imgUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_not_supported_outlined,
                    size: 64, color: Color(0xFFD4D4D8),
                            ),
                          )
                        : Image.memory(q.imgBytes!, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 12),
                Text("Bu nima?",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                        color: AppColors.ink1)),
              ] else if (q.prompt.isNotEmpty) ...[
                Text(q.prompt, style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700,
                    color: AppColors.ink1, height: 1.4)),
              ],
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 10),

      // Options
      ...List.generate(q.opts.length, (i) {
        final opt = q.opts[i];
        final label = ['A', 'B', 'C', 'D'][i < 4 ? i : 0];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _LocalOptionRow(
            label: label,
            text: opt,
            selected: selectedAns == opt,
            accentColor: sc,
            onTap: () => onAnswer(opt),
          ),
        );
      }),
    ]);
  }
}

// ── Option row with fill bar, NO correct/wrong ───────────────────────────────
class _LocalOptionRow extends StatefulWidget {
  final String label, text;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _LocalOptionRow({
    required this.label,
    required this.text,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_LocalOptionRow> createState() => _LocalOptionRowState();
}

class _LocalOptionRowState extends State<_LocalOptionRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _barCtrl;
  late final Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 680));
    _barAnim = CurvedAnimation(parent: _barCtrl, curve: Curves.linear);
  }

  @override
  void didUpdateWidget(_LocalOptionRow old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      _barCtrl.forward(from: 0);
    } else if (!widget.selected && old.selected) {
      _barCtrl.reset();
    }
  }

  @override
  void dispose() {
    _barCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ac = widget.accentColor;
    final sel = widget.selected;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minHeight: 54),
        decoration: BoxDecoration(
          color: sel ? ac.withValues(alpha: .07) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? ac : const Color(0xFFE4E4E7),
            width: sel ? 2 : 1.5,
          ),
          boxShadow: sel
              ? [BoxShadow(color: ac.withValues(alpha: .12), blurRadius: 10,
                  offset: const Offset(0, 3))]
              : [BoxShadow(color: Colors.black.withValues(alpha: .03), blurRadius: 3,
                  offset: const Offset(0, 1))],
        ),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              // Letter badge
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: sel ? ac : const Color(0xFFF4F4F5),
                  border: Border.all(
                      color: sel ? ac : const Color(0xFFD4D4D8), width: 1.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(widget.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13,
                      color: sel ? Colors.white : const Color(0xFFA1A1AA),
                    ))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(widget.text, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: sel ? AppColors.ink1 : AppColors.ink1))),
              if (sel) Container(
                width: 22, height: 22, margin: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(color: ac, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
              ),
            ]),
          ),
          // ── FILL BAR (chapdan o'ngga) ──
          if (sel) Positioned(
            left: 0, right: 0, bottom: 0,
            child: AnimatedBuilder(
              animation: _barAnim,
              builder: (_, __) => FractionallySizedBox(
                widthFactor: _barAnim.value,
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 3.5,
                  decoration: BoxDecoration(
                    color: ac,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
