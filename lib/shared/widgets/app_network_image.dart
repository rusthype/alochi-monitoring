import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';

/// Always use this instead of Image.network() for server images.
/// Handles: relative URLs, SSL on Windows, loading/error states.
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
      return errorWidget ?? const SizedBox.shrink();
    }

    Widget img = Image.network(
      fixedUrl,
      height: height,
      width: width,
      fit: fit,
      headers: const {'User-Agent': 'AlochiMonitoring/1.0'},
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return placeholder ??
            SizedBox(
              height: height ?? 80,
              width: width,
              child: Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2,
                ),
              ),
            );
      },
      errorBuilder: (ctx, error, stack) =>
          errorWidget ??
          Icon(
            Icons.broken_image_outlined,
            size: 24,
            color: Theme.of(ctx).colorScheme.error,
          ),
    );

    if (borderRadius != null) {
      img = ClipRRect(borderRadius: borderRadius!, child: img);
    }
    return img;
  }
}
