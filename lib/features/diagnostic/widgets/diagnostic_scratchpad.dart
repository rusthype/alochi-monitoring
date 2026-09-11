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
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
        child: Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '✏️ ${l10n.diagnosticScratchpadButton}',
                      style: const TextStyle(
                        color: AppColors.ink1,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, color: AppColors.ink2),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: AppColors.pageBg,
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
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _strokes.isEmpty ? null : _undo,
                        child: Text(l10n.diagnosticScratchpadUndo),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _strokes.isEmpty ? null : _clear,
                        child: Text(l10n.clearSelectionBtn),
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
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final stroke in strokes) {
      for (var i = 0; i < stroke.length - 1; i++) {
        canvas.drawLine(stroke[i], stroke[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScratchPainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
