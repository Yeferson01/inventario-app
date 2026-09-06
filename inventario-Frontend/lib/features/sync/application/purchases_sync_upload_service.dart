import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../../inventory/data/datasources/purchase_local_dao.dart';
import '../data/datasources/purchases_sync_remote_datasource.dart';
import '../data/models/catalog_upload_models.dart';
import 'local_sync_outbox_service.dart';
import 'purchase_product_dependency_resolver.dart';
import 'purchases_sync_upload_models.dart';

class PurchasesSyncUploadService {
  PurchasesSyncUploadService({
    required LocalSyncOutboxService outboxService,
    required PurchasesSyncRemoteDataSource remoteDataSource,
    required PurchaseLocalDao purchaseLocalDao,
    required PurchaseProductDependencyResolver dependencyResolver,
  })  : _outboxService = outboxService,
        _remoteDataSource = remoteDataSource,
        _purchaseLocalDao = purchaseLocalDao,
        _dependencyResolver = dependencyResolver;

  final LocalSyncOutboxService _outboxService;
  final PurchasesSyncRemoteDataSource _remoteDataSource;
  final PurchaseLocalDao _purchaseLocalDao;
  final PurchaseProductDependencyResolver _dependencyResolver;

  Future<PurchasesSyncUploadRunResult> uploadPendingPurchasesBatches({
    required String businessId,
    String? branchId,
    int batchLimit = 10,
    Set<String>? onlyLocalBatchIds,
  }) async {
    await _purchaseLocalDao.reconcileCompletedPurchasesFromOutbox(
      businessId: businessId,
    );

    final allPendingBatches = await _outboxService.getPendingPurchasesBatches(
      businessId: businessId,
      branchId: branchId,
      limit: batchLimit,
    );
    final pendingBatches = onlyLocalBatchIds == null
        ? allPendingBatches
        : allPendingBatches
            .where((batch) => onlyLocalBatchIds.contains(batch['id']))
            .toList(growable: false);

    var uploaded = 0;
    var completed = 0;
    var partial = 0;
    var failed = 0;
    var mutationsUploaded = 0;
    var waitingForDependencies = 0;
    var blockedByDependencies = 0;
    final waitingProductIds = <String>{};
    final blockedProductIds = <String>{};
    final dependencyIssues = <PurchaseProductDependencyIssue>[];

    for (final batch in pendingBatches) {
      final localBatchId = _requiredString(batch, 'id');

      try {
        final mutations =
            await _outboxService.getMutationsForBatch(localBatchId);
        final dependencyResolution = await _dependencyResolver.resolve(
          businessId: businessId,
          purchaseMutations: mutations,
        );

        if (dependencyResolution.status ==
            PurchaseProductDependencyStatus.waiting) {
          waitingForDependencies++;
          waitingProductIds.addAll(dependencyResolution.waitingProductIds);
          AppLogger.info(
            'Purchases batch deferred while Product dependencies are pending: '
            'local=$localBatchId products=${dependencyResolution.waitingProductIds.join(',')}',
          );
          continue;
        }

        if (dependencyResolution.status ==
            PurchaseProductDependencyStatus.blocked) {
          blockedByDependencies++;
          blockedProductIds.addAll(dependencyResolution.blockedProductIds);
          dependencyIssues.addAll(dependencyResolution.issues);
          AppLogger.warning(
            'Purchases batch blocked by Product dependencies: '
            'local=$localBatchId products=${dependencyResolution.blockedProductIds.join(',')}',
          );
          continue;
        }

        await _outboxService.markBatchUploading(localBatchId);

        final allRemoteEntitiesAlreadyExist =
            await _remoteDataSource.allPurchaseMutationEntitiesAlreadyExist(
          localMutations: mutations,
        );

        if (allRemoteEntitiesAlreadyExist) {
          uploaded++;
          completed++;
          mutationsUploaded += mutations.length;

          await _outboxService.markBatchCompleted(
            localBatchId: localBatchId,
            appliedCount: mutations.length,
            skippedCount: 0,
            conflictCount: 0,
            errorCount: 0,
          );

          await _markBatchMutationsApplied(
            mutations: mutations,
          );

          await _markPurchasesSyncedFromMutations(
            mutations: mutations,
          );

          AppLogger.info(
            'Purchases batch completed idempotently without upload: '
            'local=$localBatchId status=completed_remote_already_exists',
          );

          continue;
        }

        final result = await _remoteDataSource.uploadAndProcessPurchasesBatch(
          localBatch: batch,
          localMutations: mutations,
        );

        uploaded++;
        mutationsUploaded += result.mutationCount;

        var duplicateConflictsAreIdempotent = false;

        if (!result.completed && result.conflictCount > 0) {
          duplicateConflictsAreIdempotent =
              await _remoteDataSource.duplicatePurchasesConflictsAreIdempotent(
            serverBatchId: result.serverBatchId,
            localMutations: mutations,
          );
        }

        if (result.completed || duplicateConflictsAreIdempotent) {
          completed++;

          await _outboxService.markBatchCompleted(
            localBatchId: localBatchId,
            serverSyncBatchId: result.serverBatchId,
            appliedCount: result.appliedCount,
            skippedCount: result.skippedCount +
                (duplicateConflictsAreIdempotent ? result.conflictCount : 0),
            conflictCount:
                duplicateConflictsAreIdempotent ? 0 : result.conflictCount,
            errorCount: duplicateConflictsAreIdempotent ? 0 : result.errorCount,
          );

          await _markBatchMutationsApplied(
            mutations: mutations,
          );

          await _markPurchasesSyncedFromMutations(
            mutations: mutations,
          );
        } else {
          partial++;

          await _outboxService.markBatchPartial(
            localBatchId: localBatchId,
            serverSyncBatchId: result.serverBatchId,
            appliedCount: result.appliedCount,
            skippedCount: result.skippedCount,
            conflictCount: result.conflictCount,
            errorCount: result.errorCount,
          );

          await _markBatchMutationsPartial(
            mutations: mutations,
            result: result,
          );
        }

        AppLogger.info(
          'Purchases batch uploaded: local=$localBatchId '
          'server=${result.serverBatchId} status=${duplicateConflictsAreIdempotent ? 'completed_idempotent_duplicate' : result.status}',
        );
      } catch (error, stackTrace) {
        failed++;

        await _outboxService.markBatchError(
          localBatchId: localBatchId,
          error: error,
        );

        AppLogger.error(
          'Purchases batch upload failed: $localBatchId',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    final sortedWaitingProductIds = waitingProductIds.toList()..sort();
    final sortedBlockedProductIds = blockedProductIds.toList()..sort();

    return PurchasesSyncUploadRunResult(
      batchesChecked: pendingBatches.length,
      batchesUploaded: uploaded,
      batchesCompleted: completed,
      batchesPartial: partial,
      batchesFailed: failed,
      mutationsUploaded: mutationsUploaded,
      batchesWaitingForDependencies: waitingForDependencies,
      batchesBlockedByDependencies: blockedByDependencies,
      waitingProductIds: List.unmodifiable(sortedWaitingProductIds),
      blockedProductIds: List.unmodifiable(sortedBlockedProductIds),
      dependencyIssues: List.unmodifiable(dependencyIssues),
    );
  }

  Future<void> _markPurchasesSyncedFromMutations({
    required List<Map<String, dynamic>> mutations,
  }) async {
    final purchaseIds = _purchaseIdsFromMutations(mutations);

    for (final purchaseId in purchaseIds) {
      await _purchaseLocalDao.markPurchaseAndChildrenSyncedAfterUpload(
        purchaseId: purchaseId,
      );
    }
  }

  Set<String> _purchaseIdsFromMutations(
    List<Map<String, dynamic>> mutations,
  ) {
    final purchaseIds = <String>{};

    for (final mutation in mutations) {
      final entityTable = mutation['entity_table']?.toString();
      final entityId = mutation['entity_id']?.toString();

      if (entityTable == 'purchases' &&
          entityId != null &&
          entityId.trim().isNotEmpty) {
        purchaseIds.add(entityId.trim());
        continue;
      }

      if (entityTable == 'purchase_items') {
        final payload = _decodeMutationPayload(mutation);
        final purchaseId = payload['purchase_id']?.toString();

        if (purchaseId != null && purchaseId.trim().isNotEmpty) {
          purchaseIds.add(purchaseId.trim());
        }
      }
    }

    return purchaseIds;
  }

  Map<String, dynamic> _decodeMutationPayload(
    Map<String, dynamic> mutation,
  ) {
    final raw = mutation['payload_json'] ?? mutation['payload'];

    if (raw is Map<String, dynamic>) {
      return raw;
    }

    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);

        if (decoded is Map<String, dynamic>) {
          return decoded;
        }

        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return {};
      }
    }

    return {};
  }

