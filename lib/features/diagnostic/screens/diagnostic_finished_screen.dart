// lib/features/diagnostic/screens/diagnostic_finished_screen.dart
//
// Animated thank-you screen — the results endpoint is staff-only, so no
// scores are shown here. Auto-returns to the kiosk root after 15s.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import '../widgets/celebration_particles.dart';

const _kAutoReturnSeconds = 15;

class DiagnosticFinishedScreen extends StatefulWidget {
  const DiagnosticFinishedScreen({super.key});

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
    final entrance = CurvedAnimation(
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
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ScaleTransition(
                  scale: entrance,
                  child: FadeTransition(
                    opacity: entrance,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final scale = 1.0 + (_pulseController.value * 0.08);
                            return Transform.scale(scale: scale, child: child);
                          },
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: const BoxDecoration(
                              color: AppColors.successMuted,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.verified_rounded,
                              color: AppColors.success,
                              size: 48,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          l10n.diagnosticFinishedTitle,
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
                          style:
                              const TextStyle(fontSize: 15, color: AppColors.ink2),
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
                          style:
                              const TextStyle(fontSize: 12, color: AppColors.ink3),
                        ),
                      ],
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
