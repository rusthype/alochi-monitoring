// lib/features/diagnostic/screens/diagnostic_finished_screen.dart
//
// Animated thank-you screen — the results endpoint is staff-only, so no
// scores are shown here. Auto-returns to the kiosk root after 15s.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/utils/student_name_formatter.dart';
import '../../../shared/theme/app_theme.dart';
import '../widgets/celebration_particles.dart';
import '../widgets/sync_status_badge.dart';

const _kAutoReturnSeconds = 15;

class DiagnosticFinishedScreen extends StatefulWidget {
  const DiagnosticFinishedScreen({
    super.key,
    this.studentName,
    this.subjectsCompleted = const [],
  });

  final String? studentName;
  final List<String> subjectsCompleted;

  @override
  State<DiagnosticFinishedScreen> createState() =>
      _DiagnosticFinishedScreenState();
}

class _DiagnosticFinishedScreenState extends State<DiagnosticFinishedScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _particlesController;
  late final AnimationController _pulseController;
  Timer? _autoReturnTimer;
  int _secondsLeft = _kAutoReturnSeconds;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _autoReturnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        if (mounted) context.go('/');
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _autoReturnTimer?.cancel();
    _entranceController.dispose();
    _particlesController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _returnNow() {
    _autoReturnTimer?.cancel();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final entrance = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeOutBack,
      ),
    );
    final fadeIn = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutBack,
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CelebrationParticles(animation: _particlesController),
              ),
            ),
            const Positioned(top: 12, right: 12, child: SyncStatusBadge()),
            Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ScaleTransition(
                    scale: entrance,
                    child: FadeTransition(
                      opacity: fadeIn,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              final scale =
                                  1.0 + (_pulseController.value * 0.06);
                              return Transform.scale(
                                  scale: scale, child: child);
                            },
                            child: SizedBox(
                              width: 104,
                              height: 104,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 96,
                                    height: 96,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(28),
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          AppColors.gold,
                                          AppColors.amber
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.amber
                                              .withValues(alpha: 0.35),
                                          blurRadius: 24,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.emoji_events_rounded,
                                      color: Colors.white,
                                      size: 52,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: -4,
                                    right: -4,
                                    child: Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: AppColors.success,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 2.5),
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const _SequentialStars(),
                          const SizedBox(height: 24),
                          Text(
                            (widget.studentName != null &&
                                    widget.studentName!.trim().isNotEmpty)
                                ? l10n.diagnosticFinishedGreeting(
                                    formatStudentDisplayName(
                                        widget.studentName!))
                                : l10n.diagnosticFinishedTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.diagnosticFinishedSubtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 15, color: AppColors.ink2),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _StatusPill(
                                icon: Icons.check_circle_rounded,
                                label: l10n.diagnosticFinishedSubmittedPill,
                                color: AppColors.success,
                              ),
                              if (widget.subjectsCompleted.isNotEmpty)
                                _StatusPill(
                                  icon: Icons.menu_book_rounded,
                                  label: l10n.diagnosticFinishedSubjectsPill(
                                      widget.subjectsCompleted.length),
                                  color: AppColors.blue,
                                ),
                              _StatusPill(
                                icon: Icons.lock_rounded,
                                label: l10n.diagnosticFinishedSecurePill,
                                color: AppColors.violet,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.blueMuted,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.blueBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.shield_rounded,
                                  color: AppColors.blueInk,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    l10n.diagnosticFinishedInfoNote,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.blueInk,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _returnNow,
                              child: Text(l10n.backToKioskBtn),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.autoReturnTimerText(_secondsLeft),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.ink3),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () =>
                                setState(() => _isPaused = !_isPaused),
                            child: Text(_isPaused
                                ? l10n.diagnosticFinishedResumeBtn
                                : l10n.diagnosticFinishedPauseBtn),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SequentialStars extends StatefulWidget {
  const _SequentialStars();

  @override
  State<_SequentialStars> createState() => _SequentialStarsState();
}

class _SequentialStarsState extends State<_SequentialStars> {
  final List<bool> _lit = [false, false, false];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: 400 + i * 400), () {
        if (!mounted) return;
        setState(() => _lit[i] = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final lit = _lit[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedScale(
            scale: lit ? 1.0 : 0.8,
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            child: Icon(
              lit ? Icons.star_rounded : Icons.star_outline_rounded,
              size: i == 1 ? 30 : 24,
              color: lit ? AppColors.gold : AppColors.ink3,
            ),
          ),
        );
      }),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
