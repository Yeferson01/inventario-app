import '../utils/barcode_normalizer.dart';

class ProductImageAsset {
  const ProductImageAsset({
    required this.barcode,
    required this.url,
    required this.cacheKey,
  });

  final String barcode;
  final String url;
  final String cacheKey;
}

class ProductImageUrlBuilder {
  const ProductImageUrlBuilder();

  static const cloudName = 'pqn2urlk';
  static const transformationProfile = 'product_thumb_v1';
  static const targetWidth = 256;
  static const _deliveryPrefix =
      'https://res.cloudinary.com/$cloudName/image/upload/'
      'c_limit,w_$targetWidth/f_auto/q_auto:eco';

  ProductImageAsset? resolve(String? barcode) {
    final normalized = _validBarcode(barcode);
    if (normalized == null) return null;

    return ProductImageAsset(
      barcode: normalized,
      url: '$_deliveryPrefix/$normalized',
      cacheKey: '$transformationProfile:$normalized',
    );
  }

  String? buildThumbnailUrl(String? barcode) => resolve(barcode)?.url;

  String? _validBarcode(String? barcode) {
    if (barcode == null) return null;
    final normalized = BarcodeNormalizer.normalize(barcode);
    if (!BarcodeNormalizer.looksLikeGtin(normalized)) return null;
    return _hasValidGtinCheckDigit(normalized) ? normalized : null;
  }

  bool _hasValidGtinCheckDigit(String value) {
    var sum = 0;
    for (var index = 0; index < value.length - 1; index++) {
      final digit = int.parse(value[index]);
      final positionFromRight = value.length - 1 - index;
      sum += positionFromRight.isOdd ? digit * 3 : digit;
    }
    final expectedCheckDigit = (10 - (sum % 10)) % 10;
    return expectedCheckDigit == int.parse(value[value.length - 1]);
  }
}
