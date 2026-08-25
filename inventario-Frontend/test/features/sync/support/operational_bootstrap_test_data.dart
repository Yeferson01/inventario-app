Map<String, Object?> bootstrapRpcResponse({
  String snapshotId = 'snapshot-1',
  String profileId = 'profile-a',
  String businessId = 'business-a',
  String branchId = 'branch-x',
  String appDeviceId = 'device-a',
  String bundle = 'product_operational',
  String? datasetRequested = 'products',
  Map<String, Map<String, Object?>>? datasets,
  bool? snapshotComplete,
  bool? requestedDatasetsComplete,
  String snapshotAt = '2026-08-15T09:00:00Z',
  String authorizationValidatedAt = '2026-08-15T10:00:00Z',
}) {
  final resolvedDatasets = datasets ??
      {
        'products': bootstrapDatasetPage(
          dataset: 'products',
          rows: const [
            {
              'id': 'product-1',
              'name': 'Product 1',
              '_bootstrap_record_state': 'present',
            },
          ],
        ),
      };
  final anyHasMore = resolvedDatasets.values.any(
    (dataset) => dataset['has_more'] == true,
  );
  return {
    'snapshot_id': snapshotId,
    'snapshot_at': snapshotAt,
    'profile_id': profileId,
    'business_id': businessId,
    'branch_id': branchId,
    'app_device_id': appDeviceId,
    'bundle': bundle,
    'dataset_requested': datasetRequested,
    'datasets': resolvedDatasets,
    'snapshot_complete':
        snapshotComplete ?? (datasetRequested == null ? !anyHasMore : null),
    'requested_datasets_complete': requestedDatasetsComplete ?? !anyHasMore,
    'authorization_validated_at': authorizationValidatedAt,
    'generated_at': '2026-08-15T10:00:01Z',
    'sync_cursor_read': false,
    'sync_cursor_advanced': false,
    'consistency': const {
      'model': 'fixed_identity_window_current_values',
      'keyset': 'id',
    },
  };
}

Map<String, Object?> productOperationalCategoryRow({
  required String id,
  String businessId = 'business-a',
  String name = 'Category',
  String? description,
  String state = 'present',
  String createdAt = '2026-08-01T08:00:00Z',
  String updatedAt = '2026-08-14T08:00:00Z',
  String? deletedAt,
}) {
  return {
    'id': id,
    'business_id': businessId,
    'name': name,
    'description': description,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
    '_bootstrap_record_state': state,
  };
}

Map<String, Object?> productOperationalProductRow({
  required String id,
  String businessId = 'business-a',
  String? categoryId,
  String? masterProductId,
  String? barcode,
  String name = 'Product',
  String? description,
  double purchasePrice = 5,
  double salePrice = 10,
  int stockQuantity = 0,
  int minimumStock = 0,
  String unit = 'unidad',
  String status = 'active',
  String? simpleCategory,
  String state = 'present',
  String createdAt = '2026-08-01T08:00:00Z',
  String updatedAt = '2026-08-14T08:00:00Z',
  String? deletedAt,
}) {
  return {
    'id': id,
    'business_id': businessId,
    'category_id': categoryId,
    'master_product_id': masterProductId,
    'barcode': barcode,
    'name': name,
    'description': description,
    'purchase_price': purchasePrice,
    'sale_price': salePrice,
    'stock_quantity': stockQuantity,
    'minimum_stock': minimumStock,
    'unit': unit,
    'status': status,
    'simple_category': simpleCategory,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
    '_bootstrap_record_state': state,
  };
}

Map<String, Object?> productOperationalBarcodeRow({
  required String id,
  String scope = 'business',
  String? businessId = 'business-a',
  String? productId = 'product-1',
  String? masterProductId,
  String barcode = '7700000000001',
  String barcodeNormalized = '7700000000001',
  String barcodeType = 'ean13',
  bool isPrimary = true,
  String status = 'active',
  String? source = 'business',
  double? confidenceScore,
  int version = 1,
  Map<String, Object?>? metadata,
  String state = 'present',
  String createdAt = '2026-08-01T08:00:00Z',
  String updatedAt = '2026-08-14T08:00:00Z',
  String? deletedAt,
}) {
  return {
    'id': id,
    'scope': scope,
    'business_id': businessId,
    'product_id': productId,
    'master_product_id': masterProductId,
    'barcode': barcode,
    'barcode_normalized': barcodeNormalized,
    'barcode_type': barcodeType,
    'is_primary': isPrimary,
    'status': status,
    'source': source,
    'confidence_score': confidenceScore,
    'version': version,
    'metadata': metadata,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
    '_bootstrap_record_state': state,
  };
}

