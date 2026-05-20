// lib/features/result/celebration_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import 'monitoring_pdf.dart';

class CelebrationScreen extends StatefulWidget {
  final int pct;
  final int vocabCor;
  final int vocabTot;
  final int engCor;
  final int engTot;
  final int mathCor;
  final int mathTot;
  final String studentName;
  final String variant;
  final int grade;
  final String timeTaken;
  final VoidCallback? onContinue;
  final VoidCallback? onRetry;

  const CelebrationScreen({
    super.key,
    required this.pct,
    required this.vocabCor,
    required this.vocabTot,
    required this.engCor,
    required this.engTot,
    required this.mathCor,
    required this.mathTot,
    required this.studentName,
    this.variant = '',
    this.grade   = 1,
    this.timeTaken = '',
    required this.onContinue,
    required this.onRetry,
  });

  @override
  State<CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen>
    with TickerProviderStateMixin {
  late final AnimationController _confettiCtrl;
  late final AnimationController _cardCtrl;
  late final AnimationController _emojiCtrl;
  late final List<_Particle> _particles;
  final _rng = math.Random();
  bool _pdfLoading = false;
  int  _streakCount = 0; // ketma-ket to'g'ri javoblar (local_test_screen dan o'tkaziladi)

  Future<void> _downloadPdf() async {
    setState(() => _pdfLoading = true);
    try {
      await MonitoringPdf.shareOrSave(
        context:     context,
        studentName: widget.studentName,
        grade:       widget.grade,
        variant:     widget.variant,
        pct:         widget.pct,
        vocabCor:    widget.vocabCor, vocabTot: widget.vocabTot,
        engCor:      widget.engCor,   engTot:   widget.engTot,
        mathCor:     widget.mathCor,  mathTot:  widget.mathTot,
        timeTaken:   widget.timeTaken,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF xatoligi: $e'),
              backgroundColor: const Color(0xFFDC2626)));
      }
    } finally {
      if (mounted) setState(() => _pdfLoading = false);
    }
  }

  String get _msg => widget.pct >= 90
      ? 'BARAKALLA!'
      : widget.pct >= 70
          ? 'YAXSHI ISHING!'
          : widget.pct >= 50
              ? 'DAVOM ETING!'
              : 'HARAKAT QILING!';

  String get _emoji => widget.pct >= 90
      ? '🏆'
      : widget.pct >= 70
          ? '🌟'
          : widget.pct >= 50
              ? '💪'
              : '📚';

  Color get _accentColor => widget.pct >= 90
      ? const Color(0xFF16a34a)
      : widget.pct >= 70
          ? const Color(0xFF0284c7)
          : widget.pct >= 50
              ? const Color(0xFFf59e0b)
              : const Color(0xFFdc2626);

  int _vpct(int c, int t) => t > 0 ? (c * 100 ~/ t) : 0;

  @override
  void initState() {
    super.initState();
    _particles = List.generate(200, (_) => _Particle(_rng));

    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..forward();

    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _cardCtrl.forward();
    });

    _emojiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    _cardCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ac = _accentColor;

    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      body: Stack(children: [
        // ── Confetti canvas ──
        AnimatedBuilder(
          animation: _confettiCtrl,
          builder: (_, __) => CustomPaint(
            size: size,
            painter: _ConfettiPainter(_particles, _confettiCtrl.value),
          ),
        ),

        // ── Center card ──
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AnimatedBuilder(
                animation: _cardCtrl,
                builder: (_, child) => Opacity(
                  opacity: _cardCtrl.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 30 * (1 - _cardCtrl.value)),
                    child: child,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Emoji bounce
                    AnimatedBuilder(
                      animation: _emojiCtrl,
                      builder: (_, __) => Transform.scale(
                        scale: 1.0 + _emojiCtrl.value * 0.12,
                        child: Text(_emoji,
                            style: const TextStyle(fontSize: 72)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Title
                    Text(
                      _msg,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: ac,
                        letterSpacing: 1.5,
                        shadows: [
                          Shadow(color: ac.withValues(alpha: 0.5), blurRadius: 20),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.studentName,
                      style: const TextStyle(
                          color: Color(0xFF94a3b8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 20),

                    // Score circle
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1e293b),
                        border: Border.all(color: ac, width: 4.5),
                        boxShadow: [
                          BoxShadow(
                              color: ac.withValues(alpha: 0.35),
                              blurRadius: 30,
                              spreadRadius: 2)
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${widget.pct}%',
                              style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: ac)),
                          const Text('JAMI',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFF64748b),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 3 section pills
                    Row(children: [
                      _SectionPill(
                          label: 'VOCAB',
                          pct: _vpct(widget.vocabCor, widget.vocabTot),
                          score: '${widget.vocabCor}/${widget.vocabTot}',
                          color: const Color(0xFFf59e0b)),
                      const SizedBox(width: 8),
                      _SectionPill(
                          label: 'INGLIZ',
                          pct: _vpct(widget.engCor, widget.engTot),
                          score: '${widget.engCor}/${widget.engTot}',
                          color: const Color(0xFF0284c7)),
                      const SizedBox(width: 8),
                      _SectionPill(
                          label: 'MATEMATIKA',
                          pct: _vpct(widget.mathCor, widget.mathTot),
                          score: '${widget.mathCor}/${widget.mathTot}',
                          color: const Color(0xFF7c3aed)),
                    ]),
                    const SizedBox(height: 20),

                    // Continue button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          if (widget.onContinue != null) {
                            widget.onContinue!();
                          } else {
                            Navigator.of(context).popUntil((r) => r.isFirst);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ac,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Batafsil natijalar',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w800)),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Retry
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: widget.onRetry ?? () => Navigator.of(context).popUntil((r) => r.isFirst),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF334155)),
                          foregroundColor: const Color(0xFF94a3b8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh_rounded, size: 16),
                            SizedBox(width: 6),
                            Text('Qayta urinish',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // PDF yuklab olish
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: _pdfLoading ? null : _downloadPdf,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF7c3aed)),
                          foregroundColor: const Color(0xFF7c3aed),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _pdfLoading
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2,
                                  color: Color(0xFF7c3aed)))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.picture_as_pdf_rounded, size: 16),
                                SizedBox(width: 6),
                                Text('PDF yuklab olish',
                                    style: TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                      ),
                    ),
                ),
              ),
            ),
          ),
        ),
      ]),  // Stack children
      // NOTE: fixed
    );
  }
}

