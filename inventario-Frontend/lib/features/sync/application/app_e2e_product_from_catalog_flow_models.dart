class AppE2EProductFromCatalogFlowInput {
  const AppE2EProductFromCatalogFlowInput({
    required this.profileId,
    required this.isOnline,
    required this.salePrice,
    this.purchasePrice = 0,
    this.preferredBusinessId,
    this.preferredBranchId,
    this.lastSyncStatus,
    this.runManualSyncAfterCreate = true,
    this.deviceName,
    this.platform,
    this.appVersion,
    this.osVersion,
    this.metadata,
  });

  final String profileId;
  final bool isOnline;

  final String? preferredBusinessId;
  final String? preferredBranchId;
  final String? lastSyncStatus;

  final double salePrice;
  final double purchasePrice;

  final bool runManualSyncAfterCreate;

  final String? deviceName;
  final String? platform;
  final String? appVersion;
  final String? osVersion;

  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() {
    return {
      'profile_id': profileId,
      'is_online': isOnline,
      'preferred_business_id': preferredBusinessId,
      'preferred_branch_id': preferredBranchId,
      'last_sync_status': lastSyncStatus,
      'sale_price': salePrice,
      'purchase_price': purchasePrice,
      'run_manual_sync_after_create': runManualSyncAfterCreate,
      'device_name': deviceName,
      'platform': platform,
      'app_version': appVersion,
      'os_version': osVersion,
      'metadata': metadata,
    };
  }
}

class AppE2EProductFromCatalogFlowResult {
  const AppE2EProductFromCatalogFlowResult({
    required this.installationId,
    required this.businessId,
    required this.branchId,
    required this.profileId,
    required this.catalogCandidate,
    required this.creationResult,
    required this.didRunManualSyncAfterCreate,
    this.appDeviceId,
    this.postCreateSyncResult,
  });

  final String installationId;
  final String businessId;
  final String? branchId;
  final String profileId;
  final String? appDeviceId;

  final Map<String, dynamic> catalogCandidate;
  final Map<String, dynamic> creationResult;

  final bool didRunManualSyncAfterCreate;
  final Map<String, dynamic>? postCreateSyncResult;

  Map<String, dynamic> toJson() {
    return {
      'installation_id': installationId,
      'business_id': businessId,
      'branch_id': branchId,
      'profile_id': profileId,
      'app_device_id': appDeviceId,
      'catalog_candidate': catalogCandidate,
      'creation_result': creationResult,
      'did_run_manual_sync_after_create': didRunManualSyncAfterCreate,
      'post_create_sync_result': postCreateSyncResult,
    };
  }
}
