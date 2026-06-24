// lib/features/result/result_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_network_image.dart';
import '../../core/sync/sync_service.dart';
import '../auth/login_screen.dart';
import 'pdf_report.dart';

class ResultScreen extends StatefulWidget {
  final StudentSession session;
  final TestPackage package;
  final TestResult result;
  final bool synced;
  final int xpEarned;
  final List<dynamic> wrongAnswers;
  const ResultScreen(
      {super.key,
      required this.session,
      required this.package,
      required this.result,
      required this.synced,
      this.xpEarned = 0,
      this.wrongAnswers = const []});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  // Celebration overlay
  late final AnimationController _celebCtrl;
  late final AnimationController _overlayFadeCtrl;
  bool _showOverlay = true;
  int _displayedPct = 0;
  bool _pdfGenerating = false;
  String? _pdfPath;

  // Result card
  late final AnimationController _cardCtrl;
  late final Animation<double> _ring;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;

  // Confetti particles
  final _rng = math.Random();
  late final List<_Particle> _particles;

  bool get _passed => widget.result.passed;
  int get _pct => widget.result.totalPct;

  @override
  void initState() {
    super.initState();
    _particles = List.generate(80, (_) => _Particle(_rng));

    // Celebration overlay: 3.4s
    _celebCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3400))
      ..forward();

    // Overlay fade out
    _overlayFadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));

    // Score counter animation starts at 600ms
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _animateScore();
    });

    // Dismiss overlay after 3.4s
    Future.delayed(const Duration(milliseconds: 3400), () {
      if (!mounted) return;
      _overlayFadeCtrl.forward().then((_) {
        if (mounted) setState(() => _showOverlay = false);
      });
    });

    // Result card animations
    _cardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _ring = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic);
    _cardFade = CurvedAnimation(
        parent: _cardCtrl, curve: const Interval(.3, 1, curve: Curves.easeOut));
    _cardSlide = Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _cardCtrl,
            curve: const Interval(.3, 1, curve: Curves.easeOut)));

    // Start card animation after overlay fades
    Future.delayed(const Duration(milliseconds: 3800), () {
      if (mounted) _cardCtrl.forward();
    });

    SyncService.instance.flushNow();
  }

  void _animateScore() {
    const stepMs = 28;
    final steps = (_pct / math.max(1, (_pct / 50).ceil())).ceil();
    int current = 0;
    void tick(Timer t) {
      current = math.min(current + steps.ceil(), _pct);
      if (mounted) setState(() => _displayedPct = current);
      if (current >= _pct) t.cancel();
    }

    // ignore: unused_local_variable
    final timer = Timer.periodic(const Duration(milliseconds: stepMs), tick);
  }

  Future<void> _generatePdf() async {
    setState(() => _pdfGenerating = true);
    try {
      final file = await PdfReport.generate(
        session: widget.session,
        package: widget.package,
        result: widget.result,
        wrongAnswers: widget.wrongAnswers,
      );
      if (!mounted) return;
      setState(() => _pdfPath = file.path);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PDF xatosi: $e'),
        backgroundColor: AppColors.err,
      ));
    } finally {
      if (mounted) setState(() => _pdfGenerating = false);
    }
  }

  @override
  void dispose() {
    SyncService.instance.flushNow();
    _celebCtrl.dispose();
    _overlayFadeCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // ── Result card (behind overlay) ──────────────────────────
        _buildResultCard(),

        // ── Celebration overlay ───────────────────────────────────
        if (_showOverlay)
          FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0).animate(_overlayFadeCtrl),
            child: _buildCelebrationOverlay(),
          ),
      ]),
    );
  }

  Widget _buildCelebrationOverlay() {
    final name = widget.session.studentName.split(' ').take(2).join(' ');
    return Container(
      color: const Color(0xFF0F0F23),
      child: Stack(children: [
        // Falling confetti
        AnimatedBuilder(
          animation: _celebCtrl,
          builder: (_, __) => CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(_particles, _celebCtrl.value),
          ),
        ),
        // Center content
        Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Trophy
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, __) => Transform.scale(
              scale: v,
              child: const Icon(Icons.emoji_events_rounded,
                  size: 80, color: Colors.amber),
            ),
          ),
          const SizedBox(height: 16),
          // Title
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (_, v, __) => Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, 30 * (1 - v)),
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFFFBBF24),
                      Color(0xFFF97316),
                      Color(0xFFFB923C)
                    ],
                  ).createShader(bounds),
                  blendMode: BlendMode.srcIn,
                  child: Text(
                    _passed ? "Tabriklaymiz!" : "Yaxshi harakat!",
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Score
          Text(
            '$_displayedPct%',
            style: const TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFamily: 'JetBrainsMono',
              shadows: [Shadow(color: Color(0xFFF97316), blurRadius: 30)],
            ),
          ),
          const SizedBox(height: 8),
          Text(name,
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: .7),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text(
            _passed
                ? "Test muvaffaqiyatli yakunlandi"
                : "Keyingi safarida yaxshiroq bo'ladi!",
            style: TextStyle(
                fontSize: 13, color: Colors.white.withValues(alpha: .45)),
          ),
          const SizedBox(height: 20),
          // XP + coins earned
          if (widget.xpEarned > 0) ...[
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, __) => Transform.scale(
                  scale: v,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: Colors.white.withValues(alpha: .2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('⭐', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text('+${widget.xpEarned} XP',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ]),
                  ),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 8),

          // Animated dots
          Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (i) => TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.2, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  curve: Interval(i * 0.2, 1.0, curve: Curves.easeInOut),
                  builder: (_, v, __) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(Colors.white.withValues(alpha: .2),
                          AppColors.brand, v),
                    ),
                  ),
                ),
              )),
        ])),
      ]),
    );
  }

  Widget _buildResultCard() {
    final mainColor = _passed ? AppColors.ok : AppColors.brand;
    final bgColor = _passed ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bgColor, AppColors.bg],
        ),
      ),
      child: Center(
          child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: FadeTransition(
            opacity: _cardFade,
            child: SlideTransition(
              position: _cardSlide,
              child: Column(children: [
                // ── Brand logo ─────────────────────────────────
                Container(
                  width: 56,
                  height: 56,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: .08),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: ClipOval(
                      child:
                          Image.asset('assets/logo.png', fit: BoxFit.contain)),
                ),
                const SizedBox(height: 16),
                // ── Score ring ──────────────────────────────────
                AnimatedBuilder(
                  animation: _ring,
                  builder: (_, __) => CustomPaint(
                    size: const Size(150, 150),
                    painter: _RingPainter(
                      progress: (_pct / 100) * _ring.value,
                      color: mainColor,
                      bgColor: mainColor.withValues(alpha: .1),
                    ),
                    child: SizedBox(
                      width: 150,
                      height: 150,
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$_pct%',
                                style: TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800,
                                  color: mainColor,
                                  fontFamily: 'JetBrainsMono',
                                )),
                            Text('ball',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: mainColor.withValues(alpha: .7),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .09,
                                )),
                          ]),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Verdict badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: mainColor,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        _passed
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        size: 16,
                        color: Colors.white),
                    const SizedBox(width: 7),
                    Text(
                        _passed
                            ? "Tabriklaymiz! O'tdingiz!"
                            : "O'tmadi. Harakat qiling!",
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(widget.session.studentName,
                    style: AppTextStyles.titleLarge),
                const SizedBox(height: 4),
                Text(
                    '${widget.session.grade ?? '-'}-sinf · Variant ${widget.session.variant ?? '-'}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.ink3,
                        fontFamily: 'JetBrainsMono')),
                const SizedBox(height: 24),
                // Subject cards
                Row(children: [
                  Expanded(
                      child: _SubjectCard(
                    label: 'Matematika',
                    icon: Icons.calculate_outlined,
                    score: widget.result.mathScore,
                    total: widget.package.mathCount,
                    color: const Color(0xFF3B82F6),
                    ring: _ring,
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _SubjectCard(
                    label: 'Ingliz tili',
                    icon: Icons.language_rounded,
                    score: widget.result.engScore,
                    total: widget.package.engCount,
                    color: const Color(0xFF0D9488),
                    ring: _ring,
                  )),
                ]),
                const SizedBox(height: 12),
                // Total
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    const Icon(Icons.equalizer_rounded,
                        size: 18, color: AppColors.ink2),
                    const SizedBox(width: 8),
                    Text('Jami ball',
                        style: AppTextStyles.labelLarge
                            .copyWith(color: AppColors.ink2)),
                    const Spacer(),
                    Text(
                        '${widget.result.mathScore + widget.result.engScore} / ${widget.package.totalCount}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink1,
                            fontFamily: 'JetBrainsMono')),
                  ]),
                ),
                const SizedBox(height: 12),
                // Sync
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: (widget.synced ? AppColors.ok : AppColors.ink3)
                        .withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: (widget.synced ? AppColors.ok : AppColors.border)
                            .withValues(alpha: .4)),
                  ),
                  child: Row(children: [
                    Icon(
                        widget.synced
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined,
                        size: 15,
                        color: widget.synced ? AppColors.ok : AppColors.ink3),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                      widget.synced
                          ? 'Natija serverga muvaffaqiyatli yuborildi'
                          : "Offline saqlandi. Internet bo'lganda avtomatik yuboriladi",
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: widget.synced ? AppColors.ok : AppColors.ink2),
                    )),
                  ]),
                ),
                const SizedBox(height: 24),
                // Wrong answers section
                if (widget.wrongAnswers.isNotEmpty) ...[
                  _WrongAnswersSection(wrongAnswers: widget.wrongAnswers),
                  const SizedBox(height: 24),
                ],
                // Subject analysis
                _SubjectAnalysis(
                  result: widget.result,
                  package: widget.package,
                ),
                const SizedBox(height: 12),

                // Buttons row
                Row(children: [
                  // PDF button
                  Expanded(
                      child: SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _pdfGenerating ? null : _generatePdf,
                      icon: _pdfGenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text(
                          _pdfPath != null ? 'PDF tayyor' : 'PDF yuklab olish',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brand,
                        side: BorderSide(
                            color: AppColors.brand.withValues(alpha: .5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13)),
                      ),
                    ),
                  )),
                  const SizedBox(width: 10),
                  // Next student button
                  Expanded(
                      child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                          (_) => false),
                      icon: const Icon(Icons.person_outline_rounded, size: 18),
                      label: const Text("Keyingi talaba"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13)),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  )),
                ]),
              ]),
            ),
          ),
        ),
      )),
    );
  }
}

