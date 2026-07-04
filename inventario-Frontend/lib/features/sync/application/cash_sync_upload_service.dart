import '../../../core/logging/app_logger.dart';
import '../../cash/data/datasources/cash_session_local_dao.dart';
import '../data/datasources/cash_sync_remote_datasource.dart';
import '../data/models/catalog_upload_models.dart';
import 'local_sync_outbox_service.dart';

class CashSyncUploadService {
  CashSyncUploadService({
    required LocalSyncOutboxService outboxService,
    required CashSyncRemoteDataSource remoteDataSource,
    required CashSessionLocalDao cashSessionLocalDao,
  })  : _outboxService = outboxService,
        _remoteDataSource = remoteDataSource,
        _cashSessionLocalDao = cashSessionLocalDao;

  final LocalSyncOutboxService _outboxService;
  final CashSyncRemoteDataSource _remoteDataSource;
  final CashSessionLocalDao _cashSessionLocalDao;

  Future<CatalogUploadRunResult> uploadPendingCashBatches({
    required String businessId,
    int batchLimit = 10,
  }) async {
    await _cashSessionLocalDao.resetRetryableCashOutboxBatches(
      businessId: businessId,
    );

    await _cashSessionLocalDao.reconcileCompletedCashFromOutbox(
      businessId: businessId,
    );

    final pendingBatches = await _outboxService.getPendingCashBatches(
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

        final result = await _remoteDataSource.uploadAndProcessCashBatch(
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

          await _markLocalCashSynced(mutations: mutations);
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
          'Cash batch uploaded: local=$localBatchId '
          'server=${result.serverBatchId} status=${result.status}',
        );
      } catch (error, stackTrace) {
        failed++;

        await _outboxService.markBatchError(
          localBatchId: localBatchId,
          error: error,
        );

        AppLogger.error(
          'Cash batch upload failed: $localBatchId',
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

  Future<void> _markLocalCashSynced({
    required List<Map<String, dynamic>> mutations,
  }) async {
    for (final mutation in mutations) {
      final entityTable = mutation['entity_table']?.toString();
      final entityId = mutation['entity_id']?.toString();

      if (entityId == null || entityId.trim().isEmpty) {
        continue;
      }

      if (entityTable == 'cash_registers') {
        await _cashSessionLocalDao.markCashRegisterSyncedAfterUpload(
          id: entityId,
        );
      } else if (entityTable == 'cash_sessions') {
        await _cashSessionLocalDao.markCashSessionSyncedAfterUpload(
          id: entityId,
        );
      }
    }
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
          errorCode: 'remote_cash_batch_partial',
          errorMessage:
              'El batch remoto de cash quedó partial. Revisar sync_conflicts en servidor.',
        );
      }

      return;
    }

    if (result.errorCount > 0) {
      for (final mutation in mutations) {
        await _outboxService.markMutationError(
          localMutationId: _requiredString(mutation, 'id'),
          errorCode: 'remote_cash_batch_error',
          error: 'El batch remoto de cash reportó errores.',
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
