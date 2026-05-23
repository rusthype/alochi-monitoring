// lib/features/local_test/local_test_screen.dart
// Offline test screen — server kerak emas, Telegram ga yuboradi
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/theme/app_theme.dart';
import 'local_data.dart';
import '../../shared/widgets/app_network_image.dart';
import 'local_result_screen.dart';

class LocalTestScreen extends StatefulWidget {
  final String firstName, lastName, group;
  final int grade, variant;
  final List<LocalQuestion> questions;
  const LocalTestScreen(
      {super.key,
      required this.firstName,
      required this.lastName,
      required this.group,
      required this.grade,
      required this.variant,
      required this.questions});
  @override
  State<LocalTestScreen> createState() => _LocalTestScreenState();
}

class _LocalTestScreenState extends State<LocalTestScreen>
    with TickerProviderStateMixin {
  int _cur = 0;
  final Map<int, String> _answers = {};
  Timer? _timer;
  Timer? _autoAdv;
  late int _secs;

  late final AnimationController _fadeCtrl;

  int get _total => widget.questions.length;
  LocalQuestion get _q => widget.questions[_cur];
  bool get _isLast => _cur == _total - 1;
  bool get _isFirst => _cur == 0;
  int get _mathCount => widget.questions.where((q) => q.isMath).length;
  bool get _isMath => _q.isMath;
  bool get _timerHot => _secs < 120;

  String get _timerText {
    final m = (_secs ~/ 60).toString().padLeft(2, '0');
    final s = (_secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _secs = _total * 72; // ~1.2 min per question
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
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _autoAdv?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _navigate(int idx) {
    if (idx < 0 || idx >= _total) return;
    _autoAdv?.cancel();
    _fadeCtrl.forward(from: 0);
    setState(() => _cur = idx);
  }

  void _answer(String ch) {
    if (_answers[_cur] == ch) return;
    setState(() => _answers[_cur] = ch);
    if (!_isLast) {
      _autoAdv?.cancel();
      _autoAdv = Timer(const Duration(milliseconds: 720), () {
        if (mounted) _navigate(_cur + 1);
      });
    }
  }

  Future<void> _finish() async {
    _timer?.cancel();
    final unanswered = _total - _answers.length;
    if (unanswered > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Tugatish?',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Text('$unanswered ta savol javobsiz. Tugatmoqchimisiz?'),
          actions: [
            TextButton(
                onPressed: () {
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
                child: const Text('Orqaga')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size(100, 40)),
              child: const Text('Tugatish'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    // Calculate score locally
    int mathOk = 0, engOk = 0;
    final topicScores = <String, ({int ok, int tot})>{};
    for (int i = 0; i < _total; i++) {
      final q = widget.questions[i];
      final answered = _answers[i];
      final correct = answered == q.correct;
      if (q.isMath) {
        if (correct) mathOk++;
      } else {
        if (correct) engOk++;
      }

      final t =
          q.topic.isEmpty ? (q.isMath ? 'Matematika' : 'Ingliz tili') : q.topic;
      final prev = topicScores[t] ?? (ok: 0, tot: 0);
      topicScores[t] = (ok: prev.ok + (correct ? 1 : 0), tot: prev.tot + 1);
    }
    final totalOk = mathOk + engOk;
    final pct = (_total > 0) ? (totalOk * 100 ~/ _total) : 0;

    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LocalResultScreen(
            firstName: widget.firstName,
            lastName: widget.lastName,
            group: widget.group,
            grade: widget.grade,
            variant: widget.variant,
            questions: widget.questions,
            answers: Map.from(_answers),
            mathOk: mathOk,
            engOk: engOk,
            pct: pct,
            topicScores: topicScores,
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? _answers.length / _total : 0.0;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyA): () => _answer('a'),
          const SingleActivator(LogicalKeyboardKey.keyB): () => _answer('b'),
          const SingleActivator(LogicalKeyboardKey.keyC): () => _answer('c'),
          const SingleActivator(LogicalKeyboardKey.keyD): () => _answer('d'),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _navigate(_cur - 1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _navigate(_cur + 1),
        },
        child: Focus(
          autofocus: true,
          child: Column(children: [
            // Progress bar
            SizedBox(
                height: 4,
                child: Stack(children: [
                  Container(
                      width: double.infinity,
                      height: 4,
                      color: AppColors.border),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: MediaQuery.sizeOf(context).width * progress,
                    height: 4,
                    decoration: BoxDecoration(
                        color: progress == 1 ? AppColors.ok : AppColors.brand,
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(3))),
                  ),
                ])),
            // Top bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: AppColors.surface, boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .04),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('${widget.lastName} ${widget.firstName}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink1)),
                      const SizedBox(height: 2),
                      Row(children: [
                        _Pill(
                            '${widget.grade}-sinf',
                            _isMath
                                ? const Color(0xFF1E40AF)
                                : const Color(0xFF0F766E)),
                        const SizedBox(width: 6),
                        Text(_isMath ? 'Matematika' : 'Ingliz tili',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.ink3)),
                      ]),
                    ])),
                // Timer
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                      color: _timerHot
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFFFF7ED),
                      border: Border.all(
                          color: _timerHot
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFFFED7AA),
                          width: 1.5),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_timerText,
                        style: TextStyle(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _timerHot
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF7C2D12))),
                    Text('qoldi',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _timerHot
                                ? const Color(0xFFDC2626)
                                : AppColors.brand)),
                  ]),
                ),
              ]),
            ),
            // Body
            Expanded(
                child: Center(
                    child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                        child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Dots
                            SizedBox(
                                height: 42,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _total,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 4),
                                  itemBuilder: (_, i) => _QDot(
                                    number: i + 1,
                                    isCurrent: i == _cur,
                                    isAnswered: _answers.containsKey(i),
                                    isMath: i < _mathCount,
                                    onTap: () => _navigate(i),
                                  ),
                                )),
                            const SizedBox(height: 14),
                            // Question card
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 140),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                    position: Tween<Offset>(
                                            begin: const Offset(.015, 0),
                                            end: Offset.zero)
                                        .animate(anim),
                                    child: child),
                              ),
                              child: Column(
                                key: ValueKey(_cur),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Question card
                                  Container(
                                    width: double.infinity,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(16),
                                        border:
                                            Border.all(color: AppColors.border),
                                        boxShadow: [
                                          BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: .05),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3))
                                        ]),
                                    child: Stack(children: [
                                      Positioned(
                                          left: 0,
                                          top: 0,
                                          bottom: 0,
                                          child: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 250),
                                              width: 4,
                                              color: _isMath
                                                  ? AppColors.math
                                                  : AppColors.eng)),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            22, 18, 20, 16),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                      color: _isMath
                                                          ? AppColors.math
                                                          : AppColors.eng,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20)),
                                                  child: Text(
                                                      '${(_cur + 1).toString().padLeft(2, '0')} / ${_total.toString().padLeft(2, '0')}',
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 11)),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 9,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                      color: AppColors.bg,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20),
                                                      border: Border.all(
                                                          color: AppColors
                                                              .border)),
                                                  child: Text(
                                                      _isMath
                                                          ? 'Matematika'
                                                          : 'Ingliz tili',
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppColors.ink2,
                                                          fontWeight:
                                                              FontWeight.w600)),
                                                ),
                                                if (_q.topic.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                      child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                        color: const Color(
                                                            0xFFF5F3FF),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20)),
                                                    child: Text(_q.topic,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontSize: 10,
                                                            color: Color(
                                                                0xFF6D28D9),
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)),
                                                  )),
                                                ],
                                              ]),
                                              const SizedBox(height: 16),
                                              Text(_q.prompt,
                                                  style: const TextStyle(
                                                      fontSize: 19,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: AppColors.ink1,
                                                      height: 1.4)),
                                              if (_q.image != null) ...[
                                                const SizedBox(height: 14),
                                                _QuestionImage(url: _q.image!),
                                              ],
                                            ]),
                                      ),
                                    ]),
                                  ),
                                  const SizedBox(height: 12),
                                  // Options
                                  ...List.generate(4, (i) {
                                    final ch = 'abcd'[i];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _OptionRow(
                                        label: 'ABCD'[i],
                                        text: i < _q.options.length ? _q.options[i] : '',
                                        optionImage: _q.optionImages.length > i ? _q.optionImages[i] : null,
                                        selected: _answers[_cur] == ch,
                                        onTap: () => _answer(ch),
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ]),
                    )),
                    // Bottom nav
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: const Border(
                              top: BorderSide(color: AppColors.border)),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: .04),
                                blurRadius: 8,
                                offset: const Offset(0, -2))
                          ]),
                      child: Row(children: [
                        AnimatedOpacity(
                          opacity: _isFirst ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: SizedBox(
                            width: 110,
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed:
                                  _isFirst ? null : () => _navigate(_cur - 1),
                              icon: const Icon(Icons.arrow_back_rounded,
                                  size: 15),
                              label: const Text('Oldingi',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.ink2,
                                  side:
                                      const BorderSide(color: AppColors.border),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10))),
                            ),
                          ),
                        ),
                        Expanded(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Text('${_answers.length} / $_total',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink1)),
                              const Text('javoblandi',
                                  style: TextStyle(
                                      fontSize: 11, color: AppColors.ink3)),
                            ])),
                        SizedBox(
                          width: 110,
                          height: 44,
                          child: _isLast
                              ? ElevatedButton.icon(
                                  onPressed: _finish,
                                  icon:
                                      const Icon(Icons.check_rounded, size: 15),
                                  label: const Text('Tugatish',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.ok,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10))),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () => _navigate(_cur + 1),
                                  icon: const Text('Keyingi',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  label: const Icon(Icons.arrow_forward_rounded,
                                      size: 15),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.brand,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10))),
                                ),
                        ),
                      ]),
                    ),
                  ]),
            ))),
          ]),
        ),
      ),
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
            borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}

