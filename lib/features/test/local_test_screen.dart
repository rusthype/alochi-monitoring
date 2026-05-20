// lib/features/test/local_test_screen.dart — FIXED
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/data/local_test_data.dart';
import '../../core/models/models.dart';
import '../../core/services/pack_cache.dart';
import '../../shared/theme/app_theme.dart';
import '../result/celebration_screen.dart';

// ── Question model ────────────────────────────────────────────────────────────
class _LocalQ {
  final String id;
  final String tp; // 'vo' | 'en'
  final String sect;
  final String prompt;
  final List<String> opts;
  final String ans;
  final Uint8List? imgBytes;
  final String? imgUrl;
  const _LocalQ({required this.id, required this.tp, required this.sect,
    required this.prompt, required this.opts, required this.ans,
    this.imgBytes, this.imgUrl});
  bool get hasImage => imgUrl != null || imgBytes != null;
}

// ── Build from MonitoringPack ─────────────────────────────────────────────────
List<_LocalQ> buildQuestionsFromPack(MonitoringPack pack, {required int grade}) {
  final rng = math.Random();
  final qs = <_LocalQ>[];
  final shuffledVocab = List<PackVocabQ>.from(pack.vocab)..shuffle(rng);
  for (var i = 0; i < shuffledVocab.length; i++) {
    final vq = shuffledVocab[i];
    final opts = <String>[vq.ans, ...vq.wrong.take(3)]..shuffle(rng);
    Uint8List? imgBytes;
    if (vq.imgUrl == null && pack.isFallback) {
      final m = kVocabQuestions.where((q) => q.ans == vq.ans).firstOrNull;
      if (m != null && m.imgB64.isNotEmpty) {
        try { imgBytes = base64Decode(m.imgB64); } catch (_) {}
      }
    }
    qs.add(_LocalQ(id: 'vo_$i', tp: 'vo', sect: vq.cat, prompt: '',
        opts: opts, ans: vq.ans, imgBytes: imgBytes, imgUrl: vq.imgUrl));
  }
  final engQs = pack.english.where((q) => q.grade == grade).toList()..shuffle(rng);
  for (var i = 0; i < engQs.take(25).length; i++) {
    final eq = engQs[i];
    final opts = List<String>.from(eq.opts)..shuffle(rng);
    qs.add(_LocalQ(id: 'en_$i', tp: 'en', sect: eq.sect,
        prompt: eq.q, opts: opts, ans: eq.ans));
  }
  // Math: random variant, 25 ta
  if (pack.math.isNotEmpty) {
    final allVariants = pack.math
        .where((q) => q.grade == grade)
        .map((q) => q.variant).toSet().toList()..shuffle(rng);
    if (allVariants.isNotEmpty) {
      final chosenV = allVariants.first;
      final mathQs  = pack.math
          .where((q) => q.grade == grade && q.variant == chosenV)
          .toList()..shuffle(rng);
      for (var i = 0; i < mathQs.take(25).length; i++) {
        final mq   = mathQs[i];
        final opts = mq.options.toList()..shuffle(rng);
        qs.add(_LocalQ(id: 'ma_$i', tp: 'ma', sect: mq.cat,
            prompt: mq.q, opts: opts, ans: mq.ans));
      }
    }
  }
  return qs;
}

// ── Build from bundled data ───────────────────────────────────────────────────
List<_LocalQ> buildLocalQuestions({required int grade,
    required String engVariant, required int mathVariant}) {
  final rng = math.Random();
  final qs = <_LocalQ>[];
  final vocab = List<VocabQ>.from(kVocabQuestions)..shuffle(rng);
  for (var i = 0; i < vocab.length; i++) {
    final vq = vocab[i];
    Uint8List? img;
    if (vq.imgB64.isNotEmpty) {
      try { img = base64Decode(vq.imgB64); } catch (_) {}
    }
    final opts = <String>[vq.ans, ...vq.wrong.take(3)]..shuffle(rng);
    qs.add(_LocalQ(id: 'vo_$i', tp: 'vo', sect: vq.cat,
        prompt: '', opts: opts, ans: vq.ans, imgBytes: img));
  }
  final eng = kEngQuestions.where((q) => q.variant == engVariant).toList()..shuffle(rng);
  for (var i = 0; i < eng.take(25).length; i++) {
    final eq = eng[i];
    final opts = List<String>.from(eq.opts)..shuffle(rng);
    qs.add(_LocalQ(id: 'en_$i', tp: 'en', sect: eq.sect,
        prompt: eq.q, opts: opts, ans: eq.ans));
  }
  return qs;
}

