import 'operational_bootstrap_models.dart';

class ProductOperationalCategorySnapshot {
  const ProductOperationalCategorySnapshot({
    required this.id,
    required this.businessId,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  factory ProductOperationalCategorySnapshot.fromRow(
    OperationalBootstrapRow row,
  ) {
    _requireRecordState(row);
    final json = row.data;
    return ProductOperationalCategorySnapshot(
      id: _requiredString(json, 'id'),
      businessId: _requiredString(json, 'business_id'),
      name: _requiredString(json, 'name'),
      description: _optionalString(json['description']),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
      deletedAt: _optionalDateTime(json['deleted_at'], 'deleted_at'),
    );
  }

  final String id;
  final String businessId;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class ProductOperationalProductSnapshot {
  const ProductOperationalProductSnapshot({
    required this.id,
    required this.businessId,
    required this.categoryId,
    required this.masterProductId,
    required this.barcode,
    required this.name,
    required this.description,
    required this.purchasePrice,
    required this.salePrice,
    required this.stockQuantity,
    required this.minimumStock,
    required this.unit,
    required this.status,
    required this.simpleCategory,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  factory ProductOperationalProductSnapshot.fromRow(
    OperationalBootstrapRow row,
  ) {
    _requireRecordState(row);
    final json = row.data;
    return ProductOperationalProductSnapshot(
      id: _requiredString(json, 'id'),
      businessId: _requiredString(json, 'business_id'),
      categoryId: _optionalString(json['category_id']),
      masterProductId: _optionalString(json['master_product_id']),
      barcode: _optionalString(json['barcode']),
      name: _requiredString(json, 'name'),
      description: _optionalString(json['description']),
      purchasePrice: _optionalDouble(json['purchase_price']) ?? 0,
      salePrice: _requiredDouble(json, 'sale_price'),
      stockQuantity: _optionalInt(json['stock_quantity']) ?? 0,
      minimumStock: _optionalInt(json['minimum_stock']) ?? 0,
      unit: _optionalString(json['unit']) ?? 'unidad',
      status: _optionalString(json['status']) ?? 'active',
      simpleCategory: _optionalString(json['simple_category']),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
      deletedAt: _optionalDateTime(json['deleted_at'], 'deleted_at'),
    );
  }

  final String id;
  final String businessId;
  final String? categoryId;
  final String? masterProductId;
  final String? barcode;
  final String name;
  final String? description;
  final double purchasePrice;
  final double salePrice;
  final int stockQuantity;
  final int minimumStock;
  final String unit;
  final String status;
  final String? simpleCategory;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class ProductOperationalBarcodeSnapshot {
  const ProductOperationalBarcodeSnapshot({
    required this.id,
    required this.scope,
    required this.businessId,
    required this.productId,
    required this.masterProductId,
    required this.barcode,
    required this.barcodeNormalized,
    required this.barcodeType,
    required this.isPrimary,
    required this.status,
    required this.source,
    required this.confidenceScore,
    required this.version,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  factory ProductOperationalBarcodeSnapshot.fromRow(
    OperationalBootstrapRow row,
  ) {
    _requireRecordState(row);
    final json = row.data;
    final scope = _requiredString(json, 'scope');
    final businessId = _optionalString(json['business_id']);
    final productId = _optionalString(json['product_id']);
    final masterProductId = _optionalString(json['master_product_id']);
    if (scope == 'business' && (businessId == null || productId == null)) {
      throw _malformed(
        'Business product_barcodes require business_id and product_id.',
      );
    }
    if (scope == 'global' &&
        (businessId != null || productId != null || masterProductId == null)) {
      throw _malformed(
        'Global product_barcodes require only master_product_id ownership.',
      );
    }
    if (scope != 'business' && scope != 'global') {
      throw _malformed('Unsupported product_barcodes scope: $scope.');
    }

    return ProductOperationalBarcodeSnapshot(
      id: _requiredString(json, 'id'),
      scope: scope,
      businessId: businessId,
      productId: productId,
      masterProductId: masterProductId,
      barcode: _requiredString(json, 'barcode'),
      barcodeNormalized: _requiredString(json, 'barcode_normalized'),
      barcodeType: _optionalString(json['barcode_type']) ?? 'unknown',
      isPrimary: _requiredBool(json, 'is_primary'),
      status: _optionalString(json['status']) ?? 'active',
      source: _optionalString(json['source']),
      confidenceScore: _optionalDouble(json['confidence_score']),
      version: _optionalInt(json['version']) ?? 1,
      metadata: json['metadata'],
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
      deletedAt: _optionalDateTime(json['deleted_at'], 'deleted_at'),
    );
  }

  final String id;
  final String scope;
  final String? businessId;
  final String? productId;
  final String? masterProductId;
  final String barcode;
  final String barcodeNormalized;
  final String barcodeType;
  final bool isPrimary;
  final String status;
  final String? source;
  final double? confidenceScore;
  final int version;
  final Object? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

void _requireRecordState(OperationalBootstrapRow row) {
  if (row.state == OperationalBootstrapRecordState.unspecified) {
    throw _malformed('Product operational rows require an explicit state.');
  }
}

OperationalBootstrapException _malformed(String message) {
  return OperationalBootstrapException(
    kind: OperationalBootstrapFailureKind.malformedResponse,
    message: message,
  );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) {
    throw _malformed('$key must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw _malformed('Expected a non-empty string or null.');
  }
  return value.trim();
}

double _requiredDouble(Map<String, Object?> json, String key) {
  final value = _optionalDouble(json[key]);
  if (value == null) {
    throw _malformed('$key must be numeric.');
  }
  return value;
}

double? _optionalDouble(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw _malformed('Expected a numeric value or null.');
}

int? _optionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw _malformed('Expected an integer or null.');
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw _malformed('$key must be boolean.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _optionalDateTime(json[key], key);
  if (value == null) {
    throw _malformed('$key must be an ISO-8601 timestamp.');
  }
  return value;
}

DateTime? _optionalDateTime(Object? value, String key) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw _malformed('$key must be an ISO-8601 string or null.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw _malformed('$key is not a valid ISO-8601 timestamp.');
  }
  return parsed.toUtc();
}
