import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/app_image_cache.dart';

/// An image that is fetched once and then kept on the device.
///
/// Wraps CachedNetworkImage so the cache configuration and the id-based key
/// live in one place rather than being repeated at every render site, where
/// they would eventually disagree.
///
/// [cacheKey] is derived from the image id, never from [url]. Signed URLs
/// expire and are re-issued constantly; keying on one would mean a fresh
/// download every time and a disk slowly filling with copies of the same
/// picture.
class CachedImage extends StatelessWidget {
  const CachedImage({
    required this.url,
    required this.cacheKey,
    this.fit,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.onRendered,
    this.onFailed,
    super.key,
  });

  final String url;
  final String cacheKey;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget Function(BuildContext context, Object error)? errorWidget;

  /// Called once the image is on screen, and once it has failed.
  ///
  /// These carry the reporting that Image.network did through frameBuilder and
  /// errorBuilder. That instrumentation is the only thing that has ever caught
  /// the blank-screen fault, so it is passed through deliberately rather than
  /// left behind in the swap.
  final VoidCallback? onRendered;
  final void Function(Object error)? onFailed;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: cacheKey,
      cacheManager: AppImageCache.manager,
      fit: fit,
      width: width,
      height: height,
      // Held across rebuilds so a list scroll does not flash placeholders for
      // images already decoded.
      fadeInDuration: const Duration(milliseconds: 120),
      imageBuilder: (context, provider) {
        // Reaching here means the bytes decoded, so the entry is in the cache
        // and worth remembering for eviction.
        AppImageCache.track(cacheKey);
        onRendered?.call();

        return Image(
          image: provider,
          fit: fit,
          width: width,
          height: height,
        );
      },
      placeholder: (context, _) =>
          placeholder ??
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorWidget: (context, _, error) {
        onFailed?.call(error);

        return errorWidget?.call(context, error) ??
            const Center(child: Icon(Icons.broken_image_outlined));
      },
    );
  }
}
