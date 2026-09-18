// lib/features/diagnostic/widgets/diagnostic_scratchpad.dart
//
// Full-screen scratchpad overlay: lets a student sketch working-out for a
// math question (column arithmetic etc.) without leaving the question. Pure
// UI-only freehand drawing — nothing is saved or submitted anywhere.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

class DiagnosticScratchpad extends StatefulWidget {
  final VoidCallback onClose;

  const DiagnosticScratchpad({super.key, required this.onClose});

  @override
  State<DiagnosticScratchpad> createState() => _DiagnosticScratchpadState();
}

class _DiagnosticScratchpadState extends State<DiagnosticScratchpad> {
  final List<List<Offset>> _strokes = [];

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() => setState(() => _strokes.clear());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final screen = MediaQuery.sizeOf(context);
    // Scale with the available window instead of a fixed 500x400 — on the
    // kiosk's large desktop displays a small fixed box looked cramped and
    // left most of the dimmed backdrop unused.
    final maxWidth = (screen.width * 0.92).clamp(320.0, 1100.0);
    final maxHeight = (screen.height * 0.88).clamp(360.0, 820.0);
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: const BoxDecoration(
                  color: AppColors.secondaryMuted,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text('✏️', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 10),
                        Text(
                          l10n.diagnosticScratchpadButton,
                          style: const TextStyle(
                            color: AppColors.ink1,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        shape: const CircleBorder(),
                      ),
                      icon: const Icon(Icons.close, color: AppColors.ink2),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.pageBg,
                        border: Border.all(color: AppColors.border, width: 1.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: GestureDetector(
                        key: const Key('diagnosticScratchpadCanvas'),
                        onPanStart: (details) {
                          setState(() => _strokes.add([details.localPosition]));
                        },
                        onPanUpdate: (details) {
                          setState(
                              () => _strokes.last.add(details.localPosition));
                        },
                        child: CustomPaint(
                          painter: _ScratchPainter(_strokes),
                          size: Size.infinite,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _strokes.isEmpty ? null : _undo,
                        icon: const Icon(Icons.undo_rounded),
                        label: Text(l10n.diagnosticScratchpadUndo),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _strokes.isEmpty ? null : _clear,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(l10n.clearSelectionBtn),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScratchPainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _ScratchPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink1
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScratchPainter oldDelegate) {
    // `strokes` is the same mutable List instance across every paint (the
    // State field is appended-to in place, never reassigned) — comparing it
    // by identity (`!=`) is always false after the first paint, so drawn
    // strokes silently stopped rendering and Clear didn't visually clear.
    // A cheap freehand canvas has no real perf concern here, so just always
    // repaint.
    return true;
  }
}