// ── Screen ────────────────────────────────────────────────────────────────────
class LocalTestScreen extends StatefulWidget {
  final StudentSession session;
  final MonitoringPack? preloadedPack;
  const LocalTestScreen({super.key, required this.session, this.preloadedPack});
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
  bool _showSectionTransition = false;
  String _transitionLabel = '';
  Color _transitionColor = const Color(0xFFf59e0b);

  // ── Dots scroll controller ──
  final ScrollController _dotsCtrl = ScrollController();

  String get _engVariant {
    const m = {1: 'A', 2: 'B', 3: 'C', 4: 'D'};
    return m[widget.session.grade] ?? 'A';
  }

  _LocalQ get _q => _questions[_current];
  int get _total => _questions.length;
  bool get _isLast => _current == _total - 1;

  int get _voEnd => _questions.indexWhere((q) => q.tp == 'en');
  int get _enEnd => _questions.indexWhere((q) => q.tp == 'ma');
  int get _voCount => _voEnd == -1 ? _total : _voEnd;
  int get _enCount => _voEnd == -1 ? 0 : (_enEnd == -1 ? _total - _voEnd : _enEnd - _voEnd);
  int get _maCount => _enEnd == -1 ? 0 : _total - _enEnd;

  int get _voAnswered => _answers.keys.where((i) => i < _voCount).length;
  int get _enAnswered => _voEnd == -1 ? 0 : _answers.keys.where((i) => i >= _voCount && (_enEnd == -1 || i < _enEnd)).length;
  int get _maAnswered => _enEnd == -1 ? 0 : _answers.keys.where((i) => i >= _enEnd).length;

  String get _sectionLabel {
    if (_voEnd == -1 || _current < _voEnd) return "Lug'at";
    final enEnd = _questions.indexWhere((q) => q.tp == 'ma');
    if (enEnd == -1 || _current < enEnd) return 'Ingliz tili';
    return 'Matematika';
  }

  Color get _sectionColor {
    if (_voEnd == -1 || _current < _voEnd) return const Color(0xFFf59e0b);
    final enEnd = _questions.indexWhere((q) => q.tp == 'ma');
    if (enEnd == -1 || _current < enEnd) return const Color(0xFF0284c7);
    return const Color(0xFF7c3aed);
  }

  String get _timerDisplay {
    final m = (_timerSecs ~/ 60).toString().padLeft(2, '0');
    final s = (_timerSecs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
  bool get _timerHot => _timerSecs < 120;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedPack != null) {
      _questions = buildQuestionsFromPack(widget.preloadedPack!,
          grade: widget.session.grade);
    } else {
      _questions = buildLocalQuestions(grade: widget.session.grade,
          engVariant: _engVariant, mathVariant: widget.session.variant);
    }
    _timerSecs = 90 * 60;
    _startTimer();
  }

