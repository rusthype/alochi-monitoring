// lib/features/result/celebration_screen.dart
// v2 — animated score ring, section progress bars, share/copy button, dark+light mode
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../shared/theme/app_theme.dart';

class CelebrationScreen extends StatefulWidget {
  final int pct;
  final int vocabCor, vocabTot, engCor, engTot, mathCor, mathTot;
  final String studentName;
  final VoidCallback? onContinue;
  final VoidCallback? onRetry;

  const CelebrationScreen({
    super.key,
    required this.pct,
    required this.vocabCor, required this.vocabTot,
    required this.engCor,   required this.engTot,
    required this.mathCor,  required this.mathTot,
    required this.studentName,
    required this.onContinue,
    required this.onRetry,
  });

  @override
  State<CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen> with TickerProviderStateMixin {
  late final AnimationController _confettiCtrl;
  late final AnimationController _cardCtrl;
  late final AnimationController _scoreCtrl;
  late final List<_Particle> _particles;
  final _rng = math.Random();

  String get _title => widget.pct >= 90 ? 'BARAKALLA!'
      : widget.pct >= 70 ? 'YAXSHI ISHING!'
      : widget.pct >= 50 ? 'DAVOM ETING!'
      : 'HARAKAT QILING!';

  Color get _accent => widget.pct >= 90 ? const Color(0xFF16a34a)
      : widget.pct >= 70 ? const Color(0xFF0284c7)
      : widget.pct >= 50 ? const Color(0xFFf59e0b)
      : const Color(0xFFdc2626);

  IconData get _icon => widget.pct >= 90 ? Icons.emoji_events_rounded
      : widget.pct >= 70 ? Icons.star_rounded
      : widget.pct >= 50 ? Icons.thumb_up_rounded
      : Icons.menu_book_rounded;

  int _vpct(int c, int t) => t > 0 ? (c * 100 ~/ t) : 0;

  @override
  void initState() {
    super.initState();
    _particles = List.generate(220, (_) => _Particle(_rng));
    _confettiCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 5500))..forward();
    _cardCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scoreCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    Future.delayed(const Duration(milliseconds: 250), () { if (mounted) _cardCtrl.forward(); });
    Future.delayed(const Duration(milliseconds: 600),  () { if (mounted) _scoreCtrl.forward(); });
  }

  @override
  void dispose() {
    _confettiCtrl.dispose(); _cardCtrl.dispose(); _scoreCtrl.dispose();
    super.dispose();
  }

  void _share() {
    final txt =
        '${widget.studentName} monitoring testidan ${widget.pct}% natija!\n'
        'Vocab: ${widget.vocabCor}/${widget.vocabTot}  '
        'Ingliz: ${widget.engCor}/${widget.engTot}  '
        'Matematika: ${widget.mathCor}/${widget.mathTot}\n'
        'Alochi Monitoring tizimi — alochi.org';
    Clipboard.setData(ClipboardData(text: txt));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Natija nusxalandi'),
      backgroundColor: _accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeNotifier>().isDark;
    final bg   = isDark ? const Color(0xFF0f172a) : const Color(0xFFF1F5F9);
    final card = isDark ? const Color(0xFF1e293b) : Colors.white;
    final bord = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final sub  = isDark ? const Color(0xFF94a3b8) : const Color(0xFF64748b);
    final ac   = _accent;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(children: [
        AnimatedBuilder(
          animation: _confettiCtrl,
          builder: (_, __) => CustomPaint(
            size: MediaQuery.sizeOf(context),
            painter: _ConfettiPainter(_particles, _confettiCtrl.value),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: AnimatedBuilder(
                animation: _cardCtrl,
                builder: (_, child) => Opacity(
                  opacity: _cardCtrl.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 28 * (1 - _cardCtrl.value)), child: child),
                ),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: card, borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: bord),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(isDark ? .35 : .08),
                      blurRadius: 32, offset: const Offset(0, 8))],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [

                    // Icon badge
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ac.withOpacity(.12),
                        border: Border.all(color: ac.withOpacity(.3), width: 2),
                      ),
                      child: Icon(_icon, color: ac, size: 36),
                    ),
                    const SizedBox(height: 14),

                    Text(_title, style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w900,
                      color: ac, letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    Text(widget.studentName, style: TextStyle(
                      color: sub, fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 22),

                    // Animated score ring
                    Stack(alignment: Alignment.center, children: [
                      SizedBox(width: 130, height: 130,
                        child: AnimatedBuilder(
                          animation: _scoreCtrl,
                          builder: (_, __) => CustomPaint(
                            painter: _ScoreRingPainter(
                              progress: _scoreCtrl.value * widget.pct / 100,
                              color: ac, bg: bord),
                          ),
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedBuilder(
                          animation: _scoreCtrl,
                          builder: (_, __) => Text(
                            '${(_scoreCtrl.value * widget.pct).round()}%',
                            style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: ac)),
                        ),
                        Text('JAMI', style: TextStyle(
                          fontSize: 10, color: sub,
                          fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                      ]),
                    ]),
                    const SizedBox(height: 22),

                    // Section progress bars
                    _SectionRow(label: 'Vocab', icon: Icons.image_outlined,
                      correct: widget.vocabCor, total: widget.vocabTot,
                      color: const Color(0xFFf59e0b), isDark: isDark),
                    _SectionRow(label: 'Ingliz tili', icon: Icons.translate_rounded,
                      correct: widget.engCor, total: widget.engTot,
                      color: const Color(0xFF0284c7), isDark: isDark),
                    _SectionRow(label: 'Matematika', icon: Icons.calculate_outlined,
                      correct: widget.mathCor, total: widget.mathTot,
                      color: const Color(0xFF7c3aed), isDark: isDark),
                    const SizedBox(height: 22),

                    // Share
                    SizedBox(width: double.infinity, height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _share,
                        icon: Icon(Icons.copy_rounded, size: 16, color: sub),
                        label: Text('Natijani nusxalash', style: TextStyle(
                          fontSize: 13, color: sub, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: bord),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Continue
                    SizedBox(width: double.infinity, height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (widget.onContinue != null) widget.onContinue!();
                          else Navigator.of(context).popUntil((r) => r.isFirst);
                        },
                        icon: const Icon(Icons.bar_chart_rounded, size: 18),
                        label: const Text('Batafsil natijalar',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ac, foregroundColor: Colors.white, elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Retry
                    SizedBox(width: double.infinity, height: 44,
                      child: TextButton.icon(
                        onPressed: widget.onRetry ?? () => Navigator.of(context).popUntil((r) => r.isFirst),
                        icon: Icon(Icons.refresh_rounded, size: 16, color: sub),
                        label: Text('Qayta urinish', style: TextStyle(
                          fontSize: 13, color: sub, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SectionRow extends StatelessWidget {
  final String label; final IconData icon;
  final int correct, total; final Color color; final bool isDark;
  const _SectionRow({required this.label, required this.icon,
    required this.correct, required this.total,
    required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? correct / total : 0.0;
    final bg = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(width: 32, height: 32,
          decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFcbd5e1) : const Color(0xFF475569))),
            Text('$correct/$total', style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: pct, minHeight: 6,
              backgroundColor: bg,
              valueColor: AlwaysStoppedAnimation<Color>(color))),
        ])),
      ]),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  final double progress; final Color color, bg;
  const _ScoreRingPainter({required this.progress, required this.color, required this.bg});
  @override void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - 12) / 2;
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round;
    p.color = bg; canvas.drawCircle(c, r, p);
    p.color = color;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
      -math.pi / 2, 2 * math.pi * progress, false, p);
  }
  @override bool shouldRepaint(_ScoreRingPainter old) => progress != old.progress;
}

class _Particle {
  double x, y, vx, vy, rot, vrot, alpha, w, h; Color color; int shape;
  static const _cols = [Color(0xFFf59e0b), Color(0xFF0284c7), Color(0xFF7c3aed),
    Color(0xFFec4899), Color(0xFF16a34a), Color(0xFFef4444), Color(0xFF06b6d4)];
  _Particle(math.Random r)
      : x = r.nextDouble(), y = r.nextDouble() * .5 - .3,
        vx = (r.nextDouble() - .5) * .008, vy = r.nextDouble() * .006 + .003,
        rot = r.nextDouble() * 360, vrot = (r.nextDouble() - .5) * 6,
        alpha = 1.0, w = r.nextDouble() * 12 + 4, h = r.nextDouble() * 5 + 2,
        color = _cols[r.nextInt(_cols.length)], shape = r.nextInt(3);
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles; final double t;
  _ConfettiPainter(this.particles, this.t);
  @override void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      if (p.alpha <= 0) continue;
      final paint = Paint()..color = p.color.withOpacity(p.alpha.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(p.x * size.width, (p.y + t * p.vy * 200) * size.height);
      canvas.rotate((p.rot + t * p.vrot * 50) * math.pi / 180);
      if (p.shape == 0) canvas.drawCircle(Offset.zero, p.w / 2, paint);
      else canvas.drawRect(Rect.fromCenter(center: Offset.zero,
        width: p.w, height: p.shape == 1 ? p.w : p.h), paint);
      canvas.restore();
    }
  }
  @override bool shouldRepaint(_ConfettiPainter old) => t != old.t;
}
