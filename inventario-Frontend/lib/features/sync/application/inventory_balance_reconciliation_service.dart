import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../inventory/data/datasources/product_stock_balance_local_dao.dart';
import '../data/datasources/inventory_balance_reconciliation_local_dao.dart';
import '../data/datasources/inventory_movement_acknowledgement_remote_datasource.dart';
import '../data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import '../data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/models/inventory_balance_reconciliation_models.dart';
import '../data/models/inventory_movement_acknowledgement_models.dart';
import '../data/models/local_recovery_models.dart';
import 'operational_bootstrap_download_models.dart';
import 'operational_bootstrap_download_service.dart';

typedef InventoryReconciliationBeforeFinalization = Future<void> Function();

class InventoryBalanceReconciliationService {
  InventoryBalanceReconciliationService({
    required AppDatabase database,
    required InventoryMovementAcknowledgementRemoteDataSource
        acknowledgementDataSource,
    required InventoryBalanceReconciliationLocalDao movementDao,
    required ProductStockBalanceLocalDao balanceDao,
    required OperationalBootstrapDownloadService downloadService,
    required OperationalBootstrapSeenRecordLocalDao seenRecordDao,
    required OperationalBootstrapCheckpointLocalDao checkpointDao,
    required ReconciliationIssueLocalDao issueDao,
    this.maxAttempts = 3,
    this.beforeFinalization,
  })  : _database = database,
        _acknowledgementDataSource = acknowledgementDataSource,
        _movementDao = movementDao,
        _balanceDao = balanceDao,
        _downloadService = downloadService,
        _seenRecordDao = seenRecordDao,
        _checkpointDao = checkpointDao,
        _issueDao = issueDao;

  final AppDatabase _database;
  final InventoryMovementAcknowledgementRemoteDataSource
      _acknowledgementDataSource;
  final InventoryBalanceReconciliationLocalDao _movementDao;
  final ProductStockBalanceLocalDao _balanceDao;
  final OperationalBootstrapDownloadService _downloadService;
  final OperationalBootstrapSeenRecordLocalDao _seenRecordDao;
  final OperationalBootstrapCheckpointLocalDao _checkpointDao;
  final ReconciliationIssueLocalDao _issueDao;
  final int maxAttempts;
  final InventoryReconciliationBeforeFinalization? beforeFinalization;

  Future<InventoryBalanceReconciliationResult> reconcile(
    InventoryBalanceReconciliationRequest request, {
    bool restart = false,
  }) async {
    String? lastSnapshotId;
    var movementsChecked = 0;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final firstMovements = await _movementDao.getMovements(
        businessId: request.businessId,
        branchId: request.branchId,
      );
      final firstAck = await _acknowledge(request, firstMovements);

      final download = await _downloadService.download(
        OperationalBootstrapDownloadRequest(
          profileId: request.profileId,
          businessId: request.businessId,
          branchId: request.branchId,
          appDeviceId: request.appDeviceId,
          bundle: 'product_operational',
          dataset: 'product_stock_balances',
          limit: request.pageLimit,
        ),
        restart: restart && attempt == 1,
      );
      lastSnapshotId = download.snapshotId;

      final secondMovements = await _movementDao.getMovements(
        businessId: request.businessId,
        branchId: request.branchId,
      );
      final secondAck = await _acknowledge(request, secondMovements);
      movementsChecked = secondMovements.length;
      if (!_sameObservation(
        firstMovements,
        firstAck,
        secondMovements,
        secondAck,
      )) {
        continue;
      }

      await beforeFinalization?.call();
      _FinalizationResult? finalization;
      var changedBeforeCommit = false;
      await _database.transaction(() async {
        final finalMovements = await _movementDao.getMovements(
          businessId: request.businessId,
          branchId: request.branchId,
        );
        if (!_sameMovementSet(secondMovements, finalMovements)) {
          changedBeforeCommit = true;
          return;
        }
        finalization = await _finalize(
          request: request,
          snapshotId: download.snapshotId,
          movements: finalMovements,
          acknowledgements: secondAck,
        );
      });
      if (changedBeforeCommit) {
        continue;
      }
      final result = finalization!;
      return InventoryBalanceReconciliationResult(
        snapshotId: download.snapshotId,
        attempts: attempt,
        movementsChecked: movementsChecked,
        balancesReconciled: result.balancesReconciled,
        blockingIssues: result.blockingIssues,
        converged: result.blockingIssues == 0,
      );
    }