  @override
  void dispose() {
    _timerTimer?.cancel();
    _autoAdv?.cancel();
    _dotsCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timerTimer?.cancel();
    _timerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_timerSecs > 0) {
          _timerSecs--;
          // 5 daqiqa qolganda ogohlantirish
          if (_timerSecs == 300 && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⏰ 5 daqiqa qoldi!'),
                backgroundColor: Color(0xFFf59e0b),
                duration: Duration(seconds: 4),
              ));
          }
        } else {
          _timerTimer?.cancel();
          _finish();
        }
      });
    });
  }

  // ── Auto-scroll dots to current position ──
  void _scrollDots() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_dotsCtrl.hasClients) return;
      final targetOffset = (_current * 34.0) - 100;
      _dotsCtrl.animateTo(
        targetOffset.clamp(0.0, _dotsCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _navigate(int idx) {
    if (idx < 0 || idx >= _total) return;
    _autoAdv?.cancel();
    setState(() => _current = idx);
    _scrollDots();
  }

  void _answer(String choice) {
    if (_answers.containsKey(_current)) return;
    final correct = choice == _q.ans;
    setState(() {
      _answers[_current] = choice;

    });
    // Ovoz: neytral tap (to'g'ri/noto'g'ri bildirmaydi)
    // SoundService.instance.tap(); // TODO: tap sound

    _autoAdv?.cancel();
    _autoAdv = Timer(const Duration(milliseconds: 720), () {
      if (!mounted) return;
      if (_isLast) {
        _finish();
        return;
      }
      final next = _current + 1;
      // Bo'lim o'tish: Vocab → Ingliz
      if (_voEnd != -1 && _current == _voEnd - 1 && next == _voEnd) {
        _showTransition("Ingliz tiliga o'tilmoqda", const Color(0xFF0284c7),
            then: () => _navigate(next));
        return;
      }
      // Bo'lim o'tish: Ingliz → Matematika
      final enEnd = _questions.indexWhere((q) => q.tp == 'ma');
      if (enEnd != -1 && _current == enEnd - 1 && next == enEnd) {
        _showTransition("Matematikaga o'tilmoqda", const Color(0xFF7c3aed),
            then: () => _navigate(next));
        return;
      }
      _navigate(next);
    });
  }

  // ── Section transition overlay ──
  void _showTransition(String label, Color color, {required VoidCallback then}) {
    setState(() {
      _showSectionTransition = true;
      _transitionLabel = label;
      _transitionColor = color;
    });
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _showSectionTransition = false);
      then();
    });
  }

  // ── Finish & submit ──
  void _finish() {
    _timerTimer?.cancel();
    _autoAdv?.cancel();

    int vCor = 0, vTot = 0, eCor = 0, eTot = 0, mCor = 0, mTot = 0;
    for (var i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final ok = _answers[i] == q.ans;
      if (q.tp == 'vo') { vTot++; if (ok) vCor++; }
      else if (q.tp == 'en') { eTot++; if (ok) eCor++; }
      else { mTot++; if (ok) mCor++; }
    }
    final tot = vTot + eTot + mTot;
    final cor = vCor + eCor + mCor;
    final pct = tot > 0 ? (cor * 100 ~/ tot) : 0;

    // Backend ga yuborish (fire & forget)
    _submitResult(pct: pct, vCor: vCor, vTot: vTot, eCor: eCor,
        eTot: eTot, mCor: mCor, mTot: mTot);

    if (!mounted) return;
    Navigator.pushReplacement(context,
      MaterialPageRoute(builder: (ctx) => CelebrationScreen(
        pct: pct,
        vocabCor: vCor, vocabTot: vTot,
        engCor: eCor, engTot: eTot,
        mathCor: mCor, mathTot: mTot,
        studentName: widget.session.studentName,
        // CelebrationScreen o'z kontekstini ishlatadi
        onContinue: null,
        onRetry: () => Navigator.pushReplacement(
          ctx,
          MaterialPageRoute(builder: (_) => LocalTestScreen(
            session: widget.session,
            preloadedPack: widget.preloadedPack,
          )),
        ),
      )),
    );
  }

  Future<void> _submitResult({required int pct, required int vCor,
      required int vTot, required int eCor, required int eTot,
      required int mCor, required int mTot}) async {
    try {
      await http.post(
        Uri.parse('https://api.alochi.org/api/v1/monitoring/result/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name':    widget.session.studentName,
          'grade':   widget.session.grade,
          'variant': _engVariant,
          'source':  'flutter',
          'pct':     pct,
          'vocab':   {'cor': vCor, 'tot': vTot},
          'english': {'cor': eCor, 'tot': eTot},
          'math':    {'cor': mCor, 'tot': mTot},
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Yuborilmasa ham test davom etadi
    }
  }

  Future<bool> _onWillPop() async {
    final ok = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Testni to'xtatish?",
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text("Chiqsangiz natijalar saqlanmaydi."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Davom etish')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.err, minimumSize: const Size(90, 40)),
              child: const Text("Chiqish")),
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
        body: Stack(children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyA):
                  () => _answer(_q.opts.isNotEmpty ? _q.opts[0] : ''),
              const SingleActivator(LogicalKeyboardKey.keyB):
                  () => _answer(_q.opts.length > 1 ? _q.opts[1] : ''),
              const SingleActivator(LogicalKeyboardKey.keyC):
                  () => _answer(_q.opts.length > 2 ? _q.opts[2] : ''),
              const SingleActivator(LogicalKeyboardKey.keyD):
                  () => _answer(_q.opts.length > 3 ? _q.opts[3] : ''),
              const SingleActivator(LogicalKeyboardKey.arrowLeft):
                  () => _navigate(_current - 1),
              const SingleActivator(LogicalKeyboardKey.arrowRight):
                  () => _navigate(_current + 1),
            },
            child: Focus(
              autofocus: true,
              child: Column(children: [
                // ── 3 Section progress bars ──
                Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(children: [
                    // Lug'at
                    _SectionBar(
                      label: "Lug'at",
                      color: AppColors.vocab,
                      progress: _voCount > 0 ? _voAnswered / _voCount : 0,
                      active: _voEnd == -1 || _current < _voEnd,
                    ),
                    const SizedBox(width: 8),
                    // Ingliz
                    _SectionBar(
                      label: 'Ingliz',
                      color: AppColors.eng,
                      progress: _enCount > 0 ? _enAnswered / _enCount : 0,
                      active: _voEnd != -1 && (_enEnd == -1 || _current >= _voEnd && _current < _enEnd),
                    ),
                    const SizedBox(width: 8),
                    // Matematika
                    _SectionBar(
                      label: 'Matematika',
                      color: AppColors.math,
                      progress: _maCount > 0 ? _maAnswered / _maCount : 0,
                      active: _enEnd != -1 && _current >= _enEnd,
                    ),
                  ]),
                ),

                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.surface,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04),
                        blurRadius: 6, offset: const Offset(0, 2))]),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.session.studentName,
                          style: const TextStyle(fontSize: 13,
                              fontWeight: FontWeight.w700, color: AppColors.ink1)),
                      Text(_sectionLabel,
                          style: TextStyle(fontSize: 11, color: sc,
                              fontWeight: FontWeight.w600)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: sc.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(_sectionLabel,
                          style: TextStyle(fontSize: 11,
                              fontWeight: FontWeight.w700, color: sc)),
                    ),
                    // Streak indicator
                    const SizedBox(width: 12),
                    // Timer
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _timerHot
                            ? const Color(0xFFFEF2F2)
                            : const Color(0xFFFFF7ED),
                        border: Border.all(
                            color: _timerHot
                                ? const Color(0xFFFCA5A5)
                                : const Color(0xFFFED7AA),
                            width: 1.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_timerDisplay,
                            style: TextStyle(
                                fontFamily: 'monospace', fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: _timerHot
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF7C2D12))),
                        Text('qoldi',
                            style: TextStyle(
                                fontSize: 9, fontWeight: FontWeight.w700,
                                color: _timerHot
                                    ? const Color(0xFFDC2626)
                                    : AppColors.brand)),
                      ]),
                    ),
                  ]),
                ),

                // Body
                Expanded(child: Center(child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(children: [
                    Expanded(child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                      child: Column(children: [
                        // ── Dots (scrollable, auto-centers) ──
                        SizedBox(
                          height: 44,
                          child: ListView.separated(
                            controller: _dotsCtrl,
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: _total,
                            separatorBuilder: (_, __) => const SizedBox(width: 4),
                            itemBuilder: (_, i) {
                              final isAns = _answers.containsKey(i);
                              final isCur = i == _current;
                              // Section separator
                              final isFirstEng = _voEnd != -1 && i == _voEnd;
                              return Row(mainAxisSize: MainAxisSize.min, children: [
                                if (isFirstEng) Container(
                                  width: 2, height: 28, margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0284c7).withValues(alpha: .4),
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _navigate(i),
                                  child: _DotItem(
                                    number: i + 1,
                                    isCurrent: isCur,
                                    isAnswered: isAns,
                                    // Neytral: javob berilganini bildiradi, to'g'ri/noto'g'rini emas
                                    color: isCur
                                        ? (i < (_voEnd == -1 ? _total : _voEnd)
                                            ? const Color(0xFFf59e0b)
                                            : const Color(0xFF0284c7))
                                        : isAns
                                            ? const Color(0xFF71717A)  // kulrang = javob berildi
                                            : AppColors.ink3,
                                  ),
                                ),
                              ]);
                            },
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Question card
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 120),
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

                    // Nav bar
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border(top: BorderSide(color: AppColors.border))),
                      child: Row(children: [
                        AnimatedOpacity(
                          opacity: _current == 0 ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: SizedBox(width: 100, height: 42,
                            child: OutlinedButton.icon(
                              onPressed: _current == 0
                                  ? null : () => _navigate(_current - 1),
                              icon: const Icon(Icons.arrow_back_rounded, size: 14),
                              label: const Text('Oldingi',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.ink2,
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('${_answers.length} / $_total',
                              style: const TextStyle(fontSize: 15,
                                  fontWeight: FontWeight.w800, color: AppColors.ink1)),
                          const Text('javoblandi',
                              style: TextStyle(fontSize: 10, color: AppColors.ink3)),
                        ])),
                        SizedBox(width: 100, height: 42,
                          child: _isLast
                              ? ElevatedButton.icon(
                                  onPressed: _finish,
                                  icon: const Icon(Icons.check_rounded, size: 14),
                                  label: const Text('Tugatish',
                                      style: TextStyle(fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.ok,
                                      foregroundColor: Colors.white, elevation: 0,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10))),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () => _navigate(_current + 1),
                                  icon: const Text('Keyingi',
                                      style: TextStyle(fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                  label: const Icon(Icons.arrow_forward_rounded, size: 14),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: sc,
                                      foregroundColor: Colors.white, elevation: 0,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10))),
                                ),
                        ),
                      ]),
                    ),
                  ]),
                ))),
              ]),
            ),
          ),



          // ── Section transition overlay ──
          if (_showSectionTransition)
            AnimatedOpacity(
              opacity: _showSectionTransition ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                color: Colors.black.withValues(alpha: .7),
                child: Center(child: Column(
                  mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _transitionColor.withValues(alpha: .3)),
                    ),
                    child: Column(children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: _transitionColor.withValues(alpha: .1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check_circle_rounded,
                            color: _transitionColor, size: 30),
                      ),
                      const SizedBox(height: 16),
                      Text(_transitionLabel,
                          style: TextStyle(fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _transitionColor)),
                    ]),
                  ),
                ])),
              ),
            ),
        ]),
      ),
    );
  }
}

