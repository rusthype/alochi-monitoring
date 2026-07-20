// lib/features/test/test_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../core/api/api_client.dart';
import '../../core/db/offline_queue.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_network_image.dart';
import '../result/result_screen.dart';

class TestScreen extends StatefulWidget {
  final StudentSession session;
  final TestPackage package;
  final List<Question> questions;
  const TestScreen(
      {super.key,
      required this.session,
      required this.package,
      required this.questions});
  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> with TickerProviderStateMixin {
  int _current = 0;
  final Map<int, String> _answers = {};
  bool _submitting = false;
  bool _showSectionBanner = false;
  int _mathSecs = 30 * 60;
  int _engSecs = 40 * 60;
  Timer? _timerTimer;
  DateTime? _testStartedAt;

  late final AnimationController _fadeCtrl;
  final ScrollController _scrollCtrl = ScrollController();
  final ScrollController _dotsScrollCtrl = ScrollController();
  static const double _dotItemWidth = 34.0; // 30 dot + 4 separator

  // Auto-advance timer for option selection
  Timer? _autoAdv;

  int get _mathCount => widget.questions.where((q) => q.isMath).length;
  int get _engCount => widget.questions.length - _mathCount;
  Question get _q => widget.questions[_current];
  int get _total => widget.questions.length;
  bool get _isLast => _current == _total - 1;
  bool get _isFirst => _current == 0;
  bool get _isMath => _q.isMath;

  // Section-relative question number (01/20 format)
  int get _sectionIdx => _isMath ? _current : _current - _mathCount;
  int get _sectionTotal => _isMath ? _mathCount : _engCount;

  int get _activeSecs => _isMath ? _mathSecs : _engSecs;

  String get _timerDisplay {
    final s = _activeSecs;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  bool get _timerHot => _activeSecs < 120;

  @override
  void initState() {
    super.initState();
    _testStartedAt = DateTime.now();
    _startTimer();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _timerTimer?.cancel();
    _autoAdv?.cancel();
    _fadeCtrl.dispose();
    _scrollCtrl.dispose();
    _dotsScrollCtrl.dispose();
    super.dispose();
  }

  void _scrollDotsTo(int idx) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_dotsScrollCtrl.hasClients) return;
      final viewport = _dotsScrollCtrl.position.viewportDimension;
      final target = (idx * _dotItemWidth - viewport / 2 + _dotItemWidth / 2)
          .clamp(0.0, _dotsScrollCtrl.position.maxScrollExtent);
      _dotsScrollCtrl.animateTo(target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut);
    });
  }

  void _startTimer() {
    _timerTimer?.cancel();
    _timerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_isMath) {
          if (_mathSecs > 0) {
            _mathSecs--;
          } else {
            if (_engCount > 0 && _engSecs > 0) {
              _navigate(_mathCount);
            } else {
              _timerTimer?.cancel();
              _finish(force: true);
            }
          }
        } else {
          if (_engSecs > 0) {
            _engSecs--;
          } else {
            if (_mathCount > 0 && _mathSecs > 0) {
              _navigate(0);
            } else {
              _timerTimer?.cancel();
              _finish(force: true);
            }
          }
        }
      });
    });
  }

  void _navigate(int idx) {
    if (idx < 0 || idx >= _total) return;
    
    final targetIsMath = idx < _mathCount;
    if (targetIsMath && _mathSecs <= 0) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.mathSectionTimeUp)));
      return;
    }
    if (!targetIsMath && _engSecs <= 0) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.engSectionTimeUp)));
      return;
    }

    _autoAdv?.cancel();
    
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0);
    }

    // Switch to English section
    final wasInMath = _current < _mathCount;
    final nowInEng = idx >= _mathCount;
    final switchToEng = wasInMath && nowInEng;

    _fadeCtrl.forward(from: 0);
    setState(() {
      _current = idx;
      _showSectionBanner = switchToEng;
    });
    _scrollDotsTo(idx);

    if (switchToEng) {
      // Hide banner after 3s
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showSectionBanner = false);
      });
    }
  }

  void _answer(String choice) {
    if (_answers[_current] == choice) return;
    setState(() => _answers[_current] = choice);

    if (!_isLast) {
      _autoAdv?.cancel();
      _autoAdv = Timer(const Duration(milliseconds: 720), () {
        if (mounted) _navigate(_current + 1);
      });
    }
  }

  bool _dialogOpen = false;

  Future<void> _finish({bool force = false}) async {
    if (_submitting) return;
    _timerTimer?.cancel();
    final unanswered = _total - _answers.length;
    if (unanswered > 0 && !force) {
      _dialogOpen = true;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(AppLocalizations.of(context)!.finishConfirmTitle,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(
              AppLocalizations.of(context)!.unansweredWarning(unanswered)),
          actions: [
            TextButton(
                onPressed: () {
                  _startTimer();
                  Navigator.pop(context, false);
                },
                child: Text(AppLocalizations.of(context)!.backButton)),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size(100, 40)),
              child: Text(AppLocalizations.of(context)!.finishTest),
            ),
          ],
        ),
      );
      _dialogOpen = false;
      if (ok != true) return;
    } else if (_dialogOpen) {
      Navigator.pop(context);
      _dialogOpen = false;
    }

    setState(() => _submitting = true);
    final answersMap = <String, String>{};
    for (int i = 0; i < widget.questions.length; i++) {
      if (_answers.containsKey(i)) {
        answersMap[widget.questions[i].id] = _answers[i]!;
      }
    }
    final result = TestResult(
      packageId: widget.package.id,
      variant: widget.session.variant!,
      mathScore: 0, // Server hisoblaydi
      engScore: 0,
      totalPct: 0,
      answers: answersMap,
      deviceId: 'flutter-${defaultTargetPlatform.name}',
      durationSeconds: _testStartedAt != null
          ? DateTime.now().difference(_testStartedAt!).inSeconds
          : null,
    );
    final resp = await api.submitResultFull(result);
    final synced = resp['synced'] as bool? ?? false;
    final xpEarned = resp['xp_earned'] as int? ?? 0;
    final rawWrong = resp['wrong_answers'] as List<dynamic>? ?? [];
    
    TestResult finalResult = result;
    if (synced && resp.containsKey('math_score')) {
      finalResult = TestResult(
        packageId: result.packageId,
        variant: result.variant,
        mathScore: resp['math_score'] as int? ?? 0,
        engScore: resp['eng_score'] as int? ?? 0,
        totalPct: resp['total_pct'] as int? ?? 0,
        answers: answersMap,
        deviceId: 'flutter-${defaultTargetPlatform.name}',
        durationSeconds: _testStartedAt != null
            ? DateTime.now().difference(_testStartedAt!).inSeconds
            : null,
      );
    }

    final permanent = resp['permanent'] as bool? ?? false;
    if (!synced && !permanent) await OfflineQueue.enqueue(result);
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => ResultScreen(
                session: widget.session,
                package: widget.package,
                result: finalResult,
                synced: synced,
                xpEarned: xpEarned,
                wrongAnswers: rawWrong)));
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
              _navigate(_current - 1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _navigate(_current + 1),
        },
        child: Focus(
          autofocus: true,
          child: Column(children: [
            // ── Top progress bar (4px) ──────────────────────────────
            SizedBox(
              height: 4,
              child: Stack(children: [
                Container(
                    width: double.infinity,
                    height: 4,
                    decoration: const BoxDecoration(color: AppColors.border)),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  width: MediaQuery.sizeOf(context).width * progress,
                  height: 4,
                  decoration: BoxDecoration(
                    color: progress == 1 ? AppColors.ok : AppColors.brand,
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(3)),
                  ),
                ),
              ]),
            ),

            // ── Top bar ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
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
                Image.asset('assets/logo.png', width: 32, height: 32),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Text(widget.session.studentName,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink1)),
                        const SizedBox(width: 8),
                        _GradePill(grade: widget.session.grade!),
                      ]),
                      const SizedBox(height: 2),
                      Text(
                          _isMath
                              ? AppLocalizations.of(context)!.mathSectionLabel
                              : AppLocalizations.of(context)!.engSectionLabel,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.ink3,
                              fontWeight: FontWeight.w500)),
                    ])),
                _SubjectPill(isMath: _isMath),
                const SizedBox(width: 14),
                _TimerWidget(display: _timerDisplay, isHot: _timerHot),
              ]),
            ),

            // ── Body (scroll + fixed nav) ────────────────────────────
            Expanded(
                child: Center(
                    child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                        child: SingleChildScrollView(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Question dots
                            SizedBox(
                              height: 42,
                              child: ListView.separated(
                                controller: _dotsScrollCtrl,
                                scrollDirection: Axis.horizontal,
                                itemCount: _total,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 4),
                                itemBuilder: (_, i) => _QDot(
                                  number: i + 1,
                                  isCurrent: i == _current,
                                  isAnswered: _answers.containsKey(i),
                                  isMath: i < _mathCount,
                                  onTap: () => _navigate(i),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Section banner
                            if (_showSectionBanner)
                              _SectionBanner(
                                  onDismiss: () => setState(
                                      () => _showSectionBanner = false)),

                            // AnimatedSwitcher: only question+options animate on navigation
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 140),
                              switchInCurve: Curves.easeOut,
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                          begin: const Offset(.015, 0),
                                          end: Offset.zero)
                                      .animate(anim),
                                  child: child,
                                ),
                              ),
                              child: Column(
                                key: ValueKey(_current),
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
                                      ],
                                    ),
                                    child: Stack(children: [
                                      // Left accent strip via Positioned (avoids Row stretch/infinite height)
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 250),
                                          width: 4,
                                          decoration: BoxDecoration(
                                            color: _isMath
                                                ? AppColors.math
                                                : AppColors.eng,
                                          ),
                                        ),
                                      ),
                                      // Content padding
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            22, 20, 20, 18),
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
                                                            20),
                                                  ),
                                                  child: Text(
                                                    '${(_sectionIdx + 1).toString().padLeft(2, '0')} / ${_sectionTotal.toString().padLeft(2, '0')}',
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 11,
                                                        letterSpacing: .5),
                                                  ),
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
                                                          ? AppLocalizations.of(context)!.mathSubjectFull
                                                          : AppLocalizations.of(context)!.englishSubjectFull,
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppColors.ink2,
                                                          fontWeight:
                                                              FontWeight.w600)),
                                                ),
                                                const Spacer(),
                                                Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      for (final k in [
                                                        'A',
                                                        'B',
                                                        'C',
                                                        'D'
                                                      ]) ...[
                                                        _KbdKey(label: k),
                                                        if (k != 'D')
                                                          const SizedBox(
                                                              width: 3),
                                                      ],
                                                      const SizedBox(width: 5),
                                                      Text(AppLocalizations.of(context)!.keyboardButtons,
                                                          style: const TextStyle(
                                                              fontSize: 10,
                                                              color: AppColors
                                                                  .ink3)),
                                                    ]),
                                              ]),
                                              const SizedBox(height: 16),
                                              Text(_q.prompt,
                                                  style: const TextStyle(
                                                      fontSize: 21,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: AppColors.ink1,
                                                      height: 1.4)),
                                              // Question image (if any)
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
                                    final ch = ['a', 'b', 'c', 'd'][i];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _OptionRow(
                                        label: ['A', 'B', 'C', 'D'][i],
                                        text: i < _q.options.length
                                            ? _q.options[i]
                                            : '',
                                        optionImage:
                                            (_q.optionImages.length > i)
                                                ? _q.optionImages[i]
                                                : null,
                                        selected: _answers[_current] == ch,
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

                    // Fixed nav bar
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
                        ],
                      ),
                      child: Row(children: [
                        AnimatedOpacity(
                          opacity: _isFirst ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: SizedBox(
                            width: 110,
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: _isFirst
                                  ? null
                                  : () => _navigate(_current - 1),
                              icon: const Icon(Icons.arrow_back_rounded,
                                  size: 15),
                              label: Text(AppLocalizations.of(context)!.previousButton,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.ink2,
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
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
                              Text(AppLocalizations.of(context)!.answeredLabel,
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.ink3)),
                            ])),
                        SizedBox(
                          width: 110,
                          height: 44,
                          child: _isLast
                              ? ElevatedButton.icon(
                                  onPressed: _submitting ? null : _finish,
                                  icon: _submitting
                                      ? const SizedBox(
                                          width: 13,
                                          height: 13,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : const Icon(Icons.check_rounded,
                                          size: 15),
                                  label: Text(
                                      _submitting ? AppLocalizations.of(context)!.uploadTest : AppLocalizations.of(context)!.finishTest,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.ok,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () => _navigate(_current + 1),
                                  icon: Text(AppLocalizations.of(context)!.nextButton,
                                      style: const TextStyle(
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
                                            BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
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
    );
  }
}

// ── Reusable Widgets ─────────────────────────────────────────────────────────

class _GradePill extends StatelessWidget {
  final int grade;
  const _GradePill({required this.grade});
  @override
  Widget build(BuildContext context) {
    final colors = {
      1: (
        AppColors.secondaryMuted,
        const Color(0xFF9A3412),
        AppColors.amberBorder
      ),
      2: (
        AppColors.tealMuted,
        AppColors.tealInk,
        const Color(0xFF99F6E4)
      ),
      3: (
        AppColors.blueMuted,
        AppColors.blueInk,
        AppColors.blueBorder
      ),
      4: (
        AppColors.violetMuted,
        AppColors.violetInk,
        AppColors.violetBorder
      ),
    };
    final c = colors[grade] ?? colors[1]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.$1,
        border: Border.all(color: c.$3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$grade-sinf',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: c.$2)),
    );
  }
}

class _SubjectPill extends StatelessWidget {
  final bool isMath;
  const _SubjectPill({required this.isMath});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: isMath ? AppColors.blueMuted : AppColors.tealMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(isMath ? AppLocalizations.of(context)!.mathSubjectFull : AppLocalizations.of(context)!.englishSubjectFull,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isMath ? AppColors.blueInk : AppColors.tealInk,
            )),
      );
}

class _TimerWidget extends StatelessWidget {
  final String display;
  final bool isHot;
  const _TimerWidget({required this.display, required this.isHot});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isHot ? AppColors.errorMuted : AppColors.secondaryMuted,
          border: Border.all(
              color: isHot ? AppColors.dangerBorder : AppColors.amberBorder,
              width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isHot ? AppColors.error : AppColors.amberInk,
            ),
            child: Text(display),
          ),
          const SizedBox(height: 2),
          Text(AppLocalizations.of(context)!.timeLeftLabel,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .09,
                  color: isHot ? AppColors.error : AppColors.brand)),
        ]),
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
            ? AppColors.correctBorder
            : AppColors.chipBorder;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 30,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Circle dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: isCurrent ? 30 : 26,
            height: isCurrent ? 30 : 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCurrent
                  ? AppColors.brand
                  : isAnswered
                      ? AppColors.successMuted
                      : AppColors.surface,
              border: Border.all(color: accent, width: isCurrent ? 2 : 1.5),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                          color: AppColors.brand.withValues(alpha: .3),
                          blurRadius: 8,
                          spreadRadius: 1)
                    ]
                  : null,
            ),
            child: Center(
                child: Text(number.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: isCurrent ? 10 : 9,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrainsMono',
                      color: isCurrent
                          ? Colors.white
                          : isAnswered
                              ? AppColors.correctInk
                              : AppColors.chipIcon,
                    ))),
          ),
          // Current indicator — animated underline
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            height: 3,
            width: isCurrent ? 18 : 0,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SectionBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _SectionBanner({required this.onDismiss});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        decoration: BoxDecoration(
          gradient:
              const LinearGradient(colors: [AppColors.secondaryMuted, Colors.white]),
          border: Border.all(color: AppColors.amberBorder, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const Icon(Icons.language_rounded, color: AppColors.brand, size: 26),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(AppLocalizations.of(context)!.engSectionTransitionTitle,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.amberInk)),
                const SizedBox(height: 2),
                Text(AppLocalizations.of(context)!.engSectionTransitionDesc,
                    style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
              ])),
          IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded,
                  size: 18, color: AppColors.ink3)),
        ]),
      );
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
          color: widget.selected ? AppColors.secondaryMuted : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.selected ? AppColors.brand : AppColors.chipBorderMuted,
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? AppColors.brand
                      : AppColors.chipBg,
                  border: Border.all(
                      color: widget.selected
                          ? AppColors.brand
                          : AppColors.chipBorder,
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
                                : AppColors.chipIcon))),
              ),
              const SizedBox(width: 14),
              // Option text
              Expanded(
                  child: widget.optionImage != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                              if (widget.text.isNotEmpty) ...[
                                  Text(widget.text,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: widget.selected
                                              ? AppColors.amberInk
                                              : AppColors.ink1)),
                                const SizedBox(height: 6),
                              ],
                              Center(
                                child: AppNetworkImage(
                                  url: widget.optionImage,
                                  height: 80,
                                  fit: BoxFit.contain,
                                  showZoom: true,
                                  borderRadius: BorderRadius.circular(8),
                                  errorWidget: const Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.ink3,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ])
                      : Text(widget.text,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: widget.selected
                                  ? AppColors.amberInk
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 270),
            child: AppNetworkImage(
              url: url,
              alignment: Alignment.center,
              fit: BoxFit.contain,
              showZoom: true,
              borderRadius: BorderRadius.circular(10),
              placeholder: SizedBox(
                width: 120,
                height: 120,
                child: Center(
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
                  Text(AppLocalizations.of(context)!.imageLoadFailed,
                      style: const TextStyle(fontSize: 11, color: AppColors.ink3)),
                ])),
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _KbdKey extends StatelessWidget {
  final String label;
  const _KbdKey({required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.chipBorder),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.ink3)),
      );
}
