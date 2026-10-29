// lib/shared/widgets/proctor_toast.dart
//
// Transient proctor-notification toasts (admin warning / time added) shared
// by TestEngine and DiagnosticTestRunnerScreen: a [ProctorToastController]
// the screen owns (push + dispose), and a [ProctorToastStack] placed as a
// direct child of the screen's Stack that renders them top-right.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../theme/app_theme.dart';

enum ProctorToastKind { warning, extended }

/// Self-removes from [ProctorToastController.entries] via [timer] after its
/// display duration.
class ProctorToastEntry {
  final ProctorToastKind kind;
  final String message;
  Timer? timer;
  ProctorToastEntry(this.kind, this.message);
}

class ProctorToastController extends ChangeNotifier {
  final List<ProctorToastEntry> entries = [];
  bool _disposed = false;

  /// Adds a toast and schedules its own removal after [duration].
  void push(ProctorToastKind kind, String message, Duration duration) {
    if (_disposed) return;
    final entry = ProctorToastEntry(kind, message);
    entry.timer = Timer(duration, () {
      if (_disposed) return;
      entries.remove(entry);
      notifyListeners();
    });
    entries.add(entry);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in entries) {
      t.timer?.cancel();
    }
    super.dispose();
  }
}

/// Must be a direct child of a [Stack] (it returns a [Positioned]). Ignores
/// pointer events so it never blocks taps on the UI underneath.
class ProctorToastStack extends StatelessWidget {
  final ProctorToastController controller;
  final double top;

  const ProctorToastStack({super.key, required this.controller, this.top = 12});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: 12,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final e in controller.entries) _ProctorToastBanner(entry: e),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProctorToastBanner extends StatelessWidget {
  final ProctorToastEntry entry;
  const _ProctorToastBanner({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isWarning = entry.kind == ProctorToastKind.warning;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isWarning ? AppColors.secondaryMuted : AppColors.successMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWarning ? AppColors.amberBorder : AppColors.emerald,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          isWarning ? Icons.warning_amber_rounded : Icons.alarm_add_rounded,
          color: isWarning ? AppColors.amberDark : AppColors.success,
          size: 20,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            isWarning
                ? '${l10n.adminWarning}: ${entry.message}'
                : entry.message,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isWarning ? AppColors.amberInk : AppColors.emeraldInk,
            ),
          ),
        ),
      ]),
    );
  }
}
