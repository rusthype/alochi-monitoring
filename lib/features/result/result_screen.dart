// lib/features/result/result_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/models/models.dart';
import '../../shared/theme/app_theme.dart';
import '../auth/login_screen.dart';

class ResultScreen extends StatelessWidget {
  final StudentSession session;
  final TestPackage package;
  final TestResult result;
  final bool synced;
  const ResultScreen({super.key, required this.session, required this.package, required this.result, required this.synced});

  @override
  Widget build(BuildContext context) {
    final passed = result.passed;
    final color  = passed ? AppColors.ok : AppColors.err;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              // Score ring
              _ScoreRing(pct: result.totalPct, color: color),
              const SizedBox(height: 20),
              // Verdict
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(24)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(passed ? Icons.check_circle_outline : Icons.cancel_outlined, color: color, size: 18),
                  const SizedBox(width: 8),
                  Text(passed ? "O'tdingiz!" : "O'tmadi",
                      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
              ),
              const SizedBox(height: 16),
              Text(session.studentName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text('${session.grade}-sinf · Variant ${session.variant}',
                  style: const TextStyle(color: AppColors.ink2, fontSize: 13)),
              const SizedBox(height: 20),
              // Score cards
              Row(children: [
                Expanded(child: _ScoreCard(label: 'Matematika', score: result.mathScore, total: package.mathCount, color: AppColors.math)),
                const SizedBox(width: 12),
                Expanded(child: _ScoreCard(label: 'Ingliz tili', score: result.engScore, total: package.engCount, color: AppColors.eng)),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  const Icon(Icons.bar_chart, color: AppColors.ink2),
                  const SizedBox(width: 12),
                  const Text('Jami ball', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${result.mathScore + result.engScore} / ${package.totalCount}',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
                ]),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: (synced ? AppColors.ok : AppColors.ink3).withOpacity(.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: (synced ? AppColors.ok : AppColors.border).withOpacity(.4)),
                ),
                child: Row(children: [
                  Icon(synced ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                      size: 16, color: synced ? AppColors.ok : AppColors.ink3),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    synced ? 'Natija serverga yuborildi' : "Offline saqlandi. Internet bo'lganda yuboriladi",
                    style: TextStyle(fontSize: 12, color: synced ? AppColors.ok : AppColors.ink2),
                  )),
                ]),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushAndRemoveUntil(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false),
                icon: const Icon(Icons.logout),
                label: const Text("Chiqish — Keyingi talaba"),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final int pct;
  final Color color;
  const _ScoreRing({required this.pct, required this.color});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(130, 130),
    painter: _RingPainter(pct / 100, color),
    child: SizedBox(width: 130, height: 130,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('$pct%', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
        const Text('BALL', style: TextStyle(fontSize: 10, color: AppColors.ink2, letterSpacing: 2)),
      ]),
    ),
  );
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter(this.progress, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 8;
    canvas.drawCircle(c, r, Paint()..color = AppColors.border..style = PaintingStyle.stroke..strokeWidth = 10);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi / 2, 2 * pi * progress, false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 10..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(_) => true;
}

class _ScoreCard extends StatelessWidget {
  final String label;
  final int score, total;
  final Color color;
  const _ScoreCard({required this.label, required this.score, required this.total, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('$score', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
      Text('$score / $total', style: const TextStyle(fontSize: 12, color: AppColors.ink2)),
      const SizedBox(height: 8),
      ClipRRect(borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: total > 0 ? score / total : 0,
              backgroundColor: color.withOpacity(.1), color: color, minHeight: 4)),
    ]),
  );
}
