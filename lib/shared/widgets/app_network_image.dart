import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/cache/image_cache_manager.dart';

/// Barcha server rasmlar uchun shu widget ishlatiladi.
/// Bir marta yuklab, diskda saqlaydi (30 kun)
/// Offline bo'lsa ham ko'rsatadi (cached versiya)
/// Windows SSL muammosi yo'q
/// Loading va error holatlari bor
class AppNetworkImage extends StatelessWidget {
  final String? url;
  final double? height;
  final double? width;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.fit = BoxFit.contain,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final fixedUrl = MonitoringApi.fixImageUrl(url);
    if (fixedUrl.isEmpty) {
      return errorWidget ??
          SizedBox(
            height: height ?? 80,
            width: width,
          );
    }

    Widget img = CachedNetworkImage(
      imageUrl: fixedUrl,
      cacheManager: AlochiImageCacheManager(),
      height: height,
      width: width,
      fit: fit,
      httpHeaders: const {'User-Agent': 'AlochiMonitoring/1.0'},
      placeholder: (ctx, url) => SizedBox(
        height: height ?? 80,
        width: width,
        child: placeholder ??
            const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Color(0xFFF97316)),
              ),
            ),
      ),
      errorWidget: (ctx, url, err) =>
          errorWidget ??
          Icon(
            Icons.broken_image_outlined,
            size: 24,
            color: Colors.grey[400],
          ),
    );

    if (borderRadius != null) {
      img = ClipRRect(borderRadius: borderRadius!, child: img);
    }
    return img;
  }
}
