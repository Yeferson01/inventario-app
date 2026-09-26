import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../../cash/data/datasources/cash_movement_local_dao.dart';
import '../../cash/data/datasources/cash_session_local_dao.dart';
import '../data/datasources/cash_sync_remote_datasource.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/models/cash_movement_ack_models.dart';
import '../data/models/catalog_upload_models.dart';
import '../data/models/local_recovery_models.dart';
import 'local_sync_outbox_service.dart';

class CashSyncUploadService {
  CashSyncUploadService({
    required LocalSyncOutboxService outboxService,
    required CashSyncRemoteDataSource remoteDataSource,
    required CashSessionLocalDao cashSessionLocalDao,
    CashMovementLocalDao? cashMovementLocalDao,
    ReconciliationIssueLocalDao? issueDao,
  })  : _outboxService = outboxService,
        _remoteDataSource = remoteDataSource,
        _cashSessionLocalDao = cashSessionLocalDao,
        _cashMovementLocalDao = cashMovementLocalDao,
        _issueDao = issueDao;

  final LocalSyncOutboxService _outboxService;
  final CashSyncRemoteDataSource _remoteDataSource;
  final CashSessionLocalDao _cashSessionLocalDao;
  final CashMovementLocalDao? _cashMovementLocalDao;
  final ReconciliationIssueLocalDao? _issueDao;