// ── Subject card widget ───────────────────────────────────────────────────────
class _SubjectCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final int score, total;
  final Color color;
  final Animation<double> ring;
  const _SubjectCard(
      {required this.label,
      required this.icon,
      required this.score,
      required this.total,
      required this.color,
      required this.ring});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink3)),
          ]),
          const SizedBox(height: 8),
          Text('$score',
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink1,
                  fontFamily: 'JetBrainsMono')),
          Text('/ $total',
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.ink3,
                  fontFamily: 'JetBrainsMono')),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: AnimatedBuilder(
              animation: ring,
              builder: (_, __) => LinearProgressIndicator(
                value: total > 0 ? (score / total) * ring.value : 0,
                minHeight: 5,
                backgroundColor: color.withValues(alpha: .1),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ]),
      );
}

// ── Ring painter ─────────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color, bgColor;
  const _RingPainter(
      {required this.progress, required this.color, required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r = math.min(cx, cy) - 9;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;

    paint.color = bgColor;
    canvas.drawCircle(Offset(cx, cy), r, paint);

    paint.color = color;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ── Confetti particle system ──────────────────────────────────────────────────
class _Particle {
  late double x, y, vx, vy, rot, vrot, size, opacity;
  late Color color;
  late bool isRect;

  static const _colors = [
    Color(0xFFF97316),
    Color(0xFFFBBF24),
    Color(0xFF4ADE80),
    Color(0xFF60A5FA),
    Color(0xFFA78BFA),
    Color(0xFFF472B6),
    Color(0xFFFDE68A),
    Color(0xFF34D399),
  ];

  _Particle(math.Random rng) {
    _reset(rng, true);
  }

  void _reset(math.Random rng, bool init) {
    x = rng.nextDouble();
    y = init ? -rng.nextDouble() * 0.5 : -0.05;
    vx = (rng.nextDouble() - 0.5) * 0.008;
    vy = 0.003 + rng.nextDouble() * 0.008;
    rot = rng.nextDouble() * math.pi * 2;
    vrot = (rng.nextDouble() - 0.5) * 0.15;
    size = 4 + rng.nextDouble() * 8;
    opacity = 0.7 + rng.nextDouble() * 0.3;
    color = _colors[rng.nextInt(_colors.length)];
    isRect = rng.nextBool();
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;

  _ConfettiPainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      final px = (p.x + p.vx * t * 100) % 1.0;
      final py = p.y + p.vy * t * 100;
      if (py > 1.1) continue;

      final screenX = px * size.width;
      final screenY = py * size.height;
      final alpha =
          (p.opacity * (py < 0.8 ? 1.0 : (1.1 - py) / 0.3)).clamp(0.0, 1.0);

      paint.color = p.color.withValues(alpha: alpha);
      canvas.save();
      canvas.translate(screenX, screenY);
      canvas.rotate(p.rot + p.vrot * t * 60);

      if (p.isRect) {
        canvas.drawRect(
            Rect.fromCenter(
                center: Offset.zero, width: p.size, height: p.size * 0.4),
            paint);
      } else {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

// ── Wrong answers section ─────────────────────────────────────────────────
class _WrongAnswersSection extends StatefulWidget {
  final List<dynamic> wrongAnswers;
  const _WrongAnswersSection({required this.wrongAnswers});
  @override
  State<_WrongAnswersSection> createState() => _WrongAnswersSectionState();
}

class _WrongAnswersSectionState extends State<_WrongAnswersSection> {
  bool _expanded = false;

  static const _subjectLabel = {'math': 'Matematika', 'english': 'Ingliz tili'};
  static const _answerLabel = {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D'};

  @override
  Widget build(BuildContext context) {
    final math =
        widget.wrongAnswers.where((w) => w['subject'] == 'math').length;
    final eng =
        widget.wrongAnswers.where((w) => w['subject'] == 'english').length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.err.withValues(alpha: .25)),
      ),
      child: Column(children: [
        // Header
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.err.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close_rounded,
                    color: AppColors.err, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Xato javoblar — ${widget.wrongAnswers.length} ta',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink1)),
                    Text('Mat: $math  ·  Ing: $eng',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.ink3)),
                  ])),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.ink3, size: 20),
            ]),
          ),
        ),
        // List
        if (_expanded) ...[
          const Divider(height: 1, color: AppColors.border),
          ...widget.wrongAnswers.asMap().entries.map((e) {
            final w = e.value as Map<String, dynamic>;
            final pos = w['position'] as int? ?? 0;
            final subj = _subjectLabel[w['subject']] ?? w['subject'];
            final sAns =
                _answerLabel[w['student_answer']] ?? w['student_answer'];
            final cAns =
                _answerLabel[w['correct_answer']] ?? w['correct_answer'];
            final sText = w['student_text'] as String? ?? '';
            final cText = w['correct_text'] as String? ?? '';
            final imgUrl = w['image'] as String?;
            final isLast = e.key == widget.wrongAnswers.length - 1;

            return Container(
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : const Border(bottom: BorderSide(color: AppColors.border)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Position + subject
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text('$pos',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink2,
                                fontFamily: 'JetBrainsMono')),
                      ),
                      const SizedBox(width: 8),
                      Text(subj,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.ink3,
                              fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 6),
                    // Prompt
                    Text(w['prompt'] as String? ?? '',
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.ink1,
                            fontWeight: FontWeight.w600,
                            height: 1.3)),
                    if (imgUrl != null) ...[
                      const SizedBox(height: 8),
                      AppNetworkImage(
                        url: imgUrl,
                        height: 80,
                        fit: BoxFit.contain,
                        borderRadius: BorderRadius.circular(8),
                        errorWidget: const SizedBox.shrink(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Student answer (wrong)
                    _AnswerChip(label: sAns, text: sText, isCorrect: false),
                    const SizedBox(height: 4),
                    // Correct answer
                    _AnswerChip(label: cAns, text: cText, isCorrect: true),
                  ]),
            );
          }),
        ],
      ]),
    );
  }
}

