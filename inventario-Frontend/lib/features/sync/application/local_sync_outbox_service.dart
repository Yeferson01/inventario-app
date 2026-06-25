import '../../../core/utils/app_uuid.dart';
import '../data/datasources/local_sync_outbox_dao.dart';
import '../data/models/local_sync_outbox_models.dart';

class LocalSyncOutboxService {
  LocalSyncOutboxService(this._dao);

  final LocalSyncOutboxDao _dao;

  Future<LocalSyncEnqueueResult> enqueueCatalogMutations({
    required String businessId,
    required List<LocalSyncMutationDraft> mutations,
    String? branchId,
    String? appDeviceId,
    String? profileId,
    String? deviceInstallationId,
    Map<String, dynamic>? metadata,
  }) {
    return enqueueUploadBatch(
      businessId: businessId,
      domain: 'catalog',
      mutations: mutations,
      branchId: branchId,
      appDeviceId: appDeviceId,
      profileId: profileId,
      deviceInstallationId: deviceInstallationId,
      metadata: metadata,
    );
  }

  Future<LocalSyncEnqueueResult> enqueueUploadBatch({
    required String businessId,
    required String domain,
    required List<LocalSyncMutationDraft> mutations,
    String? branchId,
    String? appDeviceId,
    String? profileId,
    String? deviceInstallationId,
    Map<String, dynamic>? metadata,
  }) {
    _validateDomain(domain);
    _validateMutations(mutations);

    final installationId = deviceInstallationId?.trim().isNotEmpty == true
        ? deviceInstallationId!.trim()
        : 'local-device';

    final clientBatchId =
        '$installationId:batch:${DateTime.now().toUtc().microsecondsSinceEpoch}:${AppUuid.v7()}';

    return _dao.enqueueUploadBatch(
      businessId: businessId,
      domain: domain,
      clientBatchId: clientBatchId,
      mutations: mutations,
      branchId: branchId,
      appDeviceId: appDeviceId,
      profileId: profileId,
      metadata: {
        'source': 'flutter_local_outbox',
        if (metadata != null) ...metadata,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getPendingCatalogBatches({
    required String businessId,
    int limit = 20,
  }) {
    return _dao.getPendingBatches(
      businessId: businessId,
      domain: 'catalog',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingBatches({
    required String businessId,
    String? domain,
    int limit = 20,
  }) {
    return _dao.getPendingBatches(
      businessId: businessId,
      domain: domain,
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getMutationsForBatch(
    String localBatchId,
  ) {
    return _dao.getMutationsForBatch(localBatchId);
  }

  Future<int> countPendingMutations({
    required String businessId,
    String? domain,
  }) {
    return _dao.countPendingMutations(
      businessId: businessId,
      domain: domain,
    );
  }

  Future<void> markBatchUploading(String localBatchId) {
    return _dao.markBatchUploading(localBatchId);
  }

  Future<void> markBatchCompleted({
    required String localBatchId,
    String? serverSyncBatchId,
    int? appliedCount,
    int? skippedCount,
    int? conflictCount,
    int? errorCount,
  }) {
    return _dao.markBatchCompleted(
      localBatchId: localBatchId,
      serverSyncBatchId: serverSyncBatchId,
      appliedCount: appliedCount,
      skippedCount: skippedCount,
      conflictCount: conflictCount,
      errorCount: errorCount,
    );
  }

  Future<void> markBatchPartial({
    required String localBatchId,
    String? serverSyncBatchId,
    int? appliedCount,
    int? skippedCount,
    int? conflictCount,
    int? errorCount,
  }) {
    return _dao.markBatchPartial(
      localBatchId: localBatchId,
      serverSyncBatchId: serverSyncBatchId,
      appliedCount: appliedCount,
      skippedCount: skippedCount,
      conflictCount: conflictCount,
      errorCount: errorCount,
    );
  }

  Future<void> markBatchError({
    required String localBatchId,
    required Object error,
  }) {
    return _dao.markBatchError(
      localBatchId: localBatchId,
      error: error,
    );
  }

  void _validateDomain(String domain) {
    const allowedDomains = {
      'catalog',
      'pos',
      'purchases',
    };

    if (!allowedDomains.contains(domain)) {
      throw ArgumentError('Dominio de sync no soportado: $domain');
    }
  }

  void _validateMutations(List<LocalSyncMutationDraft> mutations) {
    if (mutations.isEmpty) {
      throw ArgumentError('No hay mutaciones para encolar.');
    }

    final idempotencyKeys = <String>{};
    final clientMutationIds = <String>{};

    for (final mutation in mutations) {
      if (!idempotencyKeys.add(mutation.idempotencyKey)) {
        throw ArgumentError(
          'idempotency_key duplicado en batch local: ${mutation.idempotencyKey}',
        );
      }

      if (!clientMutationIds.add(mutation.clientMutationId)) {
        throw ArgumentError(
          'client_mutation_id duplicado en batch local: ${mutation.clientMutationId}',
        );
      }
    }
  }
}