// ── Dot item widget ───────────────────────────────────────────────────────────
class _DotItem extends StatelessWidget {
  final int number;
  final bool isCurrent, isAnswered;
  final Color color;
  const _DotItem({required this.number, required this.isCurrent,
    required this.isAnswered, required this.color});

  @override
  Widget build(BuildContext context) {
    final size = isCurrent ? 32.0 : 28.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCurrent
              ? color
              : isAnswered
                  ? color.withValues(alpha: .12)
                  : AppColors.surface,
          border: Border.all(color: color, width: isCurrent ? 0 : 1.5),
        ),
        child: Center(child: Text(
          number.toString().padLeft(2, '0'),
          style: TextStyle(
            fontSize: isCurrent ? 10 : 9,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
            color: isCurrent
                ? Colors.white
                : isAnswered
                    ? color
                    : AppColors.ink3,
          ),
        )),
      ),
      const SizedBox(height: 2),
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 2.5, width: isCurrent ? 16 : 0,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(2)),
      ),
    ]);
  }
}

// ── Question card ─────────────────────────────────────────────────────────────
class _QuestionCard extends StatelessWidget {
  final _LocalQ q;
  final Color sectionColor;
  final int number, total;
  final String? selectedAns;
  final void Function(String) onAnswer;
  const _QuestionCard({super.key, required this.q, required this.sectionColor,
    required this.number, required this.total,
    required this.selectedAns, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final sc = sectionColor;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04),
              blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Stack(children: [
          Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 4,
            decoration: BoxDecoration(color: sc,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16))))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: sc,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('$number / $total',
                      style: const TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 10)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.bg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border)),
                  child: Text(q.tp == 'vo' ? "Lug'at" : 'Ingliz',
                      style: const TextStyle(fontSize: 10,
                          color: AppColors.ink2, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 14),

              // ── FIX 1: Rasm MARKAZDA ──
              if (q.hasImage) ...[
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260, maxWidth: 440),
                      child: q.imgUrl != null
                          ? CachedNetworkImage(
                              imageUrl: q.imgUrl!,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => SizedBox(height: 120,
                                child: Center(child: CircularProgressIndicator(
                                    strokeWidth: 2, color: sc))),
                              errorWidget: (_, __, ___) =>
                                const SizedBox(height: 80, child: Center(
                                  child: Icon(Icons.broken_image_outlined,
                                      size: 48, color: Color(0xFFD4D4D8)))),
                            )
                          : Image.memory(q.imgBytes!, fit: BoxFit.contain),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Center(child: Text('Bu nima?',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                        color: AppColors.ink1))),
              ] else if (q.prompt.isNotEmpty) ...[
                Text(q.prompt, style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: AppColors.ink1, height: 1.45)),
              ],
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      ...List.generate(q.opts.length, (i) {
        final opt = q.opts[i];
        final label = 'ABCD'[i < 4 ? i : 0];
        return Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: _OptionRow(label: label, text: opt,
              selected: selectedAns == opt,
              // Neytral rang — to'g'ri/noto'g'ri ko'rsatmaydi
              accentColor: const Color(0xFF71717A),
              onTap: () => onAnswer(opt)),
        );
      }),
    ]);
  }
}