class _QDot extends StatelessWidget {
  final int number;
  final bool isCurrent, isAnswered, isMath;
  final VoidCallback onTap;
  const _QDot(
      {required this.number,
      required this.isCurrent,
      required this.isAnswered,
      required this.isMath,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final accent = isCurrent
        ? AppColors.brand
        : isAnswered
            ? const Color(0xFF86EFAC)
            : const Color(0xFFD4D4D8);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
          width: 30,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isCurrent ? 30 : 26,
              height: isCurrent ? 30 : 26,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent
                      ? AppColors.brand
                      : isAnswered
                          ? const Color(0xFFF0FDF4)
                          : AppColors.surface,
                  border: Border.all(color: accent, width: isCurrent ? 2 : 1.5),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                              color: AppColors.brand.withValues(alpha: .3),
                              blurRadius: 8,
                              spreadRadius: 1)
                        ]
                      : null),
              child: Center(
                  child: Text(number.toString().padLeft(2, '0'),
                      style: TextStyle(
                          fontSize: isCurrent ? 10 : 9,
                          fontWeight: FontWeight.w700,
                          color: isCurrent
                              ? Colors.white
                              : isAnswered
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFA1A1AA)))),
            ),
            const SizedBox(height: 3),
            AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 3,
                width: isCurrent ? 18 : 0,
                decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(2))),
          ])),
    );
  }
}


