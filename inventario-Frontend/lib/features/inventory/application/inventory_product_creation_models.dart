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
    this.purchasePrice = 0,
    this.branchId,
    this.profileId,
    this.appDeviceId,
    this.deviceInstallationId,
    this.categoryId,
    this.nameOverride,
    this.description,
    this.unit,
    this.clientSequenceStart = 1,
  });

  final String businessId;
  final String? branchId;
  final String? profileId;
  final String? appDeviceId;
  final String? deviceInstallationId;

  final Map<String, dynamic> masterProduct;
  final Map<String, dynamic> barcodeRecord;

  final double salePrice;
  final double purchasePrice;
  final String? categoryId;
  final String? nameOverride;
  final String? description;
  final String? unit;

  final int clientSequenceStart;
}

class PendingCatalogSyncMutationDraft {
  const PendingCatalogSyncMutationDraft({
    required this.clientMutationId,
    required this.clientSequence,
    required this.entityTable,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.changedFields,
    required this.idempotencyKey,
    this.businessId,
    this.branchId,
    this.profileId,
    this.appDeviceId,
  });

  final String clientMutationId;
  final int clientSequence;
  final String entityTable;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final List<String> changedFields;
  final String idempotencyKey;

  final String? businessId;
  final String? branchId;
  final String? profileId;
  final String? appDeviceId;

  Map<String, dynamic> toJson() {
    return {
      'client_mutation_id': clientMutationId,
      'client_sequence': clientSequence,
      'entity_table': entityTable,
      'entity_id': entityId,
      'operation': operation,
      'payload': payload,
      'changed_fields': changedFields,
      'idempotency_key': idempotencyKey,
      'business_id': businessId,
      'branch_id': branchId,
      'profile_id': profileId,
      'app_device_id': appDeviceId,
    };
  }
}

class CreatedLocalProductResult {
  const CreatedLocalProductResult({
    required this.productId,
    required this.businessId,
    required this.masterProductId,
    required this.barcode,
    required this.barcodeNormalized,
    required this.name,
    required this.productPayload,
    required this.businessBarcodePayload,
    required this.pendingMutations,
  });

  final String productId;
  final String businessId;
  final String masterProductId;
  final String barcode;
  final String barcodeNormalized;
  final String name;

  final Map<String, dynamic> productPayload;
  final Map<String, dynamic> businessBarcodePayload;
  final List<PendingCatalogSyncMutationDraft> pendingMutations;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'business_id': businessId,
      'master_product_id': masterProductId,
      'barcode': barcode,
      'barcode_normalized': barcodeNormalized,
      'name': name,
      'product_payload': productPayload,
      'business_barcode_payload': businessBarcodePayload,
      'pending_mutations':
          pendingMutations.map((item) => item.toJson()).toList(),
    };
  }
}
