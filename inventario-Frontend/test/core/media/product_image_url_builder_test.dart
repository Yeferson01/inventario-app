import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/media/product_image_url_builder.dart';

void main() {
  const builder = ProductImageUrlBuilder();

  test('builds the deterministic optimized Cloudinary URL and cache key', () {
    final asset = builder.resolve('7622 2017 64999');

    expect(asset, isNotNull);
    expect(asset!.barcode, '7622201764999');
    expect(
      asset.url,
      'https://res.cloudinary.com/pqn2urlk/image/upload/'
      'c_limit,w_256/f_auto/q_auto:eco/7622201764999',
    );
    expect(asset.cacheKey, 'product_thumb_v1:7622201764999');
    expect(builder.buildThumbnailUrl('7622201764999'), asset.url);
  });

  test('returns no asset for missing, internal, or invalid GTIN barcodes', () {
    expect(builder.resolve(null), isNull);
    expect(builder.resolve('  '), isNull);
    expect(builder.resolve('LOCAL-123'), isNull);
    expect(builder.resolve('7622201764998'), isNull);
  });

  test('preserves a valid leading zero in the barcode public ID', () {
    final asset = builder.resolve('012345678905');

    expect(asset, isNotNull);
    expect(asset!.barcode, '012345678905');
    expect(asset.url, endsWith('/012345678905'));
    expect(asset.cacheKey, 'product_thumb_v1:012345678905');
  });
}