class _AnswerChip extends StatelessWidget {
  final String label, text;
  final bool isCorrect;
  const _AnswerChip(
      {required this.label, required this.text, required this.isCorrect});

  @override
  Widget build(BuildContext context) {
    final color = isCorrect ? AppColors.ok : AppColors.err;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: .4)),
        ),
        child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: color))),
      ),
      const SizedBox(width: 8),
      Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12,
                  color: isCorrect ? AppColors.ok : AppColors.err,
                  fontWeight: isCorrect ? FontWeight.w600 : FontWeight.w500))),
      Icon(isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined,
          size: 14, color: color),
    ]);
  }
}

// ── Subject Analysis Widget ───────────────────────────────────────────────────
class _SubjectAnalysis extends StatelessWidget {
  final TestResult result;
  final TestPackage package;
  const _SubjectAnalysis({required this.result, required this.package});

  @override
  Widget build(BuildContext context) {
    final mathPct =
        package.mathCount > 0 ? result.mathScore / package.mathCount : 0.0;
    final engPct =
        package.engCount > 0 ? result.engScore / package.engCount : 0.0;

    String mathStatus, engStatus;
    Color mathColor, engColor;

    if (mathPct >= 0.8) {
      mathStatus = "Yaxshi ✓";
      mathColor = AppColors.ok;
    } else if (mathPct >= 0.6) {
      mathStatus = "O'rtacha";
      mathColor = const Color(0xFFF59E0B);
    } else {
      mathStatus = "Zaif — mashq kerak";
      mathColor = AppColors.err;
    }

    if (engPct >= 0.8) {
      engStatus = "Yaxshi ✓";
      engColor = AppColors.ok;
    } else if (engPct >= 0.6) {
      engStatus = "O'rtacha";
      engColor = const Color(0xFFF59E0B);
    } else {
      engStatus = "Zaif — mashq kerak";
      engColor = AppColors.err;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.insights_rounded, size: 16, color: AppColors.brand),
          SizedBox(width: 8),
          Text('Mavzu tahlili',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink1)),
        ]),
        const SizedBox(height: 14),
        _AnalysisRow(
          subject: 'Matematika',
          score: result.mathScore,
          total: package.mathCount,
          pct: mathPct,
          status: mathStatus,
          statusColor: mathColor,
          barColor: const Color(0xFF3B82F6),
        ),
        const SizedBox(height: 10),
        _AnalysisRow(
          subject: 'Ingliz tili',
          score: result.engScore,
          total: package.engCount,
          pct: engPct,
          status: engStatus,
          statusColor: engColor,
          barColor: const Color(0xFF0D9488),
        ),
      ]),
    );
  }
}

class _AnalysisRow extends StatelessWidget {
  final String subject, status;
  final int score, total;
  final double pct;
  final Color statusColor, barColor;

  const _AnalysisRow({
    required this.subject,
    required this.score,
    required this.total,
    required this.pct,
    required this.status,
    required this.statusColor,
    required this.barColor,
  });

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(subject,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink2)),
          const Spacer(),
          Text('$score/$total',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink1,
                  fontFamily: 'JetBrainsMono')),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor)),
          ),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: barColor.withValues(alpha: .1),
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
      ]);
}
