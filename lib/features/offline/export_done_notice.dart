// lib/features/offline/export_done_notice.dart
//
// Success notice shown in the offline dialog after an export / USB copy:
// headline, exported file name(s), the folder (middle-ellipsized) and two
// actions — reveal in the file manager, copy the path.
import 'dart:async';
import 'dart:io';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_colors.dart';

/// Keeps both ends of [s] (path tail + head stay recognisable).
String middleEllipsis(String s, {int max = 48}) {
  if (s.length <= max) return s;
  final head = (max - 1) ~/ 2;
  final tail = max - 1 - head;
  return '${s.substring(0, head)}…${s.substring(s.length - tail)}';
}

/// Opens the platform file manager on [file]. Never throws.
Future<void> revealInFolder(String file) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', file]);
    } else if (Platform.isWindows) {
      // explorer exits non-zero even on success; the result is ignored.
      await Process.run('explorer', ['/select,$file']);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [p.dirname(file)]);
    }
  } catch (e) {
    debugPrint('revealInFolder failed: ${e.runtimeType}');
  }
}

class ExportDoneNotice extends StatefulWidget {
  const ExportDoneNotice(
      {super.key, required this.headline, required this.files});

  final String headline;

  /// Full paths of the exported files (non-empty).
  final List<String> files;

  @override
  State<ExportDoneNotice> createState() => _ExportDoneNoticeState();
}

class _ExportDoneNoticeState extends State<ExportDoneNotice> {
  Timer? _timer;
  bool _copied = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.files.join('\n')));
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const color = AppColors.success;
    final folder = p.dirname(widget.files.last);
    final canReveal =
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
            File(widget.files.last).existsSync();
    const mono = TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: ['Consolas', 'monospace'],
      fontSize: 12,
      height: 1.4,
      color: AppColors.ink1,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.successMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle_outline, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(widget.headline,
                  style: const TextStyle(
                      color: color, fontWeight: FontWeight.w700, height: 1.35)),
            ),
          ]),
          const SizedBox(height: 8),
          for (final f in widget.files)
            SelectableText(p.basename(f), style: mono),
          const SizedBox(height: 4),
          Tooltip(
            message: folder,
            child: Text(middleEllipsis(folder),
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: const TextStyle(color: AppColors.ink2, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (canReveal)
              TextButton.icon(
                onPressed: () => revealInFolder(widget.files.last),
                icon: const Icon(Icons.folder_open, size: 16),
                label: Text(l10n.usbRevealInFolder),
              ),
            TextButton.icon(
              onPressed: _copy,
              icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
              label: Text(_copied ? l10n.usbPathCopied : l10n.usbCopyPath),
            ),
          ]),
        ],
      ),
    );
  }
}
