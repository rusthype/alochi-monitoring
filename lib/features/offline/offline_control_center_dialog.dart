// lib/features/offline/offline_control_center_dialog.dart
//
// "Oflayn rejim" control center, opened from the login screen's permanent
// offline button. Jobs:
//   1. Load a `.alochipack` (file picker -> PIN -> roster picker).
//   2. Export stored results as `.alochires` (choose a folder, e.g. the USB).
//   3. Show what is stored / not yet exported, and leave offline mode.
//   4. LAN (phase 3): on the teacher PC start the hub for the open pack and
//      open the class monitor; on a student PC join a teacher's hub.
//
// When the public keys are not compiled in (OfflineKeys.isConfigured == false)
// everything is disabled behind a "not configured" notice — release builds
// never fall back to test keys.
import 'dart:async';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/db/pack_results_db.dart';
import '../../core/local_server/shelf_hub.dart';
import '../../core/offline/lan_client_session.dart';
import '../../core/offline/offline_keys.dart';
import '../../core/offline/offline_session.dart';
import '../../core/offline/pack_loader.dart';
import '../../core/offline/results_exporter.dart';
import '../../core/offline/usb_backup.dart';
import '../../shared/theme/app_theme.dart';
import 'lan_connect_dialog.dart';
import 'safe_file_picker.dart';

Future<void> showOfflineControlCenter(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const OfflineControlCenterDialog(),
  );
}

class OfflineControlCenterDialog extends StatefulWidget {
  const OfflineControlCenterDialog(
      {super.key, this.listDrives = listRemovableDrives});

  /// Injectable for tests (real Windows drive detection otherwise).
  final DriveLister listDrives;

  @override
  State<OfflineControlCenterDialog> createState() =>
      _OfflineControlCenterDialogState();
}

