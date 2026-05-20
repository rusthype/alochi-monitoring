// lib/shared/widgets/particle_canvas.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Interaktiv particle dots background.
/// Mouse/cursor yaqinlashganda dotlar tortiladi,
/// yaqin dotlar orasida chiziqlar paydo bo'ladi.
class ParticleCanvas extends StatefulWidget {
  final Widget child;
  final bool darkMode;
  const ParticleCanvas({super.key, required this.child, this.darkMode = false});

  @override
  State<ParticleCanvas> createState() => _ParticleCanvasState();
}

class _Particle {
  double x, y, vx, vy, r;
  final double hue;    // 10-25 (orange) yoki 220-270 (blue/purple)
  final double baseA;  // base opacity

  _Particle({
    required this.x, required this.y,
    required this.vx, required this.vy,
    required this.r, required this.hue, required this.baseA,
  });
}

class _ParticleCanvasState extends State<ParticleCanvas>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  final List<_Particle> _dots = [];
  Offset _mouse = const Offset(-9999, -9999);
  Size _size = Size.zero;
  final _rng = math.Random();
  bool _initialized = false;

  // Burst particles (click effect)
  final List<_BurstParticle> _bursts = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _initDots(Size size) {
    if (_initialized) return;
    _initialized = true;
    _size = size;
    for (int i = 0; i < 160; i++) {
      final hue = _rng.nextBool()
          ? 10.0 + _rng.nextDouble() * 20  // orange
          : 220.0 + _rng.nextDouble() * 60; // blue/purple
      _dots.add(_Particle(
        x: _rng.nextDouble() * size.width,
        y: _rng.nextDouble() * size.height,
        vx: (_rng.nextDouble() - 0.5) * 0.55,
        vy: (_rng.nextDouble() - 0.5) * 0.55,
        r: _rng.nextDouble() * 2.5 + 0.8,
        hue: hue,
        baseA: _rng.nextDouble() * 0.45 + 0.15,
      ));
    }
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    final size = _size;
    if (size == Size.zero) return;

    for (final p in _dots) {
      p.x += p.vx;
      p.y += p.vy;
      if (p.x < 0 || p.x > size.width) p.vx *= -1;
      if (p.y < 0 || p.y > size.height) p.vy *= -1;

      // Mouse attraction
      final dx = _mouse.dx - p.x;
      final dy = _mouse.dy - p.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 230 && dist > 0) {
        final force = (230 - dist) / 230 * 0.055;
        p.vx += dx / dist * force;
        p.vy += dy / dist * force;
      }

      // Speed limit
      final spd = math.sqrt(p.vx * p.vx + p.vy * p.vy);
      if (spd > 3.0) {
        p.vx *= 0.93;
        p.vy *= 0.93;
      }
    }

    // Burst update
    _bursts.removeWhere((b) {
      b.x += b.vx;
      b.y += b.vy;
      b.vy += 0.11;
      b.vx *= 0.97;
      b.life -= b.decay;
      return b.life <= 0;
    });

    setState(() {});
  }

  void _addBurst(Offset pos) {
    for (int i = 0; i < 22; i++) {
      final angle = _rng.nextDouble() * math.pi * 2;
      final speed = _rng.nextDouble() * 7 + 2;
      _bursts.add(_BurstParticle(
        x: pos.dx, y: pos.dy,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        r: _rng.nextDouble() * 4 + 1.5,
        life: 1.0,
        decay: _rng.nextDouble() * 0.028 + 0.018,
        hue: _rng.nextBool() ? 20.0 : 270.0,
      ));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (size != _size && size != Size.zero) {
        if (!_initialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _initDots(size));
        } else {
          _size = size;
        }
      }
      return MouseRegion(
        onHover: (e) => setState(() => _mouse = e.localPosition),
        onExit: (_) => setState(() => _mouse = const Offset(-9999, -9999)),
        child: GestureDetector(
          onTapDown: (d) => _addBurst(d.localPosition),
          behavior: HitTestBehavior.translucent,
          child: Stack(children: [
            // Particle layer
            CustomPaint(
              size: size,
              painter: _DotsPainter(
                dots: _dots,
                bursts: _bursts,
                mouse: _mouse,
                darkMode: widget.darkMode,
                size: size,
              ),
            ),
            // Content
            widget.child,
          ]),
        ),
      );
    });
  }
}

class _BurstParticle {
  double x, y, vx, vy, r, life, decay, hue;
  _BurstParticle({
    required this.x, required this.y, required this.vx, required this.vy,
    required this.r, required this.life, required this.decay, required this.hue,
  });
}

class _DotsPainter extends CustomPainter {
  final List<_Particle> dots;
  final List<_BurstParticle> bursts;
  final Offset mouse;
  final bool darkMode;
  final Size size;

  const _DotsPainter({
    required this.dots, required this.bursts, required this.mouse,
    required this.darkMode, required this.size,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Mouse glow
    if (mouse.dx > -100) {
      final glowPaint = Paint()
        ..shader = RadialGradient(colors: [
          Color.fromRGBO(249, 115, 22, darkMode ? 0.09 : 0.13),
          const Color.fromRGBO(249, 115, 22, 0),
        ]).createShader(Rect.fromCircle(center: mouse, radius: 200));
      canvas.drawCircle(mouse, 200, glowPaint);
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < dots.length; i++) {
      final p = dots[i];
      final dx = mouse.dx - p.x;
      final dy = mouse.dy - p.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      final glow = dist < 230 ? (230 - dist) / 230 : 0.0;

      final sat = darkMode ? 75.0 : 88.0;
      final lit = darkMode ? 62.0 : 43.0;
      final alpha = ((darkMode ? p.baseA : p.baseA * 1.5) + glow * 0.55)
          .clamp(0.0, 1.0);
      final radius = p.r * (1 + glow * 0.8);

      dotPaint.color = HSLColor.fromAHSL(alpha, p.hue, sat / 100, lit / 100)
          .toColor();
      canvas.drawCircle(Offset(p.x, p.y), radius, dotPaint);

      // Connection lines near mouse
      if (glow > 0.18) {
        final linePaint = Paint()..strokeWidth = darkMode ? 0.6 : 0.9;
        for (int j = i + 1; j < dots.length; j++) {
          final q = dots[j];
          final qd = math.sqrt((q.x - p.x) * (q.x - p.x) +
              (q.y - p.y) * (q.y - p.y));
          if (qd < 95) {
            final lineA = (1 - qd / 95) * glow * (darkMode ? 0.35 : 0.55);
            linePaint.color =
                Color.fromRGBO(249, 115, 22, lineA.clamp(0.0, 1.0));
            canvas.drawLine(Offset(p.x, p.y), Offset(q.x, q.y), linePaint);
          }
        }
      }
    }

    // Burst particles
    for (final b in bursts) {
      dotPaint.color = HSLColor.fromAHSL(
        (b.life * 0.85).clamp(0.0, 1.0), b.hue, 0.85, 0.60,
      ).toColor();
      canvas.drawCircle(Offset(b.x, b.y), b.r * b.life, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => true;
}
