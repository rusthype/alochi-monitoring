// lib/shared/widgets/update_popover.dart
// "Update available" pill for the login screen. Tapping it opens a small
// anchored popover (arrow pointing at the pill) with version / size / date,
// Skip / Later / Install and a release-notes link. Installing swaps the pill
// for a compact "Downloading: 20%" capsule; a failed download reopens the
// popover with the localized error and Retry / Open-in-browser actions.
// Never opens the system browser on its own — only the explicit buttons do.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/update_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/app_localizations.dart';
import 'hover_region.dart';

typedef UpdateInstallFn = Future<UpdateResult> Function(
  UpdateInfo info, {
  void Function(double progress)? onProgress,
});

enum _Stage { idle, downloading, error }

class UpdatePill extends StatefulWidget {
  final UpdateInfo info;

  /// Icon-only pill (narrow windows).
  final bool compact;

  /// Called after the user chose "Skip" (the version is already persisted).
  final VoidCallback? onSkipped;

  final Color surface;
  final Color border;
  final Color ink1;
  final Color ink2;
  final Color hoverFill;
  final List<BoxShadow> shadow;

  // Test seams — default to the real UpdateService.
  final UpdateInstallFn? install;
  final Future<int?> Function(UpdateInfo info)? sizeLoader;
  final VoidCallback? onOpenReleaseNotes;

  const UpdatePill({
    super.key,
    required this.info,
    required this.surface,
    required this.border,
    required this.ink1,
    required this.ink2,
    required this.hoverFill,
    this.shadow = const [],
    this.compact = false,
    this.onSkipped,
    this.install,
    this.sizeLoader,
    this.onOpenReleaseNotes,
  });

  @override
  State<UpdatePill> createState() => _UpdatePillState();
}

class _UpdatePillState extends State<UpdatePill> {
  static const double _popoverWidth = 380;

  /// Shared height of the update pill and the download capsule, so swapping
  /// one for the other never changes the row height.
  static const double _pillHeight = 40;

  final _portal = OverlayPortalController();
  final _link = LayerLink();
  _Stage _stage = _Stage.idle;
  double _progress = 0;
  String? _error;
  double _arrowRight = 24;

  int? _sizeBytes;
  bool _sizeLoading = false;
  bool _sizeRequested = false;

  @override
  void initState() {
    super.initState();
    _sizeBytes = UpdateService.instance.cachedInstallerSize(widget.info);
  }

