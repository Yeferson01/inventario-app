import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../core/media/product_image_url_builder.dart';

typedef ProductImageProviderFactory = ImageProvider<Object> Function(
  ProductImageAsset asset,
);

final CacheManager _productThumbnailCache = CacheManager(
  Config(
    'product_thumbnail_cache_v1',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 300,
  ),
);

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.barcode,
    this.size = 48,
    this.semanticLabel,
    this.urlBuilder = const ProductImageUrlBuilder(),
    @visibleForTesting this.imageProviderFactory,
  });

  final String? barcode;
  final double size;
  final String? semanticLabel;
  final ProductImageUrlBuilder urlBuilder;
  final ProductImageProviderFactory? imageProviderFactory;

  @override
  Widget build(BuildContext context) {
    final asset = urlBuilder.resolve(barcode);
    final placeholder = _ProductImagePlaceholder(size: size);
    if (asset == null) return placeholder;

    final provider = imageProviderFactory?.call(asset) ??
        ResizeImage.resizeIfNeeded(
          ProductImageUrlBuilder.targetWidth,
          ProductImageUrlBuilder.targetWidth,
          CachedNetworkImageProvider(
            asset.url,
            cacheKey: asset.cacheKey,
            cacheManager: _productThumbnailCache,
          ),
        );

    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image(
          image: provider,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          semanticLabel: semanticLabel,
          excludeFromSemantics: semanticLabel == null,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return KeyedSubtree(
                key: const Key('product-image-loaded'),
                child: child,
              );
            }
            return placeholder;
          },
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      ),
    );
  }
}

class _ProductImagePlaceholder extends StatelessWidget {
  const _ProductImagePlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const Key('product-image-placeholder'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.inventory_2_outlined,
        color: colors.primary,
      ),
    );
  }
}