  Future<CatalogUploadRunResult> uploadPendingCashBatches({
    required String businessId,
    String? branchId,
    int batchLimit = 10,
  }) async {
    await _cashSessionLocalDao.deleteOrphanCashOutboxBatches(
      businessId: businessId,
    );

    await _cashSessionLocalDao.resetRetryableCashOutboxBatches(
      businessId: businessId,
    );

    await _cashSessionLocalDao.reconcileCompletedCashFromOutbox(
      businessId: businessId,
    );

    final pendingBatches = await _outboxService.getPendingCashBatches(
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
      List<Map<String, dynamic>> mutations = const [];

      try {
        await _outboxService.markBatchUploading(localBatchId);

        mutations = await _outboxService.getMutationsForBatch(localBatchId);
        final movements = mutations
            .where((m) => m['entity_table'] == 'cash_movements')
            .toList(growable: false);
        final otherMutations = mutations
            .where((m) => m['entity_table'] != 'cash_movements')
            .toList(growable: false);
        if (movements.isNotEmpty &&
            (_cashMovementLocalDao == null || _issueDao == null)) {
          throw StateError('Cash movement ACK projection is not configured.');
        }

        final result = await _remoteDataSource.uploadAndProcessCashBatch(
          localBatch: batch,
          localMutations: mutations,
        );

        uploaded++;
        mutationsUploaded += result.mutationCount;

        final acks = movements.isEmpty
            ? const <String, CashMovementAck>{}
            : await _remoteDataSource.lookupMovementAcknowledgements(
                businessId: _requiredString(batch, 'business_id'),
                branchId: _requiredString(batch, 'branch_id'),
                appDeviceId: _requiredString(batch, 'app_device_id'),
                mutations: movements,
              );
        final movementAcksApplied = movements.every((mutation) =>
            acks[_requiredString(mutation, 'entity_id')]?.state ==
            CashMovementAckState.applied);

        if (result.completed && movementAcksApplied) {
          completed++;

          await _outboxService.markBatchCompleted(
            localBatchId: localBatchId,
            serverSyncBatchId: result.serverBatchId,
            appliedCount: result.appliedCount,
            skippedCount: result.skippedCount,
            conflictCount: result.conflictCount,
            errorCount: result.errorCount,
          );

          await _markBatchMutationsApplied(mutations: otherMutations);

          await _markLocalCashSynced(mutations: otherMutations);
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
            mutations: otherMutations,
            result: result,
          );
        }
        if (movements.isNotEmpty) {
          await _projectMovementAcks(
            batch: batch,
            mutations: movements,
            acks: acks,
          );
        }

        AppLogger.info(
          'Cash batch uploaded: local=$localBatchId '
          'server=${result.serverBatchId} status=${result.status}',
        );
        if (!result.completed || !movementAcksApplied) break;
      } catch (error, stackTrace) {
        failed++;

        await _outboxService.markBatchError(
          localBatchId: localBatchId,
          error: error,
        );
        for (final mutation in mutations.where(
          (m) => m['entity_table'] == 'cash_movements',
        )) {
          await _openMovementIssue(
            batch: batch,
            mutation: mutation,
            issueType: 'cash_movement_ack_ambiguous',
            reason: 'ack_unavailable',
          );
          await _cashMovementLocalDao?.markAmbiguous(
            _requiredString(mutation, 'entity_id'),
          );
        }

        AppLogger.error(
          'Cash batch upload failed: $localBatchId',
          error: error,
          stackTrace: stackTrace,
        );
        break;
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

  Future<void> _projectMovementAcks({
    required Map<String, dynamic> batch,
    required List<Map<String, dynamic>> mutations,
    required Map<String, CashMovementAck> acks,
  }) async {
    for (final mutation in mutations) {
      final id = _requiredString(mutation, 'entity_id');
      final ack = acks[id];
      if (ack == null) {
        throw const FormatException('Cash movement ACK missing an entity.');
      }
      switch (ack.state) {
        case CashMovementAckState.applied:
          await _outboxService.markMutationApplied(
            localMutationId: _requiredString(mutation, 'id'),
          );
          await _cashMovementLocalDao!.markSynced(id);
          for (final type in [
            'cash_movement_rejected',
            'cash_movement_ack_ambiguous',
          ]) {
            await _issueDao!.resolveOpenIssue(
              profileId: _requiredString(batch, 'profile_id'),
              businessId: _requiredString(batch, 'business_id'),
              branchId: _requiredString(batch, 'branch_id'),
              domain: 'cash_pos',
              issueType: type,
              entityType: 'cash_movements',
              entityId: id,
            );
          }
          break;
        case CashMovementAckState.rejected:
          await _outboxService.markMutationConflict(
            localMutationId: _requiredString(mutation, 'id'),
            errorCode: ack.reason ?? 'cash_movement_rejected',
            errorMessage: 'Cash movement requires recovery.',
          );
          await _cashMovementLocalDao!.markRejected(id);
          await _openMovementIssue(
            batch: batch,
            mutation: mutation,
            issueType: 'cash_movement_rejected',
            reason: ack.reason ?? 'unknown',
          );
          break;
        case CashMovementAckState.ambiguous:
        case CashMovementAckState.notFound:
          await _outboxService.markMutationError(
            localMutationId: _requiredString(mutation, 'id'),
            errorCode: 'cash_movement_ack_ambiguous',
            error: 'Cash movement acknowledgement is inconclusive.',
          );
          await _cashMovementLocalDao!.markAmbiguous(id);
          await _openMovementIssue(
            batch: batch,
            mutation: mutation,
            issueType: 'cash_movement_ack_ambiguous',
            reason: ack.reason ?? ack.state.name,
          );
          break;
      }
    }
  }

  Future<void> _openMovementIssue({
    required Map<String, dynamic> batch,
    required Map<String, dynamic> mutation,
    required String issueType,
    required String reason,
  }) async {
    final issueDao = _issueDao;
    if (issueDao == null) return;
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(_requiredString(mutation, 'payload_json'));
      if (decoded is Map<String, dynamic>) payload = decoded;
    } on FormatException {
      // Keep the blocker unresolved rather than losing it on malformed data.
    }
    final cashSessionId = payload?['cash_session_id']?.toString();
    await issueDao.openOrUpdateIssue(ReconciliationIssueDraft(
      profileId: _requiredString(batch, 'profile_id'),
      businessId: _requiredString(batch, 'business_id'),
      branchId: _requiredString(batch, 'branch_id'),
      domain: 'cash_pos',
      entityType: 'cash_movements',
      entityId: _requiredString(mutation, 'entity_id'),
      issueType: issueType,
      severity: 'blocking',
      message: 'Cash movement requires reconciliation before cash is ready.',
      metadataJson: jsonEncode(<String, String>{'reason': reason}),
      cashRegisterId: payload?['cash_register_id']?.toString(),
      cashSessionId: cashSessionId,
      scopeResolutionStatus: cashSessionId == null
          ? ReconciliationScopeResolutionStatus.unresolved
          : ReconciliationScopeResolutionStatus.resolvedSession,
      scopeEvidenceType: 'local_cash_movement',
    ));
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
