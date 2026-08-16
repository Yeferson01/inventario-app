import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../../cash/data/datasources/cash_session_local_dao.dart';
import '../../sales/data/datasources/pos_local_sale_dao.dart';
import '../data/datasources/pos_sync_remote_datasource.dart';
import '../data/models/catalog_upload_models.dart';
import 'local_sync_outbox_service.dart';

class PosSyncUploadService {
  PosSyncUploadService({
    required LocalSyncOutboxService outboxService,
    required PosSyncRemoteDataSource remoteDataSource,
    required PosLocalSaleDao posLocalSaleDao,
    required CashSessionLocalDao cashSessionLocalDao,
  })  : _outboxService = outboxService,
        _remoteDataSource = remoteDataSource,
        _posLocalSaleDao = posLocalSaleDao,
        _cashSessionLocalDao = cashSessionLocalDao;

  final LocalSyncOutboxService _outboxService;
  final PosSyncRemoteDataSource _remoteDataSource;
  final CashSessionLocalDao _cashSessionLocalDao;
  final PosLocalSaleDao _posLocalSaleDao;

  Future<CatalogUploadRunResult> uploadPendingPosBatches({
    required String businessId,
    String? branchId,
    int batchLimit = 10,
  }) async {
    await _posLocalSaleDao.reconcileCompletedPosSalesFromOutbox(
      businessId: businessId,
    );

    final pendingBatches = await _outboxService.getPendingPosBatches(
      businessId: businessId,
      branchId: branchId,
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
        final mutations =
            await _outboxService.getMutationsForBatch(localBatchId);

        if (mutations.isEmpty) {
          completed++;

          await _outboxService.markBatchCompleted(
            localBatchId: localBatchId,
            serverSyncBatchId: localBatchId,
            appliedCount: 0,
            skippedCount: 0,
            conflictCount: 0,
            errorCount: 0,
          );

          AppLogger.info(
            'POS empty batch archived locally: local=$localBatchId',
          );

          continue;
        }

        final remoteEntitiesAlreadyExist =
            await _remoteDataSource.allPosMutationEntitiesAlreadyExist(
          localMutations: mutations,
        );

        if (remoteEntitiesAlreadyExist) {
          completed++;

          await _outboxService.markBatchCompleted(
            localBatchId: localBatchId,
            serverSyncBatchId: localBatchId,
            appliedCount: mutations.length,
            skippedCount: 0,
            conflictCount: 0,
            errorCount: 0,
          );

          await _markBatchMutationsApplied(mutations: mutations);
          await _markLocalPosEntitiesSynced(mutations: mutations);

          AppLogger.info(
            'POS batch already exists on server; archived locally: '
            'local=$localBatchId mutations=${mutations.length}',
          );

          continue;
        }

        await _assertCashReadyForPosBatch(batch, mutations);

        await _outboxService.markBatchUploading(localBatchId);

        final result = await _remoteDataSource.uploadAndProcessPosBatch(
          localBatch: batch,
          localMutations: mutations,
        );

        uploaded++;
        mutationsUploaded += result.mutationCount;

        final duplicateConflictsAreIdempotent =
            await _duplicateConflictsAreIdempotent(result);

        final canTreatAsCompleted = result.completed ||
            duplicateConflictsAreIdempotent ||
            (result.errorCount == 0 &&
                result.conflictCount == 0 &&
                result.appliedCount + result.skippedCount >=
                    result.mutationCount);

        if (canTreatAsCompleted) {
          completed++;

          if (!result.completed) {
            AppLogger.info(
              'POS partial treated as completed: '
              'server=${result.serverBatchId} '
              'applied=${result.appliedCount} '
              'skipped=${result.skippedCount} '
              'conflicts=${result.conflictCount} '
              'errors=${result.errorCount}',
            );
          }

          await _outboxService.markBatchCompleted(
            localBatchId: localBatchId,
            serverSyncBatchId: result.serverBatchId,
            appliedCount: result.appliedCount,
            skippedCount: result.skippedCount,
            conflictCount: result.conflictCount,
            errorCount: result.errorCount,
          );

          await _markBatchMutationsApplied(mutations: mutations);

          await _markLocalPosEntitiesSynced(mutations: mutations);
        } else {
          partial++;

          AppLogger.info(
            'POS batch partial detail: '
            'local=$localBatchId '
            'server=${result.serverBatchId} '
            'status=${result.status} '
            'mutation_count=${result.mutationCount} '
            'applied=${result.appliedCount} '
            'skipped=${result.skippedCount} '
            'conflicts=${result.conflictCount} '
            'errors=${result.errorCount}',
          );

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
          'POS batch uploaded: local=$localBatchId '
          'server=${result.serverBatchId} status=${result.status}',
        );
      } catch (error, stackTrace) {
        failed++;

        await _outboxService.markBatchError(
          localBatchId: localBatchId,
          error: error,
        );

        AppLogger.error(
          'POS batch upload failed: $localBatchId',
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

  Future<bool> _duplicateConflictsAreIdempotent(
    CatalogUploadBatchResult result,
  ) async {
    if (result.completed) {
      return false;
    }

    if (result.errorCount != 0 || result.conflictCount <= 0) {
      return false;
    }

    final accounted =
        result.appliedCount + result.skippedCount + result.conflictCount;

    if (accounted < result.mutationCount) {
      return false;
    }

    final serverMutations =
        await _remoteDataSource.getServerBatchMutationStatuses(
      serverBatchId: result.serverBatchId,
    );

    if (serverMutations.isEmpty) {
      return false;
    }

    return serverMutations.every((mutation) {
      final status = mutation['status']?.toString();
      final errorCode = mutation['error_code']?.toString();

      if (status == 'applied' || status == 'skipped') {
        return true;
      }

      return status == 'conflict' && errorCode == 'duplicate_key';
    });
  }

  Future<void> _assertCashReadyForPosBatch(
    Map<String, dynamic> batch,
    List<Map<String, dynamic>> mutations,
  ) async {
    final saleMutations = mutations.where((mutation) {
      return mutation['entity_table']?.toString() == 'sales';
    }).toList();

    if (saleMutations.isEmpty) {
      return;
    }

    final businessId = _requiredString(batch, 'business_id');
    final branchId = _requiredString(batch, 'branch_id');

    final allSalesHaveCashContext = saleMutations.every((mutation) {
      final payload = _posUploadPayloadMap(
        mutation['payload'] ?? mutation['payload_json'],
      );

      return _posUploadNullableString(payload['cash_register_id']) != null &&
          _posUploadNullableString(payload['cash_session_id']) != null;
    });

    if (allSalesHaveCashContext) {
      final dirtyRegisters =
          await _cashSessionLocalDao.getPendingDirtyCashRegisters(
        businessId: businessId,
        branchId: branchId,
        limit: 1,
      );

      final dirtySessions =
          await _cashSessionLocalDao.getPendingDirtyCashSessions(
        businessId: businessId,
        branchId: branchId,
        limit: 1,
      );

      if (dirtyRegisters.isEmpty && dirtySessions.isEmpty) {
        return;
      }

      throw StateError(
        'Upload POS bloqueado: las ventas tienen caja asociada, '
        'pero todavía hay cash_registers/cash_sessions pendientes de sync. '
        'Sube cash antes de subir POS.',
      );
    }

    final summary = await _cashSessionLocalDao.getPosCashReadinessSummary(
      businessId: businessId,
      branchId: branchId,
    );

    final blockedReason = summary['pos_upload_blocked_reason'];

    if (blockedReason != null && blockedReason.toString().trim().isNotEmpty) {
      throw StateError(
        'Upload POS bloqueado: ${blockedReason.toString()}',
      );
    }
  }

  Map<String, dynamic> _posUploadPayloadMap(Object? payload) {
    if (payload == null) {
      return {};
    }

    if (payload is Map<String, dynamic>) {
      return payload;
    }

    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }

    if (payload is String && payload.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);

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

  String? _posUploadNullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  Future<void> _markLocalPosEntitiesSynced({
    required List<Map<String, dynamic>> mutations,
  }) async {
    final saleIds = <String>{};

    for (final mutation in mutations) {
      final entityTable = mutation['entity_table']?.toString();

      if (entityTable == 'sales') {
        final saleId = mutation['entity_id']?.toString();

        if (saleId != null && saleId.trim().isNotEmpty) {
          saleIds.add(saleId);
        }
      }
    }

    for (final saleId in saleIds) {
      await _posLocalSaleDao.markSaleAndChildrenSyncedAfterPosUpload(
        saleId: saleId,
      );
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
          errorCode: 'remote_pos_batch_partial',
          errorMessage:
              'El batch remoto POS quedó partial. Revisar sync_conflicts en servidor.',
        );
      }

      return;
    }

    if (result.errorCount > 0) {
      for (final mutation in mutations) {
        await _outboxService.markMutationError(
          localMutationId: _requiredString(mutation, 'id'),
          errorCode: 'remote_pos_batch_error',
          error: 'El batch remoto POS reportó errores.',
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
