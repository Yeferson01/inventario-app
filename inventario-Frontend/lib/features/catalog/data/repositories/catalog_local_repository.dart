import '../datasources/catalog_local_dao.dart';
import '../models/catalog_local_models.dart';

abstract interface class CatalogSyncLocalStore {
  Future<void> markCatalogSyncStarted(String businessId);

  Future<Map<String, dynamic>?> getCatalogSyncState(String businessId);

  Future<CatalogDeltaApplyResult> applyCatalogDeltaPage({
    required String businessId,
    required List<Map<String, dynamic>> records,
    required DateTime? committedSince,
    required DateTime windowUpperBound,
    required int? catalogVersion,
    required Map<String, dynamic>? pageToken,
    required bool completed,
    required bool isSyncing,
  });

  Future<void> resetCatalogSyncResume({
    required String businessId,
    required bool clearCommittedCursor,
  });

  Future<void> markCatalogSyncFailed({
    required String businessId,
    required Object error,
  });
}

class CatalogLocalRepository implements CatalogSyncLocalStore {
  CatalogLocalRepository(this._dao);

  final CatalogLocalDao _dao;

  Future<LocalBarcodeLookupResult> lookupByBarcode({
    required String businessId,
    required String barcode,
    bool allowMasterMatch = true,
  }) {
    return _dao.lookupByBarcode(
      businessId: businessId,
      barcode: barcode,
      allowMasterMatch: allowMasterMatch,
    );
  }

  Future<CatalogDeltaApplyResult> applyCatalogDeltaResponse(
    Map<String, dynamic> response,
  ) {
    final rawRecords = response['records'];

    final records = <Map<String, dynamic>>[];

    if (rawRecords is List) {
      for (final item in rawRecords) {
        if (item is Map<String, dynamic>) {
          records.add(item);
        } else if (item is Map) {
          records.add(Map<String, dynamic>.from(item));
        }
      }
    }

    return _dao.applyCatalogDeltaRecords(records);
  }

  @override
  Future<CatalogDeltaApplyResult> applyCatalogDeltaPage({
    required String businessId,
    required List<Map<String, dynamic>> records,
    required DateTime? committedSince,
    required DateTime windowUpperBound,
    required int? catalogVersion,
    required Map<String, dynamic>? pageToken,
    required bool completed,
    required bool isSyncing,
  }) {
    return _dao.applyCatalogDeltaPage(
      businessId: businessId,
      records: records,
      committedSince: committedSince,
      windowUpperBound: windowUpperBound,
      catalogVersion: catalogVersion,
      pageToken: pageToken,
      completed: completed,
      isSyncing: isSyncing,
    );
  }

  @override
  Future<void> markCatalogSyncStarted(String businessId) {
    return _dao.markCatalogSyncStarted(businessId);
  }

  @override
  Future<void> markCatalogSyncFailed({
    required String businessId,
    required Object error,
  }) {
    return _dao.markCatalogSyncFailed(
      businessId: businessId,
      error: error,
    );
  }

  @override
  Future<Map<String, dynamic>?> getCatalogSyncState(String businessId) {
    return _dao.getCatalogSyncState(businessId);
  }

  @override
  Future<void> resetCatalogSyncResume({
    required String businessId,
    required bool clearCommittedCursor,
  }) {
    return _dao.resetCatalogSyncResume(
      businessId: businessId,
      clearCommittedCursor: clearCommittedCursor,
    );
  }

  Future<String> queueContribution({
    required String businessId,
    required String contributionType,
    String? branchId,
    String? localProductId,
    String? masterProductId,
    String? barcode,
    String? barcodeType,
    String? suggestedName,
    String? suggestedBrand,
    String? suggestedManufacturer,
    String? suggestedCategoryName,
    String? suggestedSubcategoryName,
    double? suggestedPackageSize,
    String? suggestedPackageUnit,
    String? suggestedUnitType,
    String? suggestedImageUrl,
    String? suggestedImageThumbUrl,
    String? suggestedImageHash,
    String source = 'app',
    double? confidenceScore,
    Map<String, dynamic>? metadata,
  }) {
    return _dao.queueContribution(
      businessId: businessId,
      contributionType: contributionType,
      branchId: branchId,
      localProductId: localProductId,
      masterProductId: masterProductId,
      barcode: barcode,
      barcodeType: barcodeType,
      suggestedName: suggestedName,
      suggestedBrand: suggestedBrand,
      suggestedManufacturer: suggestedManufacturer,
      suggestedCategoryName: suggestedCategoryName,
      suggestedSubcategoryName: suggestedSubcategoryName,
      suggestedPackageSize: suggestedPackageSize,
      suggestedPackageUnit: suggestedPackageUnit,
      suggestedUnitType: suggestedUnitType,
      suggestedImageUrl: suggestedImageUrl,
      suggestedImageThumbUrl: suggestedImageThumbUrl,
      suggestedImageHash: suggestedImageHash,
      source: source,
      confidenceScore: confidenceScore,
      metadata: metadata,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingContributions({
    required String businessId,
    int limit = 100,
  }) {
    return _dao.getPendingContributions(
      businessId: businessId,
      limit: limit,
    );
  }

  Future<void> markContributionSynced({
    required String localContributionId,
    required String serverContributionId,
  }) {
    return _dao.markContributionSynced(
      localContributionId: localContributionId,
      serverContributionId: serverContributionId,
    );
  }

  Future<void> markContributionError({
    required String localContributionId,
    required Object error,
  }) {
    return _dao.markContributionError(
      localContributionId: localContributionId,
      error: error,
    );
  }
}