  Future<void> _markBatchMutationsApplied({
    required List<Map<String, dynamic>> mutations,
  }) async {
    for (final mutation in mutations) {
      await _outboxService.markMutationApplied(
        localMutationId: _requiredString(mutation, 'id'),
      );
    }
  }

  Future<void> _markBatchMutationsPartial({
    required List<Map<String, dynamic>> mutations,
    required CatalogUploadBatchResult result,
  }) async {
    if (result.conflictCount > 0) {
      for (final mutation in mutations) {
        await _outboxService.markMutationConflict(
          localMutationId: _requiredString(mutation, 'id'),
          errorCode: 'remote_purchases_batch_partial',
          errorMessage:
              'El batch remoto de compras quedó partial. Revisar sync_conflicts en servidor.',
        );
      }

      return;
    }

    if (result.errorCount > 0) {
      for (final mutation in mutations) {
        await _outboxService.markMutationError(
          localMutationId: _requiredString(mutation, 'id'),
          errorCode: 'remote_purchases_batch_error',
          error: 'El batch remoto de compras reportó errores.',
        );
      }

      return;
    }

    await _markBatchMutationsApplied(mutations: mutations);
  }

  String _requiredString(Map<String, dynamic> source, String key) {
    final value = source[key];

    if (value == null || value.toString().trim().isEmpty) {
      throw ArgumentError('Campo requerido ausente: $key');
    }

    return value.toString();
  }
}
