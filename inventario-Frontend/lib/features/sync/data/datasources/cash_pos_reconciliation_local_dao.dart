import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../models/cash_pos_recovery_models.dart';
import '../models/operational_bootstrap_models.dart';

enum CashPosEntityState {
  cleanRemoteSynced,
  pendingLocal,
  transportAmbiguous,
  remotelyApplied,
  dirtyWithoutOutbox,
}

class CashPosEntityClassification {
  const CashPosEntityClassification({
    required this.state,
    required this.recognizedAt,
  });

  final CashPosEntityState state;
  final DateTime? recognizedAt;

  bool get canAcceptRemote =>
      state == CashPosEntityState.cleanRemoteSynced ||
      state == CashPosEntityState.remotelyApplied;
}

class CashPosReconciliationLocalDao {
  CashPosReconciliationLocalDao(this._db);

  final AppDatabase _db;

  Future<Map<String, dynamic>?> getById(String table, String id) async {
    final row = await _db.customSelect(
      'select * from $table where id = ? limit 1',
      variables: [Variable<String>(id)],
    ).getSingleOrNull();
    return row == null ? null : Map<String, dynamic>.from(row.data);
  }

  Future<CashPosEntityClassification> classify({
    required String businessId,
    required String branchId,
    required String domain,
    required String entityTable,
    required String entityId,
    required Map<String, dynamic> local,
    String? parentSaleId,
    String? profileId,
    String? remoteCashSessionId,
  }) async {
    final localStatus = local['local_status']?.toString();
    final syncStatus = local['sync_status'];
    var dirty = syncStatus is! int || syncStatus != SyncStatus.synced.index;
    if (entityTable != 'sale_items') {
      dirty = dirty || (localStatus != null && localStatus != 'synced');
    }

    final targets = <(String, String)>[(entityTable, entityId)];
    if (parentSaleId != null) targets.add(('sales', parentSaleId));
    final clauses =
        List.filled(targets.length, '(m.entity_table = ? and m.entity_id = ?)')
            .join(' or ');
    final variables = <Variable<Object>>[
      Variable<String>(businessId),
      Variable<String>(branchId),
      Variable<String>(domain),
      for (final target in targets) ...[
        Variable<String>(target.$1),
        Variable<String>(target.$2),
      ],
    ];
    final evidence = await _db
        .customSelect(
          '''
      select m.entity_table, m.entity_id, m.business_id, m.branch_id,
             m.status as mutation_status, m.resolved_at as mutation_resolved_at,
             m.error_code as mutation_error_code,
             m.metadata_json as mutation_metadata_json,
             m.uploaded_at as mutation_uploaded_at,
             b.status as batch_status, b.uploaded_at as batch_uploaded_at
      from local_sync_mutations m
      left join local_sync_batches b on b.id = m.local_sync_batch_id
      where m.business_id = ? and m.branch_id = ?
        and (b.id is null or b.domain = ?)
        and ($clauses)
      order by m.created_at desc
      ''',
          variables: variables,
          readsFrom: {_db.localSyncMutations, _db.localSyncBatches},
        )
        .get();

    if (evidence.isEmpty) {
      return CashPosEntityClassification(
        state: dirty
            ? CashPosEntityState.dirtyWithoutOutbox
            : CashPosEntityState.cleanRemoteSynced,
        recognizedAt: null,
      );
    }

    if (profileId != null &&
        remoteCashSessionId != null &&
        await _isAuthoritativeSupersededSaleReconciliation(
          profileId: profileId,
          businessId: businessId,
          branchId: branchId,
          entityTable: entityTable,
          entityId: entityId,
          parentSaleId: parentSaleId,
          remoteCashSessionId: remoteCashSessionId,
          local: local,
          dirty: dirty,
          targets: targets,
          evidence: evidence,
        )) {
      DateTime? reconciledAt;
      for (final row in evidence) {
        final at = _dateOrNull(row.data['mutation_resolved_at']);
        if (at != null && (reconciledAt == null || at.isAfter(reconciledAt))) {
          reconciledAt = at;
        }
      }
      return CashPosEntityClassification(
        state: CashPosEntityState.remotelyApplied,
        recognizedAt: reconciledAt,
      );
    }

    final allApplied = evidence.every(
      (row) =>
          row.data['mutation_status'] == 'applied' &&
          row.data['batch_status'] == 'completed',
    );
    DateTime? recognizedAt;
    for (final row in evidence) {
      if (row.data['mutation_status'] == 'applied' &&
          row.data['batch_status'] == 'completed') {
        final at = _dateOrNull(
          row.data['mutation_uploaded_at'] ?? row.data['batch_uploaded_at'],
        );
        if (at != null && (recognizedAt == null || at.isAfter(recognizedAt))) {
          recognizedAt = at;
        }
      }
    }
    if (allApplied) {
      final updatedAt = _dateOrNull(local['updated_at']);
      if (dirty &&
          recognizedAt != null &&
          updatedAt != null &&
          updatedAt.isAfter(recognizedAt)) {
        return CashPosEntityClassification(
          state: CashPosEntityState.dirtyWithoutOutbox,
          recognizedAt: recognizedAt,
        );
      }
      return CashPosEntityClassification(
        state: CashPosEntityState.remotelyApplied,
        recognizedAt: recognizedAt,
      );
    }
    final allPending = evidence.every(
      (row) =>
          row.data['mutation_status'] == 'pending' &&
          row.data['batch_status'] == 'pending',
    );
    return CashPosEntityClassification(
      state: allPending
          ? CashPosEntityState.pendingLocal
          : CashPosEntityState.transportAmbiguous,
      recognizedAt: recognizedAt,
    );
  }

