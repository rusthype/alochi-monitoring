// lib/features/offline/lan_connect_dialog.dart
//
// Student PC -> teacher's hub (phase 3): finds hubs by listening for the UDP
// announcement (falling back to a typed IP:port), takes the 6-digit class
// code, joins, and switches the app into LAN mode. Pops with the activated
// [LanClientSession], or null when the user just closed it.
//
// Also the place that shows what is still waiting for the hub's ack (the
// outbox) and lets the operator disconnect.
import 'dart:async';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/db/lan_outbox_db.dart';
import '../../core/local_server/lan_discovery.dart';
import '../../core/offline/lan_client_session.dart';
import '../../shared/theme/app_theme.dart';

Future<LanClientSession?> showLanConnectDialog(BuildContext context) {
  return showDialog<LanClientSession?>(
    context: context,
    builder: (_) => const LanConnectDialog(),
  );
}

class LanConnectDialog extends StatefulWidget {
  const LanConnectDialog({super.key});

  @override
  State<LanConnectDialog> createState() => _LanConnectDialogState();
}

class _LanConnectDialogState extends State<LanConnectDialog> {
  final _listener = LanDiscoveryListener();
  final _addressCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  DiscoveredHub? _picked;

  /// Joined but not yet confirmed by the student (see [_confirmCard]).
  LanClientSession? _pending;
  bool _busy = false;
  String? _error;
  ({int pending, int rejected}) _outbox = (pending: 0, rejected: 0);

  @override
  void initState() {
    super.initState();
    unawaited(_listener.start());
    _loadOutbox();
  }

