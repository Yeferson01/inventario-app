import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

class RecoveryBlockedPurchaseCandidate {
  const RecoveryBlockedPurchaseCandidate({
    required this.purchaseId,
    required this.movementIds,
    required this.itemIds,
    required this.localBatchIds,
    required this.locallyConverged,
  });

  final String purchaseId;
  final List<String> movementIds;
  final List<String> itemIds;
  final List<String> localBatchIds;
  final bool locallyConverged;
}

class RecoveryBlockedPurchaseRetryLocalDao {
  RecoveryBlockedPurchaseRetryLocalDao(this._db);

  final AppDatabase _db;

  Future<RecoveryBlockedPurchaseCandidate?> findCandidate({
    required String profileId,
    required String businessId,
    required String branchId,
    required String appDeviceId,
    required String movementId,
  }) async {
    final roots = await _db.customSelect(
      '''
      select m.id as movement_id, m.source_id as purchase_id
      from local_inventory_movements m
      join purchases p on p.id = m.source_id
      where m.id = ? and m.business_id = ? and m.branch_id = ?
        and m.source_type = 'purchase' and m.deleted_at is null
        and p.business_id = ? and p.branch_id = ? and p.deleted_at is null
        and p.idempotency_key is not null and trim(p.idempotency_key) <> ''
      limit 1
      ''',
      variables: [
        Variable<String>(movementId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
    ).get();
    if (roots.isEmpty) return null;
    final purchaseId = roots.single.data['purchase_id']?.toString();
    if (purchaseId == null || purchaseId.isEmpty) return null;

    final itemRows = await _db.customSelect(
      '''
      select id
      from purchase_items
      where purchase_id = ? and business_id = ? and branch_id = ?
        and deleted_at is null
        and idempotency_key is not null and trim(idempotency_key) <> ''
      order by id
      ''',
      variables: [
        Variable<String>(purchaseId),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
    ).get();
    if (itemRows.isEmpty) return null;
    final itemIds = itemRows
        .map((row) => row.data['id']?.toString())
        .whereType<String>()
        .toList(growable: false);

    final allItemCount = await _db.customSelect(
      '''select count(*) as value from purchase_items
         where purchase_id = ? and deleted_at is null''',
      variables: [Variable<String>(purchaseId)],
    ).getSingle();
    if ((allItemCount.data['value'] as int) != itemIds.length) return null;

    final movementRows = await _db.customSelect(
      '''
      select id
      from local_inventory_movements
      where business_id = ? and branch_id = ?
        and source_type = 'purchase' and source_id = ? and deleted_at is null
        and idempotency_key is not null and trim(idempotency_key) <> ''
      order by id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(purchaseId),
      ],
    ).get();
    final movementIds = movementRows
        .map((row) => row.data['id']?.toString())
        .whereType<String>()
        .toList(growable: false);
    final allMovementCount = await _db.customSelect(
      '''select count(*) as value from local_inventory_movements
         where source_type = 'purchase' and source_id = ? and deleted_at is null''',
      variables: [Variable<String>(purchaseId)],
    ).getSingle();
    if (movementIds.length != itemIds.length ||
        (allMovementCount.data['value'] as int) != movementIds.length ||
        !movementIds.contains(movementId)) {
      return null;
    }

    final batches = await _db.customSelect(
      '''
      select distinct b.id
      from local_sync_batches b
      join local_sync_mutations mutation on mutation.local_sync_batch_id = b.id
      left join purchase_items item on item.id = mutation.entity_id
      where b.business_id = ? and b.branch_id = ?
        and b.profile_id = ? and b.app_device_id = ?
        and b.domain = 'purchases'
        and b.status in ('partial', 'error', 'superseded')
        and mutation.status in ('conflict', 'error', 'pending', 'superseded', 'applied')
        and (
          (mutation.entity_table = 'purchases' and mutation.entity_id = ?)
          or (mutation.entity_table = 'purchase_items' and item.purchase_id = ?)
        )
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(profileId),
        Variable<String>(appDeviceId),
        Variable<String>(purchaseId),
        Variable<String>(purchaseId),
      ],
    ).get();
    final batchIds = batches
        .map((row) => row.data['id']?.toString())
        .whereType<String>()
        .toList(growable: false);
    if (batchIds.isEmpty) return null;

    final locallyConverged = await isPurchaseLocallyConverged(
      businessId: businessId,
      branchId: branchId,
      purchaseId: purchaseId,
    );

    return RecoveryBlockedPurchaseCandidate(
      purchaseId: purchaseId,
      movementIds: movementIds,
      itemIds: itemIds,
      localBatchIds: batchIds,
      locallyConverged: locallyConverged,
    );
  }

  Future<String?> findReusableRetryBatchId({
    required String profileId,
    required String businessId,
    required String branchId,
    required String appDeviceId,
    required String purchaseId,
  }) async {
    final row = await _db.customSelect(
      '''
      select b.id, b.status
      from local_sync_batches b
      join local_sync_mutations mutation on mutation.local_sync_batch_id = b.id
      where b.business_id = ? and b.branch_id = ?
        and b.profile_id = ? and b.app_device_id = ?
        and b.domain = 'purchases' and b.status in ('pending', 'error', 'uploading')
        and mutation.entity_table = 'purchases' and mutation.entity_id = ?
        and mutation.status in ('pending', 'error')
      order by b.created_at desc
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(profileId),
        Variable<String>(appDeviceId),
        Variable<String>(purchaseId),
      ],
    ).getSingleOrNull();
    if (row == null) return null;
    final id = row.data['id']?.toString();
    if (id == null || id.isEmpty) return null;
    if (row.data['status'] == 'uploading') {
      final now = DateTime.now().toUtc().toIso8601String();
      await _db.customStatement(
        '''update local_sync_batches
           set status = 'error',
               last_error = 'Recovered interrupted causal Purchase retry.',
               updated_at = ?
           where id = ? and status = 'uploading' ''',
        [now, id],
      );
    }
    return id;
  }

  Future<bool> isTargetIssueOpen({
    required String profileId,
    required String businessId,
    required String branchId,
    required String movementId,
  }) async {
    final row = await _db.customSelect(
      '''
      select 1
      from local_reconciliation_issues
      where profile_id = ? and business_id = ? and branch_id = ?
        and issue_type = 'inventory_movement_rejected'
        and entity_type = 'inventory_movements' and entity_id = ?
        and severity = 'blocking' and status = 'open'
      limit 1
      ''',
      variables: [
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(movementId),
      ],
    ).getSingleOrNull();
    return row != null;
  }

  Future<bool> isPurchaseLocallyConverged({
    required String businessId,
    required String branchId,
    required String purchaseId,
  }) async {
    final row = await _db.customSelect(
      '''
      select
        p.local_status = 'synced' and p.sync_status = 0
        and not exists (
          select 1 from purchase_items item
          where item.purchase_id = p.id
            and (item.local_status <> 'synced' or item.sync_status <> 0)
        )
        and not exists (
          select 1 from local_inventory_movements movement
          where movement.source_type = 'purchase' and movement.source_id = p.id
            and (movement.local_status <> 'synced' or movement.sync_status <> 0)
        ) as converged
      from purchases p
      where p.id = ? and p.business_id = ? and p.branch_id = ?
      limit 1
      ''',
      variables: [
        Variable<String>(purchaseId),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
    ).getSingleOrNull();
    return row?.data['converged'] == true || row?.data['converged'] == 1;
  }
}