  Future<bool> _isAuthoritativeSupersededSaleReconciliation({
    required String profileId,
    required String businessId,
    required String branchId,
    required String entityTable,
    required String entityId,
    required String? parentSaleId,
    required String remoteCashSessionId,
    required Map<String, dynamic> local,
    required bool dirty,
    required List<(String, String)> targets,
    required List<QueryRow> evidence,
  }) async {
    if (dirty ||
        local['deleted_at'] != null ||
        !const {'sales', 'sale_items', 'sale_payments'}.contains(entityTable)) {
      return false;
    }

    final saleId = entityTable == 'sales' ? entityId : parentSaleId;
    if (saleId == null || saleId.isEmpty) return false;
    if (entityTable != 'sales' && local['sale_id']?.toString() != saleId) {
      return false;
    }
    if (entityTable == 'sale_payments' &&
        (local['business_id']?.toString() != businessId ||
            local['branch_id']?.toString() != branchId)) {
      return false;
    }

    final localMetadata = _decodeMetadata(local['metadata_json']);
    final reconciliationId =
        localMetadata?['sale_reconciliation_id']?.toString().trim();
    if (localMetadata?['local_resolution'] !=
            'intentional_stale_sale_reconciled' ||
        reconciliationId == null ||
        reconciliationId.isEmpty ||
        localMetadata?['destination_cash_session_id']?.toString() !=
            remoteCashSessionId) {
      return false;
    }

    final sale =
        entityTable == 'sales' ? local : await getById('sales', saleId);
    final saleMetadata = _decodeMetadata(sale?['metadata_json']);
    if (sale == null ||
        sale['business_id']?.toString() != businessId ||
        sale['branch_id']?.toString() != branchId ||
        sale['cash_session_id']?.toString() != remoteCashSessionId ||
        sale['local_status']?.toString() != 'synced' ||
        sale['sync_status'] != SyncStatus.synced.index ||
        sale['deleted_at'] != null ||
        saleMetadata?['local_resolution'] !=
            'intentional_stale_sale_reconciled' ||
        saleMetadata?['sale_reconciliation_id']?.toString() !=
            reconciliationId ||
        saleMetadata?['destination_cash_session_id']?.toString() !=
            remoteCashSessionId) {
      return false;
    }

    final evidenceTargets = evidence
        .map(
          (row) => (
            row.data['entity_table']?.toString() ?? '',
            row.data['entity_id']?.toString() ?? '',
          ),
        )
        .toSet();
    if (!targets.every(evidenceTargets.contains)) return false;

    for (final row in evidence) {
      final data = row.data;
      final metadata = _decodeMetadata(data['mutation_metadata_json']);
      final explicitMarker =
          metadata?['superseded_by_sale_reconciliation'] == true;
      // Reconciliations written before the explicit boolean marker still carry
      // the full immutable audit tuple. Never recognize a generic skipped row.
      final legacyAuthoritativeMarker = metadata?['local_resolution'] ==
              'intentional_stale_sale_reconciled' &&
          metadata?['sale_reconciliation_id']?.toString() == reconciliationId;
      if (data['business_id']?.toString() != businessId ||
          data['branch_id']?.toString() != branchId ||
          data['mutation_status'] != 'skipped' ||
          _dateOrNull(data['mutation_resolved_at']) == null ||
          data['mutation_error_code'] != 'superseded_by_sale_reconciliation' ||
          (!explicitMarker && !legacyAuthoritativeMarker) ||
          metadata?['local_resolution'] !=
              'intentional_stale_sale_reconciled' ||
          metadata?['sale_reconciliation_id']?.toString() != reconciliationId ||
          metadata?['sale_id']?.toString() != saleId ||
          metadata?['destination_cash_session_id']?.toString() !=
              remoteCashSessionId) {
        return false;
      }
    }

    final relatedIds = {entityId, saleId};
    final blockingRows = await _db.customSelect(
      '''
      select entity_id, metadata_json
      from local_reconciliation_issues
      where profile_id = ? and business_id = ? and branch_id = ?
        and severity = 'blocking' and status = 'open'
      ''',
      variables: [
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
      readsFrom: {_db.localReconciliationIssues},
    ).get();
    return !blockingRows.any((row) {
      final metadata = _decodeMetadata(row.data['metadata_json']);
      return relatedIds.contains(row.data['entity_id']?.toString()) ||
          metadata?['sale_id']?.toString() == saleId ||
          (metadata?['source_type']?.toString() == 'sale' &&
              metadata?['source_id']?.toString() == saleId);
    });
  }

  Future<void> applyCashRegister(CashRegisterSnapshotRow row) async {
    final existing = await getById('cash_registers', row.id);
    await _statement(
      '''
      insert into cash_registers (
        id, business_id, branch_id, name, code, status, idempotency_key,
        local_status, sync_status, version, metadata_json, created_at,
        updated_at, deleted_at, last_synced_at
      ) values (?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?, ?, ?, ?, ?, ?)
      on conflict(id) do update set
        business_id = excluded.business_id,
        branch_id = excluded.branch_id,
        name = excluded.name,
        status = excluded.status,
        local_status = 'synced',
        sync_status = excluded.sync_status,
        version = excluded.version,
        metadata_json = excluded.metadata_json,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        last_synced_at = excluded.last_synced_at
      ''',
      [
        row.id,
        row.businessId,
        row.branchId,
        row.name,
        existing?['code'],
        row.state == OperationalBootstrapRecordState.tombstone
            ? 'inactive'
            : row.status,
        existing?['idempotency_key'],
        SyncStatus.synced.index,
        row.version,
        _mergeMetadata(existing?['metadata_json'], {
          'recovery_source': 'cash_pos_snapshot',
        }),
        row.createdAt,
        row.updatedAt,
        row.state == OperationalBootstrapRecordState.tombstone
            ? row.deletedAt ?? row.updatedAt
            : row.deletedAt,
        row.updatedAt,
      ],
    );
  }

  Future<bool> tryRetireOrphanLegacyCashRegister({
    required Map<String, dynamic> legacy,
    required String canonicalCashRegisterId,
    required String businessId,
    required String branchId,
  }) async {
    final legacyId = legacy['id']?.toString().trim() ?? '';
    final idempotencyKey = legacy['idempotency_key']?.toString().trim() ?? '';
    final metadata = _decodeMetadata(legacy['metadata_json']);
    final isGeneratedOpeningPlaceholder =
        metadata?['source'] == 'cash_session_local_dao' &&
            metadata?['flow'] == 'open_cash_session';

    if (legacyId.isEmpty ||
        legacyId == canonicalCashRegisterId ||
        legacy['business_id'] != businessId ||
        legacy['branch_id'] != branchId ||
        legacy['status'] != 'active' ||
        legacy['local_status'] != 'dirty' ||
        legacy['sync_status'] != SyncStatus.pendingInsert.index ||
        legacy['deleted_at'] != null ||
        legacy['last_synced_at'] != null ||
        !isGeneratedOpeningPlaceholder ||
        !idempotencyKey.contains(
          ':cash_registers:$businessId:$branchId:',
        )) {
      return false;
    }

    final references = await _db.customSelect(
      '''
      select
        (select count(*) from cash_sessions
          where cash_register_id = ?) as session_count,
        (select count(*) from sales
          where cash_register_id = ?) as sale_count,
        (select count(*) from local_sync_mutations
          where entity_id = ?
             or instr(coalesce(payload_json, ''), ?) > 0
             or instr(coalesce(before_payload_json, ''), ?) > 0
             or instr(coalesce(metadata_json, ''), ?) > 0) as mutation_count,
        (select count(*) from local_reconciliation_issues
          where entity_type = 'cash_registers'
            and entity_id = ?
            and status = 'open'
            and issue_type <> 'canonical_entity_conflict') as other_issue_count
      ''',
      variables: [
        Variable<String>(legacyId),
        Variable<String>(legacyId),
        Variable<String>(legacyId),
        Variable<String>(legacyId),
        Variable<String>(legacyId),
        Variable<String>(legacyId),
        Variable<String>(legacyId),
      ],
      readsFrom: {
        _db.cashSessions,
        _db.sales,
        _db.localSyncMutations,
        _db.localReconciliationIssues,
      },
    ).getSingle();

    if (_count(references.data['session_count']) > 0 ||
        _count(references.data['sale_count']) > 0 ||
        _count(references.data['mutation_count']) > 0 ||
        _count(references.data['other_issue_count']) > 0) {
      return false;
    }

    final now = DateTime.now().toUtc();
    final retiredMetadata = _mergeMetadata(legacy['metadata_json'], {
      'recovery_reconciliation': 'retired_orphan_legacy_cash_register',
      'canonical_cash_register_id': canonicalCashRegisterId,
      'reconciled_at': now.toIso8601String(),
    });
    final changed = await _db.customUpdate(
      '''
      update cash_registers
      set status = 'inactive',
          local_status = 'synced',
          sync_status = ?,
          metadata_json = ?,
          updated_at = ?,
          deleted_at = ?
      where id = ?
        and business_id = ?
        and branch_id = ?
        and status = 'active'
        and local_status = 'dirty'
        and sync_status = ?
        and deleted_at is null
        and last_synced_at is null
      ''',
      variables: [
        Variable<int>(SyncStatus.synced.index),
        Variable<String>(retiredMetadata),
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(legacyId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<int>(SyncStatus.pendingInsert.index),
      ],
      updates: {_db.cashRegisters},
    );
    return changed == 1;
  }

  Future<void> applyCashSession(CashSessionSnapshotRow row) async {
    final openedBy = await profileExists(row.openedByProfileId)
        ? row.openedByProfileId
        : null;
    final existing = await getById('cash_sessions', row.id);
    await _statement(
      '''
      insert into cash_sessions (
        id, business_id, branch_id, cash_register_id, opened_by_profile_id,
        closed_by_profile_id, opened_at, closed_at, opening_cash_amount,
        closing_cash_amount, expected_cash_amount, difference_amount, status,
        idempotency_key, local_status, sync_status, version, metadata_json,
        created_at, updated_at, deleted_at, last_synced_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?, ?, ?, ?, ?, ?)
      on conflict(id) do update set
        business_id = excluded.business_id,
        branch_id = excluded.branch_id,
        cash_register_id = excluded.cash_register_id,
        opened_by_profile_id = excluded.opened_by_profile_id,
        closed_by_profile_id = excluded.closed_by_profile_id,
        opened_at = excluded.opened_at,
        closed_at = excluded.closed_at,
        opening_cash_amount = excluded.opening_cash_amount,
        closing_cash_amount = excluded.closing_cash_amount,
        expected_cash_amount = excluded.expected_cash_amount,
        difference_amount = excluded.difference_amount,
        status = excluded.status,
        local_status = 'synced',
        sync_status = excluded.sync_status,
        version = excluded.version,
        metadata_json = excluded.metadata_json,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        last_synced_at = excluded.last_synced_at
      ''',
      [
        row.id,
        row.businessId,
        row.branchId,
        row.cashRegisterId,
        openedBy,
        row.closedByProfileId != null &&
                await profileExists(row.closedByProfileId!)
            ? row.closedByProfileId
            : null,
        row.openedAt,
        row.closedAt,
        row.openingCashAmount,
        row.closingCashAmount,
        row.expectedCashAmount,
        row.differenceAmount,
        row.state == OperationalBootstrapRecordState.tombstone
            ? 'cancelled'
            : row.status,
        existing?['idempotency_key'],
        SyncStatus.synced.index,
        row.version,
        _mergeMetadata(existing?['metadata_json'], {
          'recovery_source': 'cash_pos_snapshot',
          'remote_opened_by_profile_id': row.openedByProfileId,
          if (row.closedByProfileId != null)
            'remote_closed_by_profile_id': row.closedByProfileId,
        }),
        row.createdAt,
        row.updatedAt,
        row.state == OperationalBootstrapRecordState.tombstone
            ? row.deletedAt ?? row.updatedAt
            : row.deletedAt,
        row.updatedAt,
      ],
    );
  }

  Future<void> applySale(
    CashPosSaleSnapshotRow row, {
    required String cashRegisterId,
  }) async {
    final existing = await getById('sales', row.id);
    final userId = row.userId != null && await profileExists(row.userId!)
        ? row.userId
        : null;
    final customerId =
        row.customerId != null && await customerExists(row.customerId!)
            ? row.customerId
            : null;
    await _statement(
      '''
      insert into sales (
        id, business_id, user_id, customer_id, branch_id, cash_register_id,
        cash_session_id, subtotal, discount_total, tax_total, total,
        payment_method, payment_status, idempotency_key, local_status,
        metadata_json, status, created_at, updated_at, deleted_at, sync_status
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?, ?, ?, ?, ?)
      on conflict(id) do update set
        business_id = excluded.business_id,
        user_id = excluded.user_id,
        customer_id = excluded.customer_id,
        branch_id = excluded.branch_id,
        cash_register_id = excluded.cash_register_id,
        cash_session_id = excluded.cash_session_id,
        subtotal = excluded.subtotal,
        discount_total = excluded.discount_total,
        tax_total = excluded.tax_total,
        total = excluded.total,
        payment_method = excluded.payment_method,
        payment_status = excluded.payment_status,
        idempotency_key = excluded.idempotency_key,
        local_status = 'synced',
        metadata_json = excluded.metadata_json,
        status = excluded.status,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        sync_status = excluded.sync_status
      ''',
      [
        row.id,
        row.businessId,
        userId,
        customerId,
        row.branchId,
        cashRegisterId,
        row.cashSessionId,
        row.subtotal,
        row.discountTotal,
        row.taxTotal,
        row.total,
        row.paymentMethod,
        row.paymentStatus,
        row.idempotencyKey,
        _mergeMetadata(existing?['metadata_json'], {
          ...?row.metadata,
          'recovery_source': 'cash_pos_snapshot',
          if (row.userId != null) 'remote_user_id': row.userId,
          if (row.customerId != null) 'remote_customer_id': row.customerId,
        }),
        row.status,
        row.createdAt,
        row.updatedAt,
        row.state == OperationalBootstrapRecordState.tombstone
            ? row.deletedAt ?? row.updatedAt
            : row.deletedAt,
        SyncStatus.synced.index,
      ],
    );
  }

  Future<void> applySaleItem(CashPosSaleItemSnapshotRow row) async {
    final existing = await getById('sale_items', row.id);
    await _statement(
      '''
      insert into sale_items (
        id, sale_id, product_id, product_name_snapshot, barcode_snapshot,
        quantity, unit_price, discount_total, tax_total, subtotal, line_total,
        metadata_json, created_at, updated_at, deleted_at, sync_status
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(id) do update set
        sale_id = excluded.sale_id,
        product_id = excluded.product_id,
        product_name_snapshot = excluded.product_name_snapshot,
        barcode_snapshot = excluded.barcode_snapshot,
        quantity = excluded.quantity,
        unit_price = excluded.unit_price,
        discount_total = excluded.discount_total,
        tax_total = excluded.tax_total,
        subtotal = excluded.subtotal,
        line_total = excluded.line_total,
        metadata_json = excluded.metadata_json,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        sync_status = excluded.sync_status
      ''',
      [
        row.id,
        row.saleId,
        row.productId,
        row.productNameSnapshot,
        row.barcodeSnapshot,
        row.quantity,
        row.unitPrice,
        row.discountTotal,
        row.taxTotal,
        row.subtotal,
        row.lineTotal,
        _mergeMetadata(existing?['metadata_json'], {
          ...?row.metadata,
          'recovery_source': 'cash_pos_snapshot',
        }),
        row.createdAt,
        row.updatedAt,
        row.state == OperationalBootstrapRecordState.tombstone
            ? row.deletedAt ?? row.updatedAt
            : row.deletedAt,
        SyncStatus.synced.index,
      ],
    );
  }

  Future<void> applySalePayment(
    CashPosSalePaymentSnapshotRow row, {
    required String branchId,
  }) async {
    final existing = await getById('sale_payments', row.id);
    await _statement(
      '''
      insert into sale_payments (
        id, business_id, branch_id, sale_id, payment_method, amount, currency,
        status, reference, metadata_json, sync_status, local_status,
        created_at, updated_at, deleted_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?, ?)
      on conflict(id) do update set
        business_id = excluded.business_id,
        branch_id = excluded.branch_id,
        sale_id = excluded.sale_id,
        payment_method = excluded.payment_method,
        amount = excluded.amount,
        currency = excluded.currency,
        status = excluded.status,
        reference = excluded.reference,
        metadata_json = excluded.metadata_json,
        sync_status = excluded.sync_status,
        local_status = 'synced',
        created_at = excluded.created_at,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at
      ''',
      [
        row.id,
        row.businessId,
        branchId,
        row.saleId,
        row.paymentMethod,
        row.amount,
        row.currency,
        row.status,
        row.reference,
        _mergeMetadata(existing?['metadata_json'], {
          ...?row.metadata,
          'recovery_source': 'cash_pos_snapshot',
        }),
        SyncStatus.synced.index,
        row.createdAt,
        row.updatedAt,
        row.state == OperationalBootstrapRecordState.tombstone
            ? row.deletedAt ?? row.updatedAt
            : row.deletedAt,
      ],
    );
  }

  Future<List<Map<String, dynamic>>> rowsForScope({
    required String table,
    required String businessId,
    required String branchId,
    String? cashSessionId,
  }) async {
    final sessionFilter =
        cashSessionId == null ? '' : 'and cash_session_id = ?';
    final rows = await _db.customSelect(
      'select * from $table where business_id = ? and branch_id = ? '
      'and deleted_at is null $sessionFilter order by id',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        if (cashSessionId != null) Variable<String>(cashSessionId),
      ],
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  Future<List<Map<String, dynamic>>> openSessionsForRegister({
    required String businessId,
    required String branchId,
    required String cashRegisterId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select * from cash_sessions
      where business_id = ? and branch_id = ? and cash_register_id = ?
        and status = 'open' and deleted_at is null
      order by opened_at, id
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(cashRegisterId),
      ],
      readsFrom: {_db.cashSessions},
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  Future<bool> reconcileRejectedSaleOriginalOpenSession({
    required String profileId,
    required String businessId,
    required String branchId,
    required String cashRegisterId,
    required String originalCashSessionId,
    required String? remoteOpenCashSessionId,
    required String saleId,
  }) {
    return _db.transaction(() async {
      if (remoteOpenCashSessionId == originalCashSessionId) return false;
      final session = await getById('cash_sessions', originalCashSessionId);
      final sale = await getById('sales', saleId);
      if (session == null ||
          sale == null ||
          session['business_id']?.toString() != businessId ||
          session['branch_id']?.toString() != branchId ||
          session['cash_register_id']?.toString() != cashRegisterId ||
          session['status']?.toString() != 'open' ||
          session['deleted_at'] != null ||
          sale['business_id']?.toString() != businessId ||
          sale['branch_id']?.toString() != branchId ||
          sale['cash_register_id']?.toString() != cashRegisterId ||
          sale['cash_session_id']?.toString() != originalCashSessionId ||
          sale['deleted_at'] != null) {
        return false;
      }
      final classification = await classify(
        businessId: businessId,
        branchId: branchId,
        domain: 'cash',
        entityTable: 'cash_sessions',
        entityId: originalCashSessionId,
        local: session,
      );
      if (!classification.canAcceptRemote) return false;

      final staleIssue = await _db.customSelect(
        '''
        select metadata_json
        from local_reconciliation_issues
        where profile_id = ? and business_id = ? and branch_id = ?
          and domain = 'cash_pos' and entity_type = 'sales'
          and entity_id = ? and issue_type = 'sale_cash_session_rejected'
          and severity = 'blocking' and status = 'open'
        limit 1
        ''',
        variables: [
          Variable<String>(profileId),
          Variable<String>(businessId),
          Variable<String>(branchId),
          Variable<String>(saleId),
        ],
        readsFrom: {_db.localReconciliationIssues},
      ).getSingleOrNull();
      final staleMetadata = _decodeMetadata(staleIssue?.data['metadata_json']);
      if (staleMetadata?['remote_reason']?.toString() != 'closed' ||
          staleMetadata?['cash_session_id']?.toString() !=
              originalCashSessionId) {
        return false;
      }

      QueryRow? conflict;
      if (remoteOpenCashSessionId != null) {
        conflict = await _db.customSelect(
          '''
        select id, metadata_json
        from local_reconciliation_issues
        where profile_id = ? and business_id = ? and branch_id = ?
          and domain = 'cash_pos' and entity_type = 'cash_sessions'
          and entity_id = ? and issue_type = 'cash_open_session_conflict'
          and severity = 'blocking' and status = 'open'
        limit 1
        ''',
          variables: [
            Variable<String>(profileId),
            Variable<String>(businessId),
            Variable<String>(branchId),
            Variable<String>(originalCashSessionId),
          ],
          readsFrom: {_db.localReconciliationIssues},
        ).getSingleOrNull();
        final conflictMetadata =
            _decodeMetadata(conflict?.data['metadata_json']);
        final localIds = conflictMetadata?['local_open_session_ids'];
        if (conflict == null ||
            conflictMetadata?['remote_cash_session_id']?.toString() !=
                remoteOpenCashSessionId ||
            conflictMetadata?['cash_register_id']?.toString() !=
                cashRegisterId ||
            localIds is! List ||
            !localIds.map((value) => value.toString()).contains(
                  originalCashSessionId,
                )) {
          return false;
        }
      }

      final now = DateTime.now().toUtc();
      final metadata = _mergeMetadata(session['metadata_json'], {
        'recovery_reconciliation':
            'projected_server_rejected_sale_original_cash_session_closed',
        'sale_id': saleId,
        if (remoteOpenCashSessionId != null)
          'remote_open_cash_session_id': remoteOpenCashSessionId,
        'reconciled_at': now.toIso8601String(),
      });
      final changed = await _db.customUpdate(
        '''
        update cash_sessions
        set status = 'closed', local_status = 'synced', sync_status = ?,
            metadata_json = ?, updated_at = ?, deleted_at = null,
            last_synced_at = ?
        where id = ? and business_id = ? and branch_id = ?
          and cash_register_id = ? and status = 'open'
          and deleted_at is null
        ''',
        variables: [
          Variable<int>(SyncStatus.synced.index),
          Variable<String>(metadata),
          Variable<DateTime>(now),
          Variable<DateTime>(now),
          Variable<String>(originalCashSessionId),
          Variable<String>(businessId),
          Variable<String>(branchId),
          Variable<String>(cashRegisterId),
        ],
        updates: {_db.cashSessions},
      );
      if (changed != 1) return false;
      if (conflict != null) {
        await _db.customUpdate(
          '''
        update local_reconciliation_issues
        set status = 'resolved', resolved_at = ?, updated_at = ?
        where id = ? and status = 'open'
        ''',
          variables: [
            Variable<DateTime>(now),
            Variable<DateTime>(now),
            Variable<String>(conflict.read<String>('id')),
          ],
          updates: {_db.localReconciliationIssues},
        );
      }
      return true;
    });
  }

  Future<List<Map<String, dynamic>>> salesForSession(String cashSessionId) {
    return _rowsByForeignKey('sales', 'cash_session_id', cashSessionId);
  }

  Future<List<Map<String, dynamic>>> saleItemsForSale(String saleId) {
    return _rowsByForeignKey('sale_items', 'sale_id', saleId);
  }

  Future<List<Map<String, dynamic>>> salePaymentsForSale(String saleId) {
    return _rowsByForeignKey('sale_payments', 'sale_id', saleId);
  }

  Future<List<Map<String, dynamic>>> _rowsByForeignKey(
    String table,
    String column,
    String value,
  ) async {
    final rows = await _db.customSelect(
      'select * from $table where $column = ? and deleted_at is null order by id',
      variables: [Variable<String>(value)],
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  Future<bool> productExistsForBusiness(String id, String businessId) =>
      _exists('products', id, businessId: businessId);

  Future<bool> profileExists(String id) => _exists('profiles', id);

  Future<bool> customerExists(String id) => _exists('customers', id);

  Future<bool> _exists(
    String table,
    String id, {
    String? businessId,
  }) async {
    final row = await _db.customSelect(
      'select 1 from $table where id = ? '
      '${businessId == null ? '' : 'and business_id = ? '}limit 1',
      variables: [
        Variable<String>(id),
        if (businessId != null) Variable<String>(businessId),
      ],
    ).getSingleOrNull();
    return row != null;
  }

  Future<void> softInvalidate({
    required String table,
    required String id,
    required DateTime at,
  }) async {
    final status = switch (table) {
      'cash_registers' => ", status = 'inactive'",
      'cash_sessions' => ", status = 'cancelled'",
      _ => '',
    };
    final localStatus =
        table == 'sale_items' ? '' : ", local_status = 'synced'";
    await _statement(
      'update $table set deleted_at = ?, updated_at = ?, sync_status = ?'
      '$localStatus$status where id = ?',
      [at, at, SyncStatus.synced.index, id],
    );
  }

  Future<int> countSalesForSession(String cashSessionId) async {
    final row = await _db.customSelect(
      'select count(*) as count from sales where cash_session_id = ? '
      'and deleted_at is null',
      variables: [Variable<String>(cashSessionId)],
      readsFrom: {_db.sales},
    ).getSingle();
    return (row.data['count'] as num).toInt();
  }

  Future<void> _statement(String sql, List<Object?> values) =>
      _db.customStatement(sql, normalizeSqliteParameters(values));

  String _mergeMetadata(Object? existing, Map<String, Object?> extra) {
    final decoded = <String, Object?>{};
    if (existing is String && existing.isNotEmpty) {
      try {
        final value = jsonDecode(existing);
        if (value is Map) {
          decoded.addAll(value.map((key, item) => MapEntry('$key', item)));
        }
      } on FormatException {
        // Replace malformed legacy metadata with valid recovery provenance.
      }
    }
    return jsonEncode({...decoded, ...extra});
  }

  Map<String, Object?>? _decodeMetadata(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry('$key', item));
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  int _count(Object? value) => value is num ? value.toInt() : 0;

  DateTime? _dateOrNull(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is int) {
      final milliseconds = value.abs() < 100000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }
}