  Future<void> _loadSize() async {
    if (_sizeBytes != null || _sizeRequested) return;
    _sizeRequested = true;
    setState(() => _sizeLoading = true);
    int? size;
    try {
      size = await (widget.sizeLoader ??
          UpdateService.instance.fetchInstallerSize)(widget.info);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _sizeBytes = size;
      _sizeLoading = false;
    });
  }

  void _open() {
    if (_stage == _Stage.downloading || _portal.isShowing) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      _arrowRight = (box.size.width / 2 - 7).clamp(14.0, 160.0);
    }
    // The login screen prefetches the size on accept; pick it up so the row
    // is in the very first frame of the popover.
    _sizeBytes ??= UpdateService.instance.cachedInstallerSize(widget.info);
    _portal.show();
    _loadSize();
  }

  void _close() {
    if (_portal.isShowing) _portal.hide();
  }

  Future<void> _skip() async {
    _close();
    await UpdateService.instance.skipVersion(widget.info.latestVersion);
    widget.onSkipped?.call();
  }

  Future<void> _install() async {
    _close();
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
      _error = null;
    });
    UpdateResult result;
    try {
      result = await (widget.install ??
          UpdateService.instance.downloadAndInstallUpdate)(
        widget.info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (_) {
      result = const UpdateResult.failed(null);
    }
    if (!mounted) return;
    if (result.success) {
      // Practically unreachable — success calls exit(0) before returning.
      setState(() => _stage = _Stage.idle);
      return;
    }
    setState(() {
      _stage = _Stage.error;
      _error = result.error;
    });
    _portal.show();
  }

  void _openNotes() {
    (widget.onOpenReleaseNotes ?? UpdateService.instance.openReleasePage)();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildPopover,
        child: _stage == _Stage.downloading
            ? _buildDownloadPill(context)
            : _buildUpdatePill(context),
      ),
    );
  }

  Widget _buildUpdatePill(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: l10n.newVersionAvailable,
      child: HoverRegion(
        builder: (context, isHovered) => GestureDetector(
          onTap: _open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _pillHeight,
            // Compact = icon-only circle (width == height); otherwise padded.
            width: widget.compact ? _pillHeight : null,
            alignment: Alignment.center,
            padding: widget.compact
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isHovered ? widget.hoverFill : widget.surface,
              // Full stadium: fully semicircular ends (radius >= height / 2).
              borderRadius: AppRadii.roundedFull,
              border: Border.all(color: widget.border),
              boxShadow: widget.shadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update_alt_rounded,
                  size: 16,
                  color: AppColors.brand,
                ),
                if (!widget.compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    l10n.newVersionAvailable,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: widget.ink1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadPill(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final percent = (_progress.clamp(0.0, 1.0) * 100).toInt();
    final style = AppTextStyles.labelLarge.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: widget.ink1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      liveRegion: true,
      label: l10n.updateDownloadingPill(percent),
      child: Container(
        height: _pillHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: widget.surface,
          borderRadius: AppRadii.roundedFull,
          border: Border.all(color: widget.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .14),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: _progress.clamp(0.0, 1.0),
                strokeWidth: 3,
                backgroundColor: AppColors.brand.withValues(alpha: .18),
                valueColor: const AlwaysStoppedAnimation(AppColors.brand),
              ),
            ),
            const SizedBox(width: 12),
            // Constant width for the whole download: reserve the widest text
            // ("... 100%") and use tabular digits, so neither the ring nor
            // the text (nor the neighbouring language capsule) ever moves.
            SizedBox(
              width: _textWidth(context, l10n.updateDownloadingPill(100), style),
              child: Text(
                l10n.updateDownloadingPill(percent),
                maxLines: 1,
                softWrap: false,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _textWidth(BuildContext context, String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width.ceilToDouble() + 1; // +1: sub-pixel rounding slack
    tp.dispose();
    return w;
  }

  Widget _buildPopover(BuildContext overlayContext) {
    final l10n = AppLocalizations.of(overlayContext)!;
    final isError = _stage == _Stage.error;
    return Stack(
      children: [
        // Outside tap closes (the popover is only open when not downloading).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 4),
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.escape) {
                _close();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Align(
              alignment: Alignment.topRight,
              widthFactor: 1,
              heightFactor: 1,
              child: SizedBox(
                width: _popoverWidth,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        key: const ValueKey('update-popover-card'),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: widget.surface,
                          borderRadius: AppRadii.roundedLg,
                          border: Border.all(color: widget.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .16),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child:
                              isError ? _errorBody(l10n) : _infoBody(l10n),
                        ),
                      ),
                    ),
                    // Arrow: bordered triangle whose base overpaints the
                    // card's top border so it reads as one speech bubble.
                    Positioned(
                      top: 0,
                      right: _arrowRight,
                      child: CustomPaint(
                        key: const ValueKey('update-popover-arrow'),
                        size: const Size(16, 9),
                        painter: _ArrowPainter(widget.surface, widget.border),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoBody(AppLocalizations l10n) {
    final date = widget.info.releasedAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.updateAvailableTitle,
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
            color: widget.ink1,
          ),
        ),
        const SizedBox(height: 12),
        _row(l10n.updateVersionLabel, 'v${widget.info.latestVersion}'),
        if (_sizeBytes != null || _sizeLoading)
          _row(
            l10n.updateSizeLabel,
            _sizeBytes != null
                ? l10n.updateSizeMb(
                    (_sizeBytes! / (1024 * 1024)).toStringAsFixed(1))
                : '…',
          ),
        if (date != null) _row(l10n.updateReleasedLabel, _formatDate(date)),
        const SizedBox(height: 14),
        Row(
          children: [
            _smallButton(l10n.updateSkipBtn, _skip),
            const SizedBox(width: 4),
            _smallButton(l10n.updateLaterBtn, _close),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _install,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadii.roundedMd,
                    ),
                  ),
                  child: Text(
                    l10n.updateInstallRelaunchBtn,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: widget.border),
        InkWell(
          onTap: _openNotes,
          borderRadius: AppRadii.roundedSm,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 18, color: widget.ink2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.updateReleaseNotes,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: widget.ink1,
                    ),
                  ),
                ),
                Icon(Icons.open_in_new_rounded, size: 16, color: widget.ink2),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorBody(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _error ?? l10n.updateDownloadFailedMsg,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.err),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () {
                _close();
                _openNotes();
              },
              child: Text(l10n.openInBrowserBtn),
            ),
            ElevatedButton(
              onPressed: _install,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(color: widget.ink2),
            ),
            const Spacer(),
            Text(
              value,
              style: AppTextStyles.labelLarge.copyWith(
                color: widget.ink1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );

  Widget _smallButton(String text, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: widget.ink2,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(text, style: AppTextStyles.labelLarge.copyWith(
          color: widget.ink2,
        )),
      );
}

String _formatDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)}.${l.year}';
}

class _ArrowPainter extends CustomPainter {
  final Color fill;
  final Color stroke;
  const _ArrowPainter(this.fill, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    const w = 16.0, h = 8.0;
    canvas.drawPath(
      Path()
        ..moveTo(0, h + 1)
        ..lineTo(0, h)
        ..lineTo(w / 2, 0)
        ..lineTo(w, h)
        ..lineTo(w, h + 1)
        ..close(),
      Paint()..color = fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, h)
        ..lineTo(w / 2, 0)
        ..lineTo(w, h),
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.fill != fill || old.stroke != stroke;
}
