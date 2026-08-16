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
    'snapshot_at': '2026-08-15T09:00:00Z',
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