Map<String, Object?> bootstrapDatasetPage({
  required String dataset,
  List<Map<String, Object?>> rows = const [],
  bool hasMore = false,
  String? nextPageToken,
  int pageSize = 1000,
}) {
  return {
    'dataset': dataset,
    'rows': rows,
    'count': rows.length,
    'has_more': hasMore,
    'complete': !hasMore,
    'authoritative_scope_complete': !hasMore,
    'page_size': pageSize,
    'next_page_token': nextPageToken,
  };
}

List<Map<String, Object?>> bootstrapRows(
  String prefix,
  int count, {
  String state = 'present',
}) {
  return List.generate(
    count,
    (index) => {
      'id': '$prefix-$index',
      '_bootstrap_record_state': state,
    },
  );
}

Map<String, Object?> bootstrapCoreRpcResponse({
  String snapshotId = 'core-snapshot-1',
  String profileId = 'profile-a',
  String businessId = 'business-a',
  String branchId = 'branch-x',
  String appDeviceId = 'device-a',
  List<String> permissions = const [
    'inventory.read',
    'products.read',
    'sales.create',
  ],
  List<Map<String, Object?>>? memberships,
  List<Map<String, Object?>>? roles,
  bool hasMore = false,
  String? nextPageToken,
  String authorizationValidatedAt = '2026-08-15T10:00:00Z',
}) {
  final resolvedMemberships = memberships ??
      [
        {
          'id': 'membership-business',
          'business_id': businessId,
          'profile_id': profileId,
          'branch_id': null,
          'role_id': 'role-cashier',
          'status': 'active',
          'created_at': '2026-08-01T08:00:00Z',
          'updated_at': '2026-08-01T08:00:00Z',
          'deleted_at': null,
        },
        {
          'id': 'membership-branch',
          'business_id': businessId,
          'profile_id': profileId,
          'branch_id': branchId,
          'role_id': 'role-inventory',
          'status': 'active',
          'created_at': '2026-08-02T08:00:00Z',
          'updated_at': '2026-08-02T08:00:00Z',
          'deleted_at': null,
        },
      ];
  final resolvedRoles = roles ??
      [
        {
          'role_id': 'role-cashier',
          'role_name': 'cashier',
          'business_id': null,
          'is_system_role': true,
        },
        {
          'role_id': 'role-inventory',
          'role_name': 'inventory_operator',
          'business_id': businessId,
          'is_system_role': false,
        },
      ];
  return bootstrapRpcResponse(
    snapshotId: snapshotId,
    profileId: profileId,
    businessId: businessId,
    branchId: branchId,
    appDeviceId: appDeviceId,
    bundle: 'core',
    datasetRequested: null,
    authorizationValidatedAt: authorizationValidatedAt,
    datasets: {
      'context': bootstrapDatasetPage(
        dataset: 'context',
        hasMore: hasMore,
        nextPageToken: nextPageToken,
        rows: [
          {
            'profile_id': profileId,
            'business': {
              'id': businessId,
              'name': 'Business A',
              'business_type': 'retail',
              'owner_name': 'Owner A',
              'phone': '+570000000',
              'email': 'business-a@example.test',
              'address': 'Address A',
              'subscription_plan': 'free',
              'status': 'active',
              'created_at': '2026-08-01T08:00:00Z',
              'updated_at': '2026-08-14T08:00:00Z',
              'deleted_at': null,
            },
            'branch': {
              'id': branchId,
              'business_id': businessId,
              'name': 'Branch X',
              'address': 'Branch address',
              'phone': '+571111111',
              'status': 'active',
              'created_at': '2026-08-01T08:00:00Z',
              'updated_at': '2026-08-14T08:00:00Z',
              'deleted_at': null,
            },
            'app_device': {
              'id': appDeviceId,
              'business_id': businessId,
              'branch_id': branchId,
              'profile_id': profileId,
              'status': 'active',
            },
            'memberships': resolvedMemberships,
            'effective_roles': resolvedRoles,
            'effective_permissions': permissions,
            'authorization_validated_at': authorizationValidatedAt,
          },
        ],
      ),
    },
  );
}