class _OptionRow extends StatefulWidget {
  final String label, text;
  final String? optionImage;
  final bool selected;
  final VoidCallback onTap;
  const _OptionRow(
      {required this.label,
      required this.text,
      this.optionImage,
      required this.selected,
      required this.onTap});
  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _barCtrl;
  late final Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 720));
    _barAnim = CurvedAnimation(parent: _barCtrl, curve: Curves.linear);
  }

  @override
  void didUpdateWidget(_OptionRow old) {
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
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: const BoxConstraints(minHeight: 54),
        decoration: BoxDecoration(
          color: widget.selected ? const Color(0xFFFFF7ED) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.selected ? AppColors.brand : const Color(0xFFE4E4E7),
            width: widget.selected ? 2 : 1.5,
          ),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                      color: AppColors.brand.withValues(alpha: .12),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .03),
                      blurRadius: 3,
                      offset: const Offset(0, 1))
                ],
        ),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              // Letter badge
              Stack(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? AppColors.brand
                        : const Color(0xFFF4F4F5),
                    border: Border.all(
                        color: widget.selected
                            ? AppColors.brand
                            : const Color(0xFFD4D4D8),
                        width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                      child: Text(widget.label,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: widget.selected
                                  ? Colors.white
                                  : const Color(0xFFA1A1AA)))),
                ),
                // Keyboard hint superscript
                Positioned(
                    top: -1,
                    right: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: widget.selected
                            ? const Color(0xFFFED7AA)
                            : const Color(0xFFD4D4D8),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                            color: widget.selected
                                ? const Color(0xFFFED7AA)
                                : const Color(0xFFE4E4E7)),
                      ),
                      child: Center(
                          child: Text(widget.label,
                              style: TextStyle(
                                  fontSize: 7,
                                  fontWeight: FontWeight.w700,
                                  color: widget.selected
                                      ? const Color(0xFF9A3412)
                                      : const Color(0xFFA1A1AA)))),
                    )),
              ]),
              const SizedBox(width: 14),
              // Option text
              Expanded(
                  child: widget.optionImage != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              if (widget.text.isNotEmpty) ...[
                                Text(widget.text,
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: widget.selected
                                            ? const Color(0xFF7C2D12)
                                            : AppColors.ink1)),
                                const SizedBox(height: 6),
                              ],
                              AppNetworkImage(
                                url: widget.optionImage,
                                height: 80,
                                fit: BoxFit.contain,
                                borderRadius: BorderRadius.circular(8),
                                errorWidget: const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.ink3,
                                  size: 20,
                                ),
                              ),
                            ])
                      : Text(widget.text,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: widget.selected
                                  ? const Color(0xFF7C2D12)
                                  : AppColors.ink1))),
              // Check
              if (widget.selected)
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(left: 10),
                  decoration: const BoxDecoration(
                      color: AppColors.brand, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded,
                      size: 13, color: Colors.white),
                ),
            ]),
          ),
          // Auto-advance bar at bottom
          if (widget.selected)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _barAnim,
                builder: (_, __) => FractionallySizedBox(
                  widthFactor: _barAnim.value,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 3,
                    decoration: const BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.only(
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

// ── Question image widget ────────────────────────────────────────────────────
class _QuestionImage extends StatelessWidget {
  final String url;
  const _QuestionImage({required this.url});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: AppNetworkImage(
              url: url,
              fit: BoxFit.contain,
              borderRadius: BorderRadius.circular(10),
              placeholder: SizedBox(
                width: double.infinity,
                height: 120,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 120,
                    width: 120,
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.brand,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                ),
              ),
          errorWidget: Builder(
            builder: (context) {
              debugPrint('IMAGE ERROR | URL: $url');
              return Container(
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.err.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.err.withValues(alpha: .2)),
                ),
                child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.broken_image_outlined,
                      color: AppColors.err.withValues(alpha: .5), size: 16),
                  const SizedBox(width: 6),
                  const Text('Rasm yuklanmadi',
                      style: TextStyle(fontSize: 11, color: AppColors.ink3)),
                ])),
              );
            },
          ),
        ),
      ),
    ),
  );
}

