class ProductFromMasterDraft {
  const ProductFromMasterDraft({
    required this.businessId,
    required this.masterProductId,
    required this.barcode,
    required this.barcodeNormalized,
    required this.barcodeType,
    required this.name,
    this.brand,
    this.manufacturer,
    this.categoryName,
    this.subcategoryName,
    this.packageSize,
    this.packageUnit,
    this.unitType,
    this.imageThumbUrl,
    this.imageHash,
    this.confidenceScore,
  });

  final String businessId;
  final String masterProductId;
  final String barcode;
  final String barcodeNormalized;
  final String barcodeType;
  final String name;
  final String? brand;
  final String? manufacturer;
  final String? categoryName;
  final String? subcategoryName;
  final double? packageSize;
  final String? packageUnit;
  final String? unitType;
  final String? imageThumbUrl;
  final String? imageHash;
  final double? confidenceScore;

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'master_product_id': masterProductId,
      'barcode': barcode,
      'barcode_normalized': barcodeNormalized,
      'barcode_type': barcodeType,
      'name': name,
      'brand': brand,
      'manufacturer': manufacturer,
      'category_name': categoryName,
      'subcategory_name': subcategoryName,
      'package_size': packageSize,
      'package_unit': packageUnit,
      'unit_type': unitType,
      'image_thumb_url': imageThumbUrl,
      'image_hash': imageHash,
      'confidence_score': confidenceScore,
    };
  }
}

class CreateProductFromMasterInput {
  const CreateProductFromMasterInput({
    required this.businessId,
    required this.masterProduct,
    required this.barcodeRecord,
    required this.salePrice,
    required this.purchasePrice,
    this.categoryId,
    this.nameOverride,
    this.description,
    this.initialStock = 0,
    this.minimumStock = 0,
    this.unit,
  });

  final String businessId;
  final Map<String, dynamic> masterProduct;
  final Map<String, dynamic> barcodeRecord;
  final double salePrice;
  final double purchasePrice;
  final String? categoryId;
  final String? nameOverride;
  final String? description;
  final int initialStock;
  final int minimumStock;
  final String? unit;
}

class CreatedLocalProductResult {
  const CreatedLocalProductResult({
    required this.productId,
    required this.businessId,
    required this.masterProductId,
    required this.barcode,
    required this.barcodeNormalized,
    required this.name,
    required this.syncStatus,
  });

  final String productId;
  final String businessId;
  final String masterProductId;
  final String barcode;
  final String barcodeNormalized;
  final String name;
  final String syncStatus;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'business_id': businessId,
      'master_product_id': masterProductId,
      'barcode': barcode,
      'barcode_normalized': barcodeNormalized,
      'name': name,
      'sync_status': syncStatus,
    };
  }
}