  @override
  void dispose() {
    // Joined but never confirmed (dialog closed, window changed): the hub must
    // not keep a ghost client that was never allowed to take part (N-5). An
    // activated session is the app's now and stays.
    final ghost = _pending;
    if (ghost != null && !identical(LanClientSession.current, ghost)) {
      ghost.close();
    }
    _pending = null;
    unawaited(_listener.stop());
    _addressCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOutbox() async {
    try {
      final c = await LanOutboxDb.counts();
      if (mounted) setState(() => _outbox = c);
    } catch (e) {
      debugPrint('LanConnectDialog: outbox counts failed (${e.runtimeType})');
    }
  }

  String _joinError(AppLocalizations l10n, LanJoinException e) {
    switch (e.code) {
      case LanJoinError.badAddress:
        return l10n.lanErrAddress;
      case LanJoinError.badCode:
        return l10n.lanErrBadCode;
      case LanJoinError.blocked:
        return l10n.lanErrBlocked(e.retryAfterSec);
      case LanJoinError.full:
        return l10n.lanErrFull;
      case LanJoinError.unreachable:
        return l10n.lanErrUnreachable;
      case LanJoinError.packActive:
        return l10n.lanClosePackFirst;
      case LanJoinError.joinsClosed:
        return l10n.lanErrJoinsClosed;
      case LanJoinError.badResponse:
        return l10n.lanErrGeneric;
    }
  }

  Future<void> _connect() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = l10n.lanErrCodeFormat);
      return;
    }
    final addr = _picked != null
        ? (host: _picked!.ip, port: _picked!.port)
        : parseHubAddress(_addressCtrl.text);
    if (addr == null) {
      setState(() => _error = l10n.lanErrAddress);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await LanClientSession.join(
          host: addr.host,
          port: addr.port,
          code: code,
          replacing: LanClientSession.current);
      // The announcement and the typed address are not authenticated: before
      // this PC takes part, the student compares the pack tag with what the
      // teacher reads out (S-008). Nothing is activated until then.
      if (mounted) {
        setState(() => _pending = session);
      } else {
        session.close();
      }
    } on LanJoinException catch (e) {
      debugPrint('LanConnectDialog: join refused: ${e.code.name}');
      if (mounted) setState(() => _error = _joinError(l10n, e));
    } catch (e) {
      debugPrint('LanConnectDialog: connect failed (${e.runtimeType})');
      if (mounted) setState(() => _error = l10n.lanErrGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final s = _pending;
    if (s == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await s.activate();
      if (mounted) Navigator.of(context).pop(s);
    } catch (e) {
      debugPrint('LanConnectDialog: activate failed (${e.runtimeType})');
      s.close();
      if (mounted) {
        setState(() {
          _pending = null;
          _error =
              e is LanJoinException ? _joinError(l10n, e) : l10n.lanErrGeneric;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _declineConfirm() {
    _pending?.close(); // tells the hub we are leaving
    setState(() => _pending = null);
  }

  Widget _confirmCard(AppLocalizations l10n, LanClientSession s) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.lanConfirmTitle,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.ink1)),
        const SizedBox(height: 12),
        Text(l10n.lanConfirmBody(s.hubName, s.fingerprint),
            style: const TextStyle(color: AppColors.ink1, height: 1.5)),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _confirm,
          child: Text(l10n.lanConfirmYes),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : _declineConfirm,
          child: Text(l10n.lanConfirmNo),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final active = LanClientSession.current;
    final pending = _pending;
    if (pending != null) {
      return Dialog(
        backgroundColor: AppColors.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _confirmCard(l10n, pending),
          ),
        ),
      );
    }
    return Dialog(
      backgroundColor: AppColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Icon(Icons.lan_rounded, color: AppColors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l10n.lanConnectTitle,
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
                Text(l10n.lanConnectIntro,
                    style: const TextStyle(color: AppColors.ink2, height: 1.4)),
                if (active != null) ...[
                  const SizedBox(height: 12),
                  _statusCard(l10n, active),
                ],
                const SizedBox(height: 16),
                Text(l10n.lanFoundHubs,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.ink1)),
                const SizedBox(height: 6),
                _hubList(l10n),
                const SizedBox(height: 14),
                if (_picked == null) ...[
                  Text(l10n.lanManualAddress,
                      style: const TextStyle(color: AppColors.ink2)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _addressCtrl,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: l10n.lanAddressHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(l10n.lanClassCode,
                    style: const TextStyle(color: AppColors.ink2)),
                const SizedBox(height: 6),
                TextField(
                  controller: _codeCtrl,
                  enabled: !_busy,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, letterSpacing: 8),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: l10n.lanCodeHint,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _busy ? null : _connect(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: AppColors.err)),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _connect,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login_rounded),
                  label: Text(_busy ? l10n.lanConnecting : l10n.lanConnect),
                ),
                if (_outbox.pending > 0 || _outbox.rejected > 0) ...[
                  const SizedBox(height: 14),
                  if (_outbox.pending > 0)
                    Text(l10n.lanUnsentResults(_outbox.pending),
                        style: const TextStyle(color: AppColors.ink1)),
                  if (_outbox.rejected > 0)
                    Text(l10n.lanRejectedResults(_outbox.rejected),
                        style: const TextStyle(color: AppColors.err)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(AppLocalizations l10n, LanClientSession s) {
    return ListenableBuilder(
      listenable:
          Listenable.merge([s.connected, s.needsRejoin, s.pending, s.hold]),
      builder: (context, _) {
        final expired = s.needsRejoin.value;
        final ok = s.connected.value && !expired;
        final color = ok ? AppColors.brand : AppColors.err;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.lanActiveHub(s.hubName),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                  expired
                      ? l10n.lanErrExpired
                      : (ok
                          ? l10n.lanStatusConnected
                          : l10n.lanStatusDisconnected),
                  style: TextStyle(color: color, height: 1.35)),
              if (s.pending.value > 0)
                Text(l10n.lanUnsentResults(s.pending.value),
                    style: const TextStyle(color: AppColors.ink1)),
              if (s.hold.value != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      s.hold.value == 'client_quota'
                          ? l10n.lanHoldClientQuota
                          : l10n.lanHoldPackFull,
                      style:
                          const TextStyle(color: AppColors.err, height: 1.35)),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  s.close();
                  setState(() {});
                  _loadOutbox();
                },
                icon: const Icon(Icons.link_off_rounded),
                label: Text(l10n.lanDisconnect),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _hubList(AppLocalizations l10n) {
    return ValueListenableBuilder<List<DiscoveredHub>>(
      valueListenable: _listener.hubs,
      builder: (context, hubs, _) {
        if (hubs.isEmpty) {
          return ValueListenableBuilder<bool>(
            valueListenable: _listener.bindFailed,
            builder: (context, failed, _) => Text(
                failed ? l10n.lanDiscoveryUnavailable : l10n.lanNoHubsFound,
                style: const TextStyle(color: AppColors.ink3, height: 1.35)),
          );
        }
        return Column(children: [
          for (final h in hubs)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: _picked?.address == h.address
                  ? AppColors.brandLight
                  : AppColors.surface,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.computer_rounded),
                title: Text(h.name),
                subtitle: Text([
                  h.address,
                  if (h.packLabel.isNotEmpty) l10n.usbSchoolLabel(h.packLabel),
                ].join('  ·  ')),
                onTap: _busy
                    ? null
                    : () => setState(() {
                          _picked = _picked?.address == h.address ? null : h;
                          _error = null;
                        }),
              ),
            ),
        ]);
      },
    );
  }
}
