// lib/features/diagnostic/widgets/diagnostic_scratchpad.dart
//
// Full-screen scratchpad overlay: lets a student sketch working-out for a
// math question (column arithmetic etc.) without leaving the question. Pure
// UI-only freehand drawing — nothing is saved or submitted anywhere.
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';

/// Height the runner's floating bottom nav dock occupies from the bottom
/// edge (20 margin + 12*2 padding + 44 button = 88, plus breathing room).
/// Shared by the runner's content padding and the scratchpad so the dialog
/// never overlaps the dock.
const double kDiagnosticBottomNavReserve = 110;

/// Largest width the dialog grows to on big displays.
const double kDiagnosticScratchpadMaxWidth = 1400;

class DiagnosticScratchpad extends StatefulWidget {
  final VoidCallback onClose;

  /// Space at the bottom of the host the dialog must stay clear of.
  final double bottomReserve;

  const DiagnosticScratchpad({
    super.key,
    required this.onClose,
    this.bottomReserve = kDiagnosticBottomNavReserve,
  });

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
    return LayoutBuilder(builder: (context, box) {
      // Fit the space the host actually gives us (minus the bottom dock),
      // not fixed clamps: grows on big windows, shrinks on small ones.
      final availH = (box.maxHeight - widget.bottomReserve).clamp(0.0, 1e5);
      final maxWidth = (box.maxWidth * 0.94)
          .clamp(0.0, kDiagnosticScratchpadMaxWidth)
          .toDouble();
      return Container(
        color: Colors.black.withValues(alpha: 0.55),
        padding: EdgeInsets.only(bottom: widget.bottomReserve),
        alignment: Alignment.center,
        child: ConstrainedBox(
          key: const Key('diagnosticScratchpadDialog'),
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: availH),
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
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
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
                          border:
                              Border.all(color: AppColors.border, width: 1.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: GestureDetector(
                          key: const Key('diagnosticScratchpadCanvas'),
                          onPanStart: (details) {
                            setState(
                                () => _strokes.add([details.localPosition]));
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
    });
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