class _SectionPill extends StatelessWidget {
  final String label, score;
  final int pct;
  final Color color;
  const _SectionPill(
      {required this.label,
      required this.pct,
      required this.score,
      required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1e293b),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: color,
                      letterSpacing: .5)),
              const SizedBox(height: 3),
              Text('$pct%',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: color.withValues(alpha: .9))),
              Text(score,
                  style: const TextStyle(
                      fontSize: 9, color: Color(0xFF64748b))),
            ],
          ),
        ),
      );
}

// ── Confetti particle ──
class _Particle {
  double x, y, vx, vy, rot, vrot, alpha, w, h;
  Color color;
  int shape; // 0=circle 1=square 2=ribbon

  static const _colors = [
    Color(0xFFf59e0b), Color(0xFF0284c7), Color(0xFF7c3aed),
    Color(0xFFec4899), Color(0xFF16a34a), Color(0xFFef4444), Color(0xFF06b6d4),
  ];

  _Particle(math.Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble() * 0.5 - 0.3,
        vx = (rng.nextDouble() - 0.5) * 0.008,
        vy = rng.nextDouble() * 0.006 + 0.003,
        rot = rng.nextDouble() * 360,
        vrot = (rng.nextDouble() - 0.5) * 6,
        alpha = 1.0,
        w = rng.nextDouble() * 12 + 4,
        h = rng.nextDouble() * 5 + 2,
        color = _colors[rng.nextInt(_colors.length)],
        shape = rng.nextInt(3);

  void update(double dt, double screenH) {
    x += vx * dt;
    y += vy * dt;
    rot += vrot * dt;
    if (y > 1.0) alpha -= 0.05;
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  _ConfettiPainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.alpha <= 0) continue;
      final paint = Paint()
        ..color = p.color.withValues(alpha: p.alpha.clamp(0.0, 1.0));

      final cx = p.x * size.width;
      final cy = (p.y + t * (p.vy * 200)) * size.height;
      final rot = p.rot + t * p.vrot * 50;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rot * math.pi / 180);

      if (p.shape == 0) {
        canvas.drawCircle(Offset.zero, p.w / 2, paint);
      } else if (p.shape == 1) {
        canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: p.w, height: p.w),
            paint);
      } else {
        canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h),
            paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => t != old.t;
}
