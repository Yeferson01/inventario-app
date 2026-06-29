import '../../../core/logging/app_logger.dart';
import '../data/datasources/inventory_sync_remote_datasource.dart';
import '../data/models/catalog_upload_models.dart';
import 'local_sync_outbox_service.dart';

class InventorySyncUploadService {
  InventorySyncUploadService({
    required LocalSyncOutboxService outboxService,
    required InventorySyncRemoteDataSource remoteDataSource,
  })  : _outboxService = outboxService,
        _remoteDataSource = remoteDataSource;

  final LocalSyncOutboxService _outboxService;
  final InventorySyncRemoteDataSource _remoteDataSource;

  Future<CatalogUploadRunResult> uploadPendingInventoryBatches({
    required String businessId,
    int batchLimit = 10,
  }) async {
    final pendingBatches = await _outboxService.getPendingInventoryBatches(
      businessId: businessId,
      limit: batchLimit,
    );

    var uploaded = 0;
    var completed = 0;
    var partial = 0;
    var failed = 0;
    var mutationsUploaded = 0;

    for (final batch in pendingBatches) {
      final localBatchId = _requiredString(batch, 'id');

      try {
        await _outboxService.markBatchUploading(localBatchId);

        final mutations =
            await _outboxService.getMutationsForBatch(localBatchId);

        final result = await _remoteDataSource.uploadAndProcessInventoryBatch(
          localBatch: batch,
          localMutations: mutations,
        );

        uploaded++;
        mutationsUploaded += result.mutationCount;

        if (result.completed) {
          completed++;

          await _outboxService.markBatchCompleted(
            localBatchId: localBatchId,
            serverSyncBatchId: result.serverBatchId,
            appliedCount: result.appliedCount,
            skippedCount: result.skippedCount,
            conflictCount: result.conflictCount,
            errorCount: result.errorCount,
          );

          await _markBatchMutationsApplied(mutations: mutations);
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
          'Inventory batch uploaded: local=$localBatchId '
          'server=${result.serverBatchId} status=${result.status}',
        );
      } catch (error, stackTrace) {
        failed++;

        await _outboxService.markBatchError(
          localBatchId: localBatchId,
          error: error,
        );

        AppLogger.error(
          'Inventory batch upload failed: $localBatchId',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    return CatalogUploadRunResult(
      batchesChecked: pendingBatches.length,
      batchesUploaded: uploaded,
      batchesCompleted: completed,
      batchesPartial: partial,
      batchesFailed: failed,
      mutationsUploaded: mutationsUploaded,
    );
  }

  Future<void> _markBatchMutationsApplied({
    required List<Map<String, dynamic>> mutations,
  }) async {
    for (final mutation in mutations) {
      final localMutationId = _requiredString(mutation, 'id');

      await _outboxService.markMutationApplied(
        localMutationId: localMutationId,
      );
    }
  }

  Future<void> _markBatchMutationsPartial({
    required List<Map<String, dynamic>> mutations,
    required CatalogUploadBatchResult result,
  }) async {
    if (result.conflictCount > 0) {
      for (final mutation in mutations) {
        final localMutationId = _requiredString(mutation, 'id');

        await _outboxService.markMutationConflict(
          localMutationId: localMutationId,
          errorCode: 'remote_inventory_batch_partial',
          errorMessage:
              'El batch remoto de inventario quedó partial. Revisar sync_conflicts en servidor.',
        );
      }

      return;
    }

    if (result.errorCount > 0) {
      for (final mutation in mutations) {
        final localMutationId = _requiredString(mutation, 'id');

        await _outboxService.markMutationError(
          localMutationId: localMutationId,
          errorCode: 'remote_inventory_batch_error',
          error: 'El batch remoto de inventario reportó errores.',
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