// ── Option row ────────────────────────────────────────────────────────────────
class _OptionRow extends StatefulWidget {
  final String label, text;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;
  const _OptionRow({required this.label, required this.text,
    required this.selected, required this.accentColor, required this.onTap});
  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bar;
  late final Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _bar = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 680));
    _barAnim = CurvedAnimation(parent: _bar, curve: Curves.linear);
  }

  @override
  void didUpdateWidget(_OptionRow old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _bar.forward(from: 0);
    else if (!widget.selected && old.selected) _bar.reset();
  }

  @override
  void dispose() { _bar.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ac = widget.accentColor;
    final sel = widget.selected;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          color: sel ? ac.withValues(alpha: .07) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? ac : const Color(0xFFE4E4E7),
              width: sel ? 2 : 1.5),
          boxShadow: sel
              ? [BoxShadow(color: ac.withValues(alpha: .1),
                  blurRadius: 8, offset: const Offset(0, 2))]
              : [BoxShadow(color: Colors.black.withValues(alpha: .02),
                  blurRadius: 2, offset: const Offset(0, 1))],
        ),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: sel ? ac : const Color(0xFFF4F4F5),
                  border: Border.all(
                      color: sel ? ac : const Color(0xFFD4D4D8), width: 1.5),
                  borderRadius: BorderRadius.circular(9)),
                child: Center(child: Text(widget.label,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12,
                        color: sel ? Colors.white : const Color(0xFFA1A1AA)))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.text,
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w500, color: AppColors.ink1))),
              if (sel) ...[
                const SizedBox(width: 8),
                Container(width: 20, height: 20,
                  decoration: BoxDecoration(color: ac, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded,
                      size: 12, color: Colors.white)),
              ],
            ]),
          ),
          if (sel) Positioned(left: 0, right: 0, bottom: 0,
            child: AnimatedBuilder(animation: _barAnim,
              builder: (_, __) => FractionallySizedBox(
                widthFactor: _barAnim.value,
                alignment: Alignment.centerLeft,
                child: Container(height: 3,
                  decoration: BoxDecoration(color: ac,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12)))),
              ))),
        ]),
      ),
    );
  }
}

// ── Section Progress Bar widget ─────────────────────────────────────────────────────────────────────────
class _SectionBar extends StatelessWidget {
  final String label;
  final Color  color;
  final double progress; // 0.0 – 1.0
  final bool   active;   // hozirgi section

  const _SectionBar({
    required this.label,
    required this.color,
    required this.progress,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final done = progress >= 1.0;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Label
        AnimatedOpacity(
          opacity: active || done ? 1.0 : 0.35,
          duration: const Duration(milliseconds: 300),
          child: Row(children: [
            Text(label,
              style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: done ? AppColors.ok : color,
              )),
            if (done) ...[const SizedBox(width: 3),
              Icon(Icons.check_circle_rounded, size: 9, color: AppColors.ok)],
          ]),
        ),
        const SizedBox(height: 3),
        // Bar track
        AnimatedOpacity(
          opacity: active || done ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 300),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(children: [
              Container(height: 5,
                color: color.withValues(alpha: .12)),
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOut,
                widthFactor: progress.clamp(0.0, 1.0),
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: done ? AppColors.ok : color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
