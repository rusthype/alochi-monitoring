// lib/features/diagnostic/widgets/celebration_particles.dart
//
// Isolated, score-agnostic confetti/particle animation for the diagnostic
// "finished" screen. Deliberately separate from result_screen.dart's
// private _ConfettiPainter (that file is off-limits) — static green/blue
// palette only, no score/percentage input of any kind.
import 'dart:math';
import 'package:flutter/material.dart';

class CelebrationParticles extends StatefulWidget {
  const CelebrationParticles({super.key, required this.animation});

  /// 0.0 -> 1.0 looping progress, driven by the parent's AnimationController.
  final Animation<double> animation;

  static const List<Color> _palette = [
    Color(0xFF0F9A6E), // success green
    Color(0xFF3B82F6), // blue
    Color(0xFF10B981), // emerald
    Color(0xFF0EA5E9), // math blue
  ];

  @override
  State<CelebrationParticles> createState() => _CelebrationParticlesState();
}

class _CelebrationParticlesState extends State<CelebrationParticles> {
  late final List<_Particle> _particles = List.generate(
    24,
    (i) => _Particle(Random()),
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, _) => CustomPaint(
        painter: _ParticlesPainter(
          progress: widget.animation.value,
          particles: _particles,
          palette: CelebrationParticles._palette,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _Particle {
  _Particle(Random rng)
      : dx = rng.nextDouble(),
        startY = rng.nextDouble() * 0.3,
        speed = 0.4 + rng.nextDouble() * 0.6,
        size = 4 + rng.nextDouble() * 5,
        colorIndex = rng.nextInt(4),
        phase = rng.nextDouble();

  final double dx;
  final double startY;
  final double speed;
  final double size;
  final int colorIndex;
  final double phase;
}

class _ParticlesPainter extends CustomPainter {
  _ParticlesPainter({
    required this.progress,
    required this.particles,
    required this.palette,
  });

  final double progress;
  final List<_Particle> particles;
  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      final t = (progress * p.speed + p.phase) % 1.0;
      final y = p.startY * size.height + t * size.height;
      if (y > size.height) continue;
      final x = p.dx * size.width;
      final opacity = (1.0 - t).clamp(0.0, 1.0);
      paint.color = palette[p.colorIndex].withValues(alpha: opacity * 0.6);
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