class _OfflineControlCenterDialogState
    extends State<OfflineControlCenterDialog> {
  bool _busy = false;
  String? _busyLabel;
  String? _message;
  bool _messageIsError = false;
  List<PackSummary> _summaries = const [];

  late final OfflineKeys _keys = OfflineKeys.current;
  late final bool _configured = _keys.isConfigured;

  @override
  void initState() {
    super.initState();
    // No pack open -> no decrypted images should be lying around.
    if (!OfflinePackSession.isActive && !LanClientSession.isActive) {
      unawaited(OfflinePackSession.cleanupMedia());
    }
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final s = await PackResultsDb.summaries();
      if (mounted) setState(() => _summaries = s);
    } catch (e) {
      debugPrint('OfflineControlCenter: summaries failed: $e');
    }
  }

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  String _packError(AppLocalizations l10n, PackException e) {
    switch (e.code) {
      case PackError.notConfigured:
        return l10n.usbNotConfigured;
      case PackError.badSignature:
        return l10n.usbErrBadSignature;
      case PackError.expired:
        return l10n.usbErrExpired;
      case PackError.hashMismatch:
        return l10n.usbErrHash;
      case PackError.wrongPin:
        return l10n.usbErrBadPin;
      case PackError.unsafeName:
        return l10n.usbErrUnsafeName;
      case PackError.badFormat:
        return l10n.usbErrFormat;
      case PackError.tooLarge:
        return l10n.usbErrTooLarge;
    }
  }

  // ── load a pack ────────────────────────────────────────────────────────────

  /// True from the first tap until the flow ends, so a double click on
  /// "open" (or on the PIN dialog's button) cannot start a second unlock/open.
  bool _loadingPack = false;

  Future<void> _loadPack({bool thenOpenHub = false}) async {
    if (_loadingPack || _busy) return;
    _loadingPack = true;
    try {
      await _loadPackInner(thenOpenHub: thenOpenHub);
    } finally {
      _loadingPack = false;
    }
  }

  Future<void> _loadPackInner({bool thenOpenHub = false}) async {
    final l10n = AppLocalizations.of(context)!;
    final path = await pickPackFile(title: l10n.usbPickPackTitle);
    // Cancel is a pure no-op: the open pack (OfflinePackSession.current) and
    // everything derived from it stay untouched.
    if (path == null) return;

    setState(() {
      _busy = true;
      _busyLabel = l10n.usbOpening;
      _message = null;
    });
    try {
      // Zip decode + RSA verify + per-file SHA-256 off the UI thread.
      final keys = _keys;
      final archive = await inspectPackFile(path, keys);
      if (!mounted) return;
      setState(() => _busy = false);

      final pin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _PinDialog(),
      );
      if (pin == null || !mounted) return;

      setState(() {
        _busy = true;
        _busyLabel = l10n.usbOpening;
      });
      final mediaDir =
          await OfflinePackSession.mediaDirFor(archive.manifest.packUuid);
      final pack =
          await PackLoader(keys: keys).unlock(archive, pin, mediaDir: mediaDir);
      final session = await OfflinePackSession.open(pack, mediaDir);
      await _refresh();
      if (!mounted) return;
      setState(() => _busy = false);
      if (thenOpenHub) {
        _openMonitor();
      } else {
        _startTests(session);
      }
    } on PackException catch (e) {
      debugPrint('OfflineControlCenter: pack rejected: ${e.code.name}');
      _say(_packError(l10n, e), error: true);
    } catch (e) {
      // Never log the PIN; the exception text does not contain it.
      debugPrint('OfflineControlCenter: load failed: $e');
      // Type name only: no PIN, no file content, no message text.
      _say('${l10n.usbErrRead} ${l10n.usbErrDiag(e.runtimeType.toString())}',
          error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startTests(OfflinePackSession session) =>
      _goToGroups(session.pack.schoolCode, session.pack.schoolId);

  /// Roster picker for the open pack (USB) or the joined hub (LAN).
  void _goToGroups(String schoolCode, String schoolId) {
    final router = GoRouter.of(context);
    final code = schoolCode.isEmpty ? '0' : schoolCode;
    final label = schoolCode.isEmpty
        ? ''
        : AppLocalizations.of(context)!.usbSchoolLabel(schoolCode);
    Navigator.of(context).pop();
    router.push('/group_select/$code', extra: {
      'schoolLabel': label,
      'schoolId': schoolId,
    });
  }

  // ── LAN (phase 3) ──────────────────────────────────────────────────────────

  /// Teacher PC: needs the unlocked pack (PIN) first, then the class monitor.
  Future<void> _startHub() async {
    if (OfflinePackSession.current == null) {
      await _loadPack(thenOpenHub: true);
    } else {
      _openMonitor();
    }
  }

  void _openMonitor() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push('/lan_hub');
  }

  /// Student PC: find the teacher's hub, enter the class code, then pick the
  /// student exactly as in USB mode.
  Future<void> _connectToHub() async {
    final session = await showLanConnectDialog(context);
    if (session == null || !mounted) {
      if (mounted) setState(() {});
      return;
    }
    _goToGroups(session.schoolCode, session.schoolId);
  }

  void _exitMode() {
    exitOfflineMode();
    setState(() {});
  }

  // ── export ─────────────────────────────────────────────────────────────────

  /// Exports [targets] (or, when null, every pack with at least one saved
  /// result, exported before or not) into `<Downloads>/alochi-offline`.
  Future<void> _export({List<PackSummary>? targets}) async {
    final l10n = AppLocalizations.of(context)!;
    final list = targets ?? _summaries.where((s) => s.total > 0).toList();
    if (list.isEmpty) {
      _say(l10n.usbExportNothing);
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = null;
      _message = null;
    });
    try {
      final dir = await defaultExportDir();
      final exporter = ResultsExporter(keys: _keys);
      var total = 0;
      var badKeys = 0;
      String lastFile = '';
      for (final s in list) {
        final out = await exporter.exportPack(s.packUuid, dir,
            schoolCode: s.schoolCode);
        total += out.count;
        badKeys += out.invalidKeyCount;
        lastFile = out.file.path;
      }
      await _refresh();
      _say(
          badKeys > 0
              ? l10n.usbExportBadKeys(badKeys)
              : l10n.usbExportDone(total, lastFile),
          error: badKeys > 0);
    } on ExportException catch (e) {
      _say(
          e.code == ExportError.notConfigured
              ? l10n.usbNotConfigured
              : l10n.usbExportNothing,
          error: e.code == ExportError.notConfigured);
    } catch (e) {
      debugPrint('OfflineControlCenter: export failed: $e');
      _say(l10n.usbExportFailed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fresh export of every pack with results, then copy onto a removable drive.
  Future<void> _copyToFlash() async {
    final l10n = AppLocalizations.of(context)!;
    final list = _summaries.where((s) => s.total > 0).toList();
    if (list.isEmpty) {
      _say(l10n.usbExportNothing);
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = null;
      _message = null;
    });
    try {
      final dir = await defaultExportDir();
      final exporter = ResultsExporter(keys: _keys);
      final r = await exportToFlash(
        exports: [
          for (final s in list)
            () async => (await exporter.exportPack(s.packUuid, dir,
                    schoolCode: s.schoolCode))
                .file,
        ],
        drives: widget.listDrives,
        pick: _pickDrive,
      );
      await _refresh();
      switch (r.status) {
        case FlashStatus.ok:
          _say(l10n.usbFlashDone(r.paths.join(', ')));
        case FlashStatus.noDrive:
          _say(l10n.usbFlashNone, error: true);
        case FlashStatus.cancelled:
          break;
        case FlashStatus.failed:
          // Keep what already reached the drive visible next to the failure.
          _say(
              r.paths.isEmpty
                  ? l10n.usbFlashFailed
                  : '${l10n.usbFlashDone(r.paths.join(', '))}\n${l10n.usbFlashFailed}',
              error: true);
      }
    } on ExportException catch (e) {
      _say(
          e.code == ExportError.notConfigured
              ? l10n.usbNotConfigured
              : l10n.usbExportNothing,
          error: e.code == ExportError.notConfigured);
    } catch (e) {
      debugPrint('OfflineControlCenter: flash copy failed: ${e.runtimeType}');
      _say(l10n.usbFlashFailed, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickDrive(List<String> drives) {
    if (!mounted) return Future.value(null);
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: Text(AppLocalizations.of(ctx)!.usbFlashPick),
        children: [
          for (final d in drives)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(d),
              child: Text(d),
            ),
        ],
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final session = OfflinePackSession.current;
    final totalUnexported =
        _summaries.fold<int>(0, (sum, s) => sum + s.unexported);
    final totalSaved = _summaries.fold<int>(0, (sum, s) => sum + s.total);

    return Dialog(
      backgroundColor: AppColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.usb_rounded, color: AppColors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l10n.usbCenterTitle,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink1)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(l10n.usbCenterIntro,
                    style: const TextStyle(color: AppColors.ink2, height: 1.4)),
                const SizedBox(height: 16),
                if (!_configured) _notice(l10n.usbNotConfigured, error: true),
                if (session != null) ...[
                  _notice(l10n.usbActivePack(
                      session.pack.schoolCode,
                      DateFormat('dd.MM.yyyy')
                          .format(session.pack.manifest.expiresAt.toLocal()))),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _startTests(session),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(l10n.usbStartTests),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _exitMode,
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(l10n.usbExitMode),
                  ),
                ] else
                  Text(l10n.usbNoPackOpen,
                      style: const TextStyle(color: AppColors.ink3)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed:
                      (_busy || !_configured || LanClientSession.isActive)
                          ? null
                          : _loadPack,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(l10n.usbLoadPack),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: (_busy || !_configured) ? null : () => _export(),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(l10n.usbExportResults),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: (_busy || !_configured || totalSaved == 0)
                      ? null
                      : _copyToFlash,
                  icon: const Icon(Icons.usb_rounded),
                  label: Text(l10n.usbFlashButton),
                ),
                const SizedBox(height: 16),
                ..._lanSection(l10n),
                if (_busy) ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    if (_busyLabel != null)
                      Text(_busyLabel!,
                          style: const TextStyle(color: AppColors.ink2)),
                  ]),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 14),
                  _notice(_message!, error: _messageIsError),
                ],
                const SizedBox(height: 20),
                Text(l10n.usbResultsHeader,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.ink1)),
                const SizedBox(height: 6),
                if (_summaries.isEmpty)
                  Text(l10n.usbNoResults,
                      style: const TextStyle(color: AppColors.ink3))
                else ...[
                  Text(
                      '${l10n.usbSavedCount(totalSaved)}  ·  '
                      '${l10n.usbUnexportedCount(totalUnexported)}',
                      style: const TextStyle(color: AppColors.ink2)),
                  const SizedBox(height: 8),
                  for (final s in _summaries) _packRow(l10n, s),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _lanSection(AppLocalizations l10n) {
    final lan = LanClientSession.current;
    final packOpen = OfflinePackSession.isActive;
    final hub = ShelfHub.current;
    final hubRunning = hub != null && hub.running && packOpen;
    return [
      const Divider(height: 1, color: AppColors.border),
      const SizedBox(height: 16),
      // Teacher PC: the hub.
      if (hubRunning && hub.port != null) ...[
        _notice(l10n.lanHubStatusRunning(hub.port!)),
        const SizedBox(height: 8),
      ],
      FilledButton.tonalIcon(
        onPressed: (_busy || !_configured || lan != null) ? null : _startHub,
        icon: const Icon(Icons.dns_rounded),
        label: Text(hubRunning ? l10n.lanHubOpenMonitor : l10n.lanHubButton),
      ),
      if (lan != null) ...[
        const SizedBox(height: 4),
        Text(l10n.lanDisconnectFirst,
            style: const TextStyle(color: AppColors.ink3, fontSize: 12)),
      ],
      const SizedBox(height: 8),
      // Student PC: join a teacher's hub.
      if (lan != null) ...[
        _notice(l10n.lanActiveHub(lan.hubName)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed:
              _busy ? null : () => _goToGroups(lan.schoolCode, lan.schoolId),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(l10n.usbStartTests),
        ),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: (_busy || packOpen) ? null : _connectToHub,
        icon: const Icon(Icons.lan_rounded),
        label: Text(l10n.lanConnectButton),
      ),
      if (packOpen) ...[
        const SizedBox(height: 4),
        Text(l10n.lanClosePackFirst,
            style: const TextStyle(color: AppColors.ink3, fontSize: 12)),
      ],
    ];
  }

  Widget _packRow(AppLocalizations l10n, PackSummary s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.usbPackRow(s.schoolCode, s.packUuid.substring(0, 8)),
                  style: const TextStyle(color: AppColors.ink1)),
              Text(
                  '${l10n.usbSavedCount(s.total)}  ·  '
                  '${l10n.usbUnexportedCount(s.unexported)}',
                  style: const TextStyle(color: AppColors.ink3, fontSize: 12)),
              ValueListenableBuilder(
                valueListenable: AutoSaveStatus.all,
                builder: (_, all, __) {
                  final e = all[s.packUuid];
                  if (e != null && !e.failed && e.lastOkAt != null) {
                    return Text(
                        l10n.autoSaveOk(DateFormat('HH:mm').format(e.lastOkAt!),
                            e.lastResultCount),
                        style: const TextStyle(
                            color: AppColors.ink3, fontSize: 12));
                  }
                  // Only a failure recorded this session; no entry = unknown
                  // (e.g. after restart), so show nothing.
                  if (e != null && e.failed) {
                    return Text(l10n.autoSaveFailed,
                        style: const TextStyle(
                            color: AppColors.err, fontSize: 12));
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
        TextButton(
          onPressed:
              (_busy || !_configured) ? null : () => _export(targets: [s]),
          child: Text(l10n.usbExportOne),
        ),
      ]),
    );
  }

  Widget _notice(String text, {bool error = false}) {
    final color = error ? AppColors.err : AppColors.brand;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Text(text, style: TextStyle(color: color, height: 1.35)),
    );
  }
}

/// 8-digit PIN prompt. The PIN is returned to the caller and goes straight
/// into the key derivation — it is never stored or logged.
class _PinDialog extends StatefulWidget {
  const _PinDialog();

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _submitted = false;

  void _submit() {
    if (_submitted) return;
    final pin = _ctrl.text.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(pin)) {
      setState(() => _error = AppLocalizations.of(context)!.usbPinInvalid);
      return;
    }
    _submitted = true;
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title:
          Text(l10n.usbPinTitle, style: const TextStyle(color: AppColors.ink1)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.usbPinPrompt,
              style: const TextStyle(color: AppColors.ink2)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 8,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 8),
            decoration: InputDecoration(
              counterText: '',
              hintText: l10n.usbPinHint,
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child:
              Text(l10n.cancel, style: const TextStyle(color: AppColors.ink3)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(l10n.usbUnlock,
              style: const TextStyle(color: AppColors.brand)),
        ),
      ],
    );
  }
}
