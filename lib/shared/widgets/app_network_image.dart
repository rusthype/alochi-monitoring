import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/cache/image_cache_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// Barcha server rasmlar uchun shu widget ishlatiladi.
/// Bir marta yuklab, diskda saqlaydi (30 kun)
/// Offline bo'lsa ham ko'rsatadi (cached versiya)
/// Windows SSL muammosi yo'q
/// Loading va error holatlari bor
class AppNetworkImage extends StatefulWidget {
  final String? url;
  final double? height;
  final double? width;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Alignment alignment;
  final bool showZoom;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
    this.showZoom = false,
  });

  @override
  State<AppNetworkImage> createState() => _AppNetworkImageState();
}

class _AppNetworkImageState extends State<AppNetworkImage> {
  /// Bumped on tap-to-retry — forces `CachedNetworkImage` to rebuild with a
  /// fresh key after the previous failed cache entry is evicted, instead of
  /// re-rendering the same stuck error widget.
  int _retryNonce = 0;

  @override
  Widget build(BuildContext context) {
    final fixedUrl = MonitoringApi.fixImageUrl(widget.url);
    if (fixedUrl.isEmpty) {
      return widget.errorWidget ??
          SizedBox(
            height: widget.height ?? 80,
            width: widget.width,
          );
    }

    Widget img = CachedNetworkImage(
      key: ValueKey('$fixedUrl#$_retryNonce'),
      imageUrl: fixedUrl,
      cacheManager: AlochiImageCacheManager(),
      height: widget.height,
      width: widget.width,
      fit: widget.fit,
      alignment: widget.alignment,
      filterQuality: FilterQuality.medium,
      httpHeaders: const {'User-Agent': 'AlochiMonitoring/1.0'},
      placeholder: (ctx, url) => SizedBox(
        height: widget.height ?? 80,
        width: widget.width,
        child: widget.placeholder ??
            const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.flame),
              ),
            ),
      ),
      errorWidget: (ctx, url, err) =>
          widget.errorWidget ??
          InkWell(
            onTap: () async {
              await AlochiImageCacheManager().removeFile(fixedUrl);
              if (mounted) setState(() => _retryNonce++);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined,
                    size: 24, color: Colors.grey[400]),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)!.retry,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
    );

    if (widget.borderRadius != null) {
      img = ClipRRect(borderRadius: widget.borderRadius!, child: img);
    }

    if (widget.showZoom) {
      img = GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            barrierColor: Colors.black87,
            builder: (ctx) => Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: MediaQuery.of(ctx).size.width,
                height: MediaQuery.of(ctx).size.height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      maxScale: 5.0,
                      child: Center(
                        child: CachedNetworkImage(
                          imageUrl: fixedUrl,
                          cacheManager: AlochiImageCacheManager(),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          httpHeaders: const {
                            'User-Agent': 'AlochiMonitoring/1.0'
                          },
                          placeholder: (c, u) => const Center(
                            child:
                                CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 20,
                      right: 20,
                      child: IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white, size: 32),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            img,
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.zoom_in, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      );
    }

    return img;
  }
}
