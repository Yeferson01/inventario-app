import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../../cash/data/datasources/cash_session_local_dao.dart';
import '../../sales/data/datasources/pos_local_sale_dao.dart';
import '../data/datasources/pos_sync_remote_datasource.dart';
import '../data/models/catalog_upload_models.dart';
import 'local_sync_outbox_service.dart';
import 'pos_cash_session_failure_reconciliation_service.dart';
import 'pos_inventory_failure_reconciliation_service.dart';

typedef WeightedSaleInventoryRefresher = Future<bool> Function({
  required String profileId,
  required String businessId,
  required String branchId,
  required String appDeviceId,
});

class PosSyncUploadService {
  PosSyncUploadService({
    required LocalSyncOutboxService outboxService,
    required PosSyncRemoteDataSource remoteDataSource,
    required PosLocalSaleDao posLocalSaleDao,
    required CashSessionLocalDao cashSessionLocalDao,
    required PosCashSessionFailureReconciliationService
        cashSessionFailureReconciliationService,
    required PosInventoryFailureReconciliationService
        inventoryFailureReconciliationService,
    this.weightedSaleInventoryRefresher,
  })  : _outboxService = outboxService,
        _remoteDataSource = remoteDataSource,
        _posLocalSaleDao = posLocalSaleDao,
        _cashSessionLocalDao = cashSessionLocalDao,
        _cashSessionFailureReconciliationService =
            cashSessionFailureReconciliationService,
        _inventoryFailureReconciliationService =
            inventoryFailureReconciliationService;

  final LocalSyncOutboxService _outboxService;
  final PosSyncRemoteDataSource _remoteDataSource;
  final CashSessionLocalDao _cashSessionLocalDao;
  final PosLocalSaleDao _posLocalSaleDao;
  final PosCashSessionFailureReconciliationService
      _cashSessionFailureReconciliationService;
  final PosInventoryFailureReconciliationService
      _inventoryFailureReconciliationService;
  final WeightedSaleInventoryRefresher? weightedSaleInventoryRefresher;

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

        final batchMetadata = _posUploadPayloadMap(batch['metadata_json']);
        final weightedBatch = batchMetadata['monetary_contract_version'] ==
                'exact_weight_sale_v1' ||
            mutations.any((mutation) {
              if (mutation['entity_table'] != 'sales' &&
                  mutation['entity_table'] != 'sale_items') {
                return false;
              }
              final payload = _posUploadPayloadMap(
                mutation['payload'] ?? mutation['payload_json'],
              );
              return payload['monetary_contract_version'] ==
                      'exact_weight_sale_v1' ||
                  payload['sale_mode_snapshot'] == 'weight';
            });
        if (weightedBatch) {
          if (mutations.isEmpty &&
              await _outboxService.supersedeLegacyEmptyWeightedPosBatch(
                localBatchId: localBatchId,
                businessId: businessId,
                branchId: branchId,
              )) {
            AppLogger.info('Legacy empty WEIGHT POS batch superseded: '
                'local=$localBatchId');
            continue;
          }
          _validateWeightedBatchPayload(batchMetadata, mutations);
          if (weightedSaleInventoryRefresher == null ||
              !await _remoteDataSource.supportsWeightedSaleSync()) {
            throw StateError('weighted_sale_remote_apply_not_enabled');
          }
        }

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

        final remoteEntitiesAlreadyExist = !weightedBatch &&
            await _remoteDataSource.allPosMutationEntitiesAlreadyExist(
              localMutations: mutations,
            );