    await _database.transaction(() async {
      await _openIssue(
        request: request,
        issueType: 'inventory_convergence_unstable',
        message:
            'Inventory movements or acknowledgements changed during every convergence attempt.',
        metadata: {'attempts': maxAttempts},
      );
      await _checkpointDao.markConvergence(
        _scope(request),
        status: 'blocked',
        error:
            'Inventory convergence remained unstable after $maxAttempts attempts.',
      );
    });
    return InventoryBalanceReconciliationResult(
      snapshotId: lastSnapshotId,
      attempts: maxAttempts,
      movementsChecked: movementsChecked,
      balancesReconciled: 0,
      blockingIssues: 1,
      converged: false,
    );
  }

  Future<Map<String, InventoryMovementAcknowledgement>> _acknowledge(
    InventoryBalanceReconciliationRequest request,
    List<LocalInventoryMovementForReconciliation> movements,
  ) {
    return _acknowledgementDataSource.lookup(
      businessId: request.businessId,
      branchId: request.branchId,
      appDeviceId: request.appDeviceId,
      operations: movements
          .where((movement) => movement.canRequestAcknowledgement)
          .map((movement) => movement.acknowledgementOperation)
          .toList(growable: false),
    );
  }

  bool _sameObservation(
    List<LocalInventoryMovementForReconciliation> leftMovements,
    Map<String, InventoryMovementAcknowledgement> leftAck,
    List<LocalInventoryMovementForReconciliation> rightMovements,
    Map<String, InventoryMovementAcknowledgement> rightAck,
  ) {
    if (!_sameMovementSet(leftMovements, rightMovements) ||
        leftAck.length != rightAck.length) {
      return false;
    }
    return leftAck.entries.every(
      (entry) => rightAck[entry.key]?.status == entry.value.status,
    );
  }

  bool _sameMovementSet(
    List<LocalInventoryMovementForReconciliation> left,
    List<LocalInventoryMovementForReconciliation> right,
  ) {
    if (left.length != right.length) return false;
    final rightById = {for (final movement in right) movement.id: movement};
    return left.every(
      (movement) => rightById[movement.id]?.fingerprint == movement.fingerprint,
    );
  }

  Future<_FinalizationResult> _finalize({
    required InventoryBalanceReconciliationRequest request,
    required String snapshotId,
    required List<LocalInventoryMovementForReconciliation> movements,
    required Map<String, InventoryMovementAcknowledgement> acknowledgements,
  }) async {
    final balances = await _balanceDao.getScopeBalances(
      businessId: request.businessId,
      branchId: request.branchId,
    );
    final seen = (await _seenRecordDao.getEntityIds(
      snapshotId: snapshotId,
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
      bundle: 'product_operational',
      dataset: 'product_stock_balances',
    ))
        .toSet();
    final movementsByProduct =
        <String, List<LocalInventoryMovementForReconciliation>>{};
    for (final movement in movements) {
      movementsByProduct
          .putIfAbsent(movement.productId, () => [])
          .add(movement);
    }

    var reconciled = 0;
    var blockers = 0;
    final processedProducts = <String>{};
    for (final balance in balances) {
      final productId = balance['product_id'].toString();
      processedProducts.add(productId);
      final productMovements = movementsByProduct[productId] ?? const [];
      final pending = <LocalInventoryMovementForReconciliation>[];
      var productBlocked = false;
      for (final movement in productMovements) {
        final issue = _movementIssue(movement, acknowledgements[movement.id]);
        if (issue != null) {
          productBlocked = true;
          blockers += 1;
          await _openIssue(
            request: request,
            issueType: issue.type,
            message: issue.message,
            entityType: 'inventory_movements',
            entityId: movement.id,
            metadata: issue.metadata,
          );
          continue;
        }
        await _resolveMovementIssues(request, movement.id);
        final acknowledgement = acknowledgements[movement.id];
        if (acknowledgement?.status ==
                InventoryMovementAcknowledgementStatus.notFound &&
            movement.transportState ==
                InventoryMovementTransportState.pending) {
          pending.add(movement);
        }
      }

      final semanticIdentity =
          '${request.businessId}:${request.branchId}:$productId';
      final isSeen = seen.contains(semanticIdentity) &&
          balance['remote_snapshot_id']?.toString() == snapshotId;
      final metadata = _metadata(balance['metadata_json']);
      final isTombstone =
          isSeen && metadata['remote_record_state']?.toString() == 'tombstone';
      if ((!isSeen || isTombstone) && pending.isNotEmpty) {
        productBlocked = true;
        blockers += 1;
        await _openIssue(
          request: request,
          issueType: isTombstone
              ? 'remote_tombstone_with_pending_movement'
              : 'balance_absent_with_pending_movement',
          message: isTombstone
              ? 'Remote balance is tombstoned while unacknowledged local movements remain.'
              : 'Balance is absent from the remote snapshot while unacknowledged local movements remain.',
          entityType: 'product_stock_balances',
          entityId: productId,
          metadata: {'snapshot_id': snapshotId},
        );
      }
      if (productBlocked) continue;

      await _resolveBalanceAbsenceIssues(request, productId);

      if (!isSeen || isTombstone) {
        await _balanceDao.finalizeOperativeBalance(
          businessId: request.businessId,
          branchId: request.branchId,
          productId: productId,
          quantityOnHand: 0,
          quantityReserved: 0,
          quantityAvailable: 0,
          averageCost: null,
          lastMovementAt: _latestMovement(productMovements),
          deletedAt: _remoteDeletedAt(metadata) ?? DateTime.now().toUtc(),
        );
        reconciled += 1;
        continue;
      }

      final remoteOnHand = _requiredInt(balance, 'remote_quantity_on_hand');
      final remoteReserved = _requiredInt(balance, 'remote_quantity_reserved');
      final remoteAvailable =
          _requiredInt(balance, 'remote_quantity_available');
      var operativeOnHand = remoteOnHand;
      var operativeAvailable = remoteAvailable;
      var operativeAverageCost =
          (balance['remote_average_cost'] as num?)?.toDouble();
      for (final movement in pending) {
        final oldQuantity = operativeOnHand;
        final newQuantity = oldQuantity + movement.quantityChange;
        if (movement.quantityChange > 0 && movement.unitCost != null) {
          operativeAverageCost =
              oldQuantity <= 0 || operativeAverageCost == null
                  ? movement.unitCost
                  : _roundMoney(
                      ((oldQuantity * operativeAverageCost) +
                              (movement.quantityChange * movement.unitCost!)) /
                          newQuantity,
                    );
        }
        operativeOnHand = newQuantity;
        operativeAvailable += movement.quantityChange;
      }
      await _balanceDao.finalizeOperativeBalance(
        businessId: request.businessId,
        branchId: request.branchId,
        productId: productId,
        quantityOnHand: operativeOnHand,
        quantityReserved: remoteReserved,
        quantityAvailable: operativeAvailable,
        averageCost: operativeAverageCost,
        lastMovementAt: _latestMovement(productMovements),
        deletedAt: null,
      );
      reconciled += 1;
    }

    for (final entry in movementsByProduct.entries) {
      if (processedProducts.contains(entry.key)) continue;
      var hasPendingEffect = false;
      for (final movement in entry.value) {
        final issue = _movementIssue(movement, acknowledgements[movement.id]);
        if (issue != null) {
          blockers += 1;
          await _openIssue(
            request: request,
            issueType: issue.type,
            message: issue.message,
            entityType: 'inventory_movements',
            entityId: movement.id,
            metadata: issue.metadata,
          );
        } else {
          await _resolveMovementIssues(request, movement.id);
        }
        if (issue == null &&
            acknowledgements[movement.id]?.status ==
                InventoryMovementAcknowledgementStatus.notFound &&
            movement.transportState ==
                InventoryMovementTransportState.pending) {
          hasPendingEffect = true;
        }
      }
      if (hasPendingEffect) {
        blockers += 1;
        await _openIssue(
          request: request,
          issueType: 'balance_absent_with_pending_movement',
          message:
              'Balance is absent from the remote snapshot while unacknowledged local movements remain.',
          entityType: 'product_stock_balances',
          entityId: entry.key,
          metadata: {'snapshot_id': snapshotId},
        );
      } else {
        await _resolveBalanceAbsenceIssues(request, entry.key);
      }
    }

    await _checkpointDao.markConvergence(
      _scope(request),
      status: blockers == 0 ? 'complete' : 'blocked',
      error: blockers == 0 ? null : '$blockers inventory blockers remain.',
    );
    if (blockers == 0) {
      await _issueDao.resolveOpenIssue(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        domain: 'inventory_balance',
        issueType: 'inventory_convergence_unstable',
      );
    }
    return _FinalizationResult(
      balancesReconciled: reconciled,
      blockingIssues: blockers,
    );
  }

  _MovementIssue? _movementIssue(
    LocalInventoryMovementForReconciliation movement,
    InventoryMovementAcknowledgement? acknowledgement,
  ) {
    if (movement.requiresSourceItemId && movement.sourceItemId == null) {
      return const _MovementIssue(
        type: 'missing_source_item_id',
        message:
            'Sale or purchase movement lacks the item identity required for authoritative acknowledgement.',
      );
    }
    if (movement.requiresSourceItemId && movement.sourceId == null) {
      return const _MovementIssue(
        type: 'missing_source_id',
        message:
            'Sale or purchase movement lacks the parent identity required for authoritative acknowledgement.',
      );
    }
    if (movement.quantityChange == 0) {
      return const _MovementIssue(
        type: 'invalid_inventory_movement_quantity',
        message: 'A zero inventory movement cannot be acknowledged safely.',
      );
    }
    if (movement.isAppliedServerAuthoritativeTransfer) {
      return null;
    }
    if (!movement.canRequestAcknowledgement) {
      return _MovementIssue(
        type: 'unsupported_inventory_movement',
        message: 'Movement source ${movement.sourceType} cannot be reconciled.',
      );
    }
    if (acknowledgement == null) {
      return const _MovementIssue(
        type: 'missing_acknowledgement',
        message: 'Remote acknowledgement response omitted the movement.',
      );
    }
    if (acknowledgement.status ==
        InventoryMovementAcknowledgementStatus.rejected) {
      return _MovementIssue(
        type: 'inventory_movement_rejected',
        message: 'Remote evidence marks the inventory movement as rejected.',
        metadata: {
          'remote_evidence_status': acknowledgement.remoteEvidenceStatus,
        },
      );
    }
    if (acknowledgement.status ==
        InventoryMovementAcknowledgementStatus.ambiguous) {
      return const _MovementIssue(
        type: 'inventory_movement_ambiguous',
        message:
            'Remote evidence cannot identify the inventory movement uniquely.',
      );
    }
    if (acknowledgement.status ==
            InventoryMovementAcknowledgementStatus.notFound &&
        movement.transportState ==
            InventoryMovementTransportState.terminalApplied) {
      return const _MovementIssue(
        type: 'terminal_local_movement_not_found',
        message:
            'Local transport says the movement was applied but remote inventory evidence was not found.',
      );
    }
    if (acknowledgement.status ==
            InventoryMovementAcknowledgementStatus.notFound &&
        movement.transportState ==
            InventoryMovementTransportState.terminalIncompatible) {
      return const _MovementIssue(
        type: 'terminal_incompatible_inventory_movement',
        message:
            'A rejected local transport operation cannot be added to the operative balance.',
      );
    }
    return null;
  }

  Future<void> _openIssue({
    required InventoryBalanceReconciliationRequest request,
    required String issueType,
    required String message,
    String? entityType,
    String? entityId,
    Map<String, Object?> metadata = const {},
  }) async {
    await _issueDao.openOrUpdateIssue(
      ReconciliationIssueDraft(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        domain: 'inventory_balance',
        entityType: entityType,
        entityId: entityId,
        issueType: issueType,
        severity: 'blocking',
        message: message,
        metadataJson: jsonEncode(metadata),
      ),
    );
  }

  Future<void> _resolveMovementIssues(
    InventoryBalanceReconciliationRequest request,
    String movementId,
  ) async {
    for (final issueType in const [
      'missing_source_item_id',
      'missing_source_id',
      'invalid_inventory_movement_quantity',
      'unsupported_inventory_movement',
      'missing_acknowledgement',
      'inventory_movement_rejected',
      'inventory_movement_ambiguous',
      'terminal_local_movement_not_found',
      'terminal_incompatible_inventory_movement',
    ]) {
      await _issueDao.resolveOpenIssue(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        domain: 'inventory_balance',
        issueType: issueType,
        entityType: 'inventory_movements',
        entityId: movementId,
      );
    }
  }

  Future<void> _resolveBalanceAbsenceIssues(
    InventoryBalanceReconciliationRequest request,
    String productId,
  ) async {
    for (final issueType in const [
      'remote_tombstone_with_pending_movement',
      'balance_absent_with_pending_movement',
    ]) {
      await _issueDao.resolveOpenIssue(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        domain: 'inventory_balance',
        issueType: issueType,
        entityType: 'product_stock_balances',
        entityId: productId,
      );
    }
  }

  OperationalBootstrapScope _scope(
    InventoryBalanceReconciliationRequest request,
  ) {
    return OperationalBootstrapScope(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
      appDeviceId: request.appDeviceId,
      bundle: 'product_operational',
      dataset: 'product_stock_balances',
    );
  }

  Map<String, dynamic> _metadata(Object? value) {
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map((key, item) => MapEntry(key.toString(), item));
        }
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }

  DateTime? _remoteDeletedAt(Map<String, dynamic> metadata) {
    final value = metadata['remote_deleted_at'];
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }

  int _requiredInt(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is num) return value.toInt();
    throw StateError('Staged balance is missing $key.');
  }

  DateTime? _latestMovement(
    List<LocalInventoryMovementForReconciliation> movements,
  ) {
    if (movements.isEmpty) return null;
    return movements
        .map((movement) => movement.occurredAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
  }

  double _roundMoney(double value) => (value * 100).round() / 100;
}

class _MovementIssue {
  const _MovementIssue({
    required this.type,
    required this.message,
    this.metadata = const {},
  });

  final String type;
  final String message;
  final Map<String, Object?> metadata;
}

class _FinalizationResult {
  const _FinalizationResult({
    required this.balancesReconciled,
    required this.blockingIssues,
  });

  final int balancesReconciled;
  final int blockingIssues;
}