        if (remoteEntitiesAlreadyExist) {
          final inventoryFailures =
              await _remoteDataSource.getInventoryApplyFailuresForMutations(
            localMutations: mutations,
          );
          await _recordInventoryFailures(
            batch: batch,
            failures: inventoryFailures,
          );
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

        final cashSessionFailures =
            await _remoteDataSource.getCashSessionApplyFailures(
          serverBatchId: result.serverBatchId,
        );
        await _recordCashSessionFailures(
          batch: batch,
          failures: cashSessionFailures,
        );

        final inventoryFailures =
            await _remoteDataSource.getInventoryApplyFailures(
          serverBatchId: result.serverBatchId,
        );
        if (inventoryFailures.isNotEmpty) {
          await _recordInventoryFailures(
            batch: batch,
            failures: inventoryFailures,
          );
        }

        uploaded++;
        mutationsUploaded += result.mutationCount;

        final duplicateConflictsAreIdempotent =
            await _duplicateConflictsAreIdempotent(result);

        final canTreatAsCompleted = weightedBatch
            ? result.completed
            : result.completed ||
                duplicateConflictsAreIdempotent ||
                (result.errorCount == 0 &&
                    result.conflictCount == 0 &&
                    result.appliedCount + result.skippedCount >=
                        result.mutationCount);

        if (canTreatAsCompleted) {
          if (weightedBatch) {
            final entries = _weightedAckEntries(result, mutations);
            await _posLocalSaleDao.applyWeightedSaleAck(
              businessId: _requiredString(batch, 'business_id'),
              branchId: _requiredString(batch, 'branch_id'),
              saleId: _requiredString(
                mutations.firstWhere(
                    (mutation) => mutation['entity_table'] == 'sales'),
                'entity_id',
              ),
              entries: entries,
            );
            await _markLocalPosEntitiesSynced(mutations: mutations);
            final converged = await weightedSaleInventoryRefresher!(
              profileId: _requiredString(batch, 'profile_id'),
              businessId: _requiredString(batch, 'business_id'),
              branchId: _requiredString(batch, 'branch_id'),
              appDeviceId: _requiredString(batch, 'app_device_id'),
            );
            if (!converged) {
              throw StateError('weighted_sale_inventory_not_converged');
            }
          }

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

          if (!weightedBatch) {
            await _markLocalPosEntitiesSynced(mutations: mutations);
          }

          completed++;
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

  Future<void> _recordInventoryFailures({
    required Map<String, dynamic> batch,
    required List<PosInventoryApplyFailure> failures,
  }) async {
    if (failures.isEmpty) return;
    await _inventoryFailureReconciliationService.recordFailures(
      profileId: _requiredString(batch, 'profile_id'),
      businessId: _requiredString(batch, 'business_id'),
      branchId: _requiredString(batch, 'branch_id'),
      failures: failures,
    );
  }

  Future<void> _recordCashSessionFailures({
    required Map<String, dynamic> batch,
    required List<PosCashSessionApplyFailure> failures,
  }) async {
    if (failures.isEmpty) return;
    await _cashSessionFailureReconciliationService.recordFailures(
      profileId: _requiredString(batch, 'profile_id'),
      businessId: _requiredString(batch, 'business_id'),
      branchId: _requiredString(batch, 'branch_id'),
      failures: failures,
    );
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

  void _validateWeightedBatchPayload(
    Map<String, dynamic> metadata,
    List<Map<String, dynamic>> mutations,
  ) {
    final sales = mutations.where((m) => m['entity_table'] == 'sales').toList();
    final items =
        mutations.where((m) => m['entity_table'] == 'sale_items').toList();
    final payments =
        mutations.where((m) => m['entity_table'] == 'sale_payments').toList();
    if (metadata['monetary_contract_version'] != 'exact_weight_sale_v1' ||
        sales.length != 1 ||
        items.isEmpty ||
        payments.isEmpty ||
        metadata['item_count'] != items.length ||
        metadata['payment_count'] != payments.length ||
        mutations.length != 1 + items.length + payments.length) {
      throw StateError('weighted_sale_payload_invalid');
    }
    final salePayload = _posUploadPayloadMap(
      sales.single['payload'] ?? sales.single['payload_json'],
    );
    final saleId = sales.single['entity_id']?.toString();
    final total = salePayload['total_cents'];
    if (saleId == null ||
        saleId.isEmpty ||
        salePayload['monetary_contract_version'] != 'exact_weight_sale_v1' ||
        total is! int ||
        total < 0) {
      throw StateError('weighted_sale_payload_invalid');
    }
    var hasWeight = false;
    var itemTotal = 0;
    for (final mutation in items) {
      final payload = _posUploadPayloadMap(
        mutation['payload'] ?? mutation['payload_json'],
      );
      final mode = payload['sale_mode_snapshot'];
      final quantity = payload['quantity'];
      final price = payload['price_cents_snapshot'];
      final lineTotal = payload['line_total_cents'];
      final basis = payload['price_basis_quantity_snapshot'];
      if (payload['monetary_contract_version'] != 'exact_weight_sale_v1' ||
          payload['sale_id'] != saleId ||
          (mode != 'weight' && mode != 'unit') ||
          quantity is! int ||
          quantity <= 0 ||
          price is! int ||
          price < 0 ||
          lineTotal is! int ||
          lineTotal < 0 ||
          (mode == 'weight' &&
              (basis != 500 ||
                  payload['discount_amount'] != 0 ||
                  payload['tax_amount'] != 0)) ||
          (mode == 'unit' && basis != 1)) {
        throw StateError('weighted_sale_payload_invalid');
      }
      hasWeight |= mode == 'weight';
      itemTotal += lineTotal;
    }
    var paymentTotal = 0;
    for (final mutation in payments) {
      final payload = _posUploadPayloadMap(
        mutation['payload'] ?? mutation['payload_json'],
      );
      final amount = payload['amount_cents'];
      if (payload['sale_id'] != saleId || amount is! int || amount < 0) {
        throw StateError('weighted_sale_payload_invalid');
      }
      paymentTotal += amount;
    }
    if (!hasWeight || itemTotal != total || paymentTotal != total) {
      throw StateError('weighted_sale_payload_invalid');
    }
  }

  List<Map<String, dynamic>> _weightedAckEntries(
    CatalogUploadBatchResult result,
    List<Map<String, dynamic>> mutations,
  ) {
    final raw = result.raw['weighted_sale_ack'];
    final expected = mutations
        .where((mutation) {
          if (mutation['entity_table'] != 'sale_items') return false;
          final payload = _posUploadPayloadMap(
            mutation['payload'] ?? mutation['payload_json'],
          );
          return payload['sale_mode_snapshot'] == 'weight';
        })
        .map((mutation) => mutation['entity_id']?.toString())
        .toSet();
    if (raw is! List || raw.length != expected.length) {
      throw StateError('weighted_sale_ack_missing');
    }
    final entries = raw.map((entry) => _posUploadPayloadMap(entry)).toList();
    final actual =
        entries.map((entry) => entry['sale_item_id']?.toString()).toSet();
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      throw StateError('weighted_sale_ack_invalid');
    }
    return entries;
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
