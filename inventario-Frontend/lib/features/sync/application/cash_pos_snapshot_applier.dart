import 'dart:convert';

import '../data/datasources/cash_pos_reconciliation_local_dao.dart';
import '../data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/models/cash_pos_recovery_models.dart';
import '../data/models/local_recovery_models.dart';
import '../data/models/operational_bootstrap_models.dart';
import 'operational_bootstrap_page_applier.dart';

class CashPosSnapshotApplier
    implements
        OperationalBootstrapPageApplier,
        OperationalBootstrapDatasetFinalizer {
  CashPosSnapshotApplier({
    required CashPosReconciliationLocalDao localDao,
    required OperationalBootstrapSeenRecordLocalDao seenRecordDao,
    required ReconciliationIssueLocalDao issueDao,
  })  : _localDao = localDao,
        _seenRecordDao = seenRecordDao,
        _issueDao = issueDao;

  final CashPosReconciliationLocalDao _localDao;
  final OperationalBootstrapSeenRecordLocalDao _seenRecordDao;
  final ReconciliationIssueLocalDao _issueDao;

  static const datasets = [
    'cash_registers',
    'open_cash_sessions',
    'session_sales',
    'session_sale_items',
    'session_sale_payments',
  ];

  @override
  Future<OperationalBootstrapPageApplyResult> applyPage({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  }) async {
    _validatePage(snapshot, page);
    final seen = <String>[];
    var blocked = false;
    for (final raw in page.rows) {
      final id = raw.entityId;
      if (id == null) {
        throw const OperationalBootstrapException(
          kind: OperationalBootstrapFailureKind.malformedResponse,
          message: 'Cash/POS snapshot row has no ID.',
        );
      }
      seen.add(id);
      final applied = switch (page.dataset) {
        'cash_registers' => await _applyRegister(
            profileId,
            snapshot,
            CashRegisterSnapshotRow.fromRow(raw),
          ),
        'open_cash_sessions' => await _applySession(
            profileId,
            snapshot,
            CashSessionSnapshotRow.fromRow(raw),
          ),
        'session_sales' => await _applySale(
            profileId,
            snapshot,
            CashPosSaleSnapshotRow.fromRow(raw),
          ),
        'session_sale_items' => await _applyItem(
            profileId,
            snapshot,
            CashPosSaleItemSnapshotRow.fromRow(raw),
          ),
        'session_sale_payments' => await _applyPayment(
            profileId,
            snapshot,
            CashPosSalePaymentSnapshotRow.fromRow(raw),
          ),
        _ => false,
      };
      blocked = blocked || !applied;
    }
    return OperationalBootstrapPageApplyResult(
      seenEntityIds: seen,
      completeConvergenceStatus: blocked ? 'blocked' : 'complete',
    );
  }

  Future<bool> _applyRegister(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    CashRegisterSnapshotRow remote,
  ) async {
    if (!_scopeMatches(snapshot, remote.businessId, remote.branchId)) {
      return _dependencyIssue(
        profileId,
        snapshot,
        entityType: 'cash_registers',
        entityId: remote.id,
        issueType: 'scope_mismatch',
        message: 'Cash register belongs to another business or branch.',
      );
    }
    final local = await _localDao.getById('cash_registers', remote.id);
    if (local != null) {
      final classification = await _classify(
        snapshot,
        'cash',
        'cash_registers',
        remote.id,
        local,
      );
      if (!classification.canAcceptRemote) {
        await _preservedIssue(
          profileId,
          snapshot,
          entityType: 'cash_registers',
          entityId: remote.id,
          classification: classification,
          tombstone: remote.state == OperationalBootstrapRecordState.tombstone,
        );
        return false;
      }
    }
    await _localDao.applyCashRegister(remote);
    if (remote.state == OperationalBootstrapRecordState.present) {
      final duplicates = await _localDao.rowsForScope(
        table: 'cash_registers',
        businessId: snapshot.businessId,
        branchId: snapshot.branchId,
      );
      for (final candidate in duplicates) {
        if (candidate['id'] == remote.id ||
            candidate['name']?.toString().toLowerCase() !=
                remote.name.toLowerCase()) {
          continue;
        }
        final classification = await _classify(
          snapshot,
          'cash',
          'cash_registers',
          candidate['id'].toString(),
          candidate,
        );
        if (!classification.canAcceptRemote) {
          final retired = await _localDao.tryRetireOrphanLegacyCashRegister(
            legacy: candidate,
            canonicalCashRegisterId: remote.id,
            businessId: snapshot.businessId,
            branchId: snapshot.branchId,
          );
          if (retired) {
            await _issueDao.resolveOpenIssue(
              profileId: profileId,
              businessId: snapshot.businessId,
              branchId: snapshot.branchId,
              domain: 'cash_pos',
              issueType: 'canonical_entity_conflict',
              entityType: 'cash_registers',
              entityId: candidate['id'].toString(),
            );
            continue;
          }
          await _openIssue(
            profileId,
            snapshot,
            entityType: 'cash_registers',
            entityId: candidate['id'].toString(),
            issueType: 'canonical_entity_conflict',
            severity: 'blocking',
            message:
                'A legacy dirty cash register conflicts with canonical register ${remote.id}.',
            metadata: {'canonical_cash_register_id': remote.id},
          );
        }
      }
    }
    await _resolveEntityIssues(
      profileId,
      snapshot,
      entityType: 'cash_registers',
      entityId: remote.id,
    );
    return true;
  }

  Future<bool> _applySession(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    CashSessionSnapshotRow remote,
  ) async {
    if (!_scopeMatches(snapshot, remote.businessId, remote.branchId)) {
      return _dependencyIssue(
        profileId,
        snapshot,
        entityType: 'cash_sessions',
        entityId: remote.id,
        issueType: 'scope_mismatch',
        message: 'Cash session belongs to another business or branch.',
      );
    }
    final register = await _localDao.getById(
      'cash_registers',
      remote.cashRegisterId,
    );
    if (register == null ||
        register['business_id'] != snapshot.businessId ||
        register['branch_id'] != snapshot.branchId ||
        register['deleted_at'] != null) {
      return _dependencyIssue(
        profileId,
        snapshot,
        entityType: 'cash_sessions',
        entityId: remote.id,
        issueType: 'dependency_missing',
        message: 'Cash session references an unavailable canonical register.',
        metadata: {'cash_register_id': remote.cashRegisterId},
      );
    }
    final local = await _localDao.getById('cash_sessions', remote.id);
    if (local != null) {
      final classification = await _classify(
        snapshot,
        'cash',
        'cash_sessions',
        remote.id,
        local,
      );
      if (!classification.canAcceptRemote) {
        final tombstone =
            remote.state == OperationalBootstrapRecordState.tombstone;
        if (tombstone ||
            classification.state == CashPosEntityState.dirtyWithoutOutbox ||
            !_sessionEquivalent(local, remote)) {
          await _preservedIssue(
            profileId,
            snapshot,
            entityType: 'cash_sessions',
            entityId: remote.id,
            classification: classification,
            tombstone: tombstone,
          );
        }
        return false;
      }
    }
    if (remote.state == OperationalBootstrapRecordState.present &&
        remote.status == 'open') {
      final open = await _localDao.openSessionsForRegister(
        businessId: snapshot.businessId,
        branchId: snapshot.branchId,
        cashRegisterId: remote.cashRegisterId,
      );
      final conflicts = open.where((row) => row['id'] != remote.id).toList();
      if (conflicts.isNotEmpty) {
        await _openIssue(
          profileId,
          snapshot,
          entityType: 'cash_sessions',
          entityId: conflicts.first['id'].toString(),
          issueType: 'cash_open_session_conflict',
          severity: 'blocking',
          message:
              'Remote open session ${remote.id} conflicts with an existing local open session.',
          metadata: {
            'remote_cash_session_id': remote.id,
            'cash_register_id': remote.cashRegisterId,
            'local_open_session_ids':
                conflicts.map((row) => row['id']).toList(),
          },
        );
        return false;
      }
    }
    await _localDao.applyCashSession(remote);
    await _resolveEntityIssues(
      profileId,
      snapshot,
      entityType: 'cash_sessions',
      entityId: remote.id,
    );
    return true;
  }

  Future<bool> _applySale(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    CashPosSaleSnapshotRow remote,
  ) async {
    if (!_scopeMatches(snapshot, remote.businessId, remote.branchId)) {
      return _dependencyIssue(
        profileId,
        snapshot,
        entityType: 'sales',
        entityId: remote.id,
        issueType: 'scope_mismatch',
        message: 'Sale belongs to another business or branch.',
      );
    }
    final session =
        await _localDao.getById('cash_sessions', remote.cashSessionId);
    if (session == null ||
        session['business_id'] != snapshot.businessId ||
        session['branch_id'] != snapshot.branchId ||
        session['status'] != 'open' ||
        session['deleted_at'] != null) {
      return _dependencyIssue(
        profileId,
        snapshot,
        entityType: 'sales',
        entityId: remote.id,
        issueType: 'dependency_missing',
        message: 'Sale references an unavailable remote open cash session.',
        metadata: {'cash_session_id': remote.cashSessionId},
      );
    }
    final local = await _localDao.getById('sales', remote.id);
    if (local != null) {
      final classification = await _classify(
        snapshot,
        'pos',
        'sales',
        remote.id,
        local,
        profileId: profileId,
        remoteCashSessionId: remote.cashSessionId,
      );
      if (!classification.canAcceptRemote) {
        await _preservedIssue(
          profileId,
          snapshot,
          entityType: 'sales',
          entityId: remote.id,
          classification: classification,
          tombstone: remote.state == OperationalBootstrapRecordState.tombstone,
        );
        return false;
      }
    }
    await _localDao.applySale(
      remote,
      cashRegisterId: session['cash_register_id'].toString(),
    );
    await _resolveEntityIssues(
      profileId,
      snapshot,
      entityType: 'sales',
      entityId: remote.id,
    );
    return true;
  }

  Future<bool> _applyItem(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    CashPosSaleItemSnapshotRow remote,
  ) async {
    final sale = await _localDao.getById('sales', remote.saleId);
    if (sale == null ||
        sale['business_id'] != snapshot.businessId ||
        sale['branch_id'] != snapshot.branchId ||
        sale['deleted_at'] != null) {
      return _dependencyIssue(
        profileId,
        snapshot,
        entityType: 'sale_items',
        entityId: remote.id,
        issueType: 'dependency_missing',
        message: 'Sale item references an unavailable parent sale.',
        metadata: {'sale_id': remote.saleId},
      );
    }
    if (remote.productId != null &&
        !await _localDao.productExistsForBusiness(
          remote.productId!,
          snapshot.businessId,
        )) {
      return _dependencyIssue(
        profileId,
        snapshot,
        entityType: 'sale_items',
        entityId: remote.id,
        issueType: 'dependency_missing',
        message: 'Sale item references an unavailable product.',
        metadata: {'product_id': remote.productId, 'sale_id': remote.saleId},
      );
    }
    final local = await _localDao.getById('sale_items', remote.id);
    if (local != null) {
      final classification = await _classify(
        snapshot,
        'pos',
        'sale_items',
        remote.id,
        local,
        parentSaleId: remote.saleId,
        profileId: profileId,
        remoteCashSessionId: sale['cash_session_id']?.toString(),
      );
      if (!classification.canAcceptRemote) {
        await _preservedIssue(
          profileId,
          snapshot,
          entityType: 'sale_items',
          entityId: remote.id,
          classification: classification,
          tombstone: remote.state == OperationalBootstrapRecordState.tombstone,
        );
        return false;
      }
    }
    await _localDao.applySaleItem(remote);
    await _resolveEntityIssues(
      profileId,
      snapshot,
      entityType: 'sale_items',
      entityId: remote.id,
    );
    return true;
  }

  Future<bool> _applyPayment(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    CashPosSalePaymentSnapshotRow remote,
  ) async {
    final sale = await _localDao.getById('sales', remote.saleId);
    if (remote.businessId != snapshot.businessId ||
        sale == null ||
        sale['business_id'] != snapshot.businessId ||
        sale['branch_id'] != snapshot.branchId ||
        sale['deleted_at'] != null) {
      return _dependencyIssue(
        profileId,
        snapshot,
        entityType: 'sale_payments',
        entityId: remote.id,
        issueType: remote.businessId == snapshot.businessId
            ? 'dependency_missing'
            : 'scope_mismatch',
        message: 'Sale payment has an invalid scope or parent sale.',
        metadata: {'sale_id': remote.saleId},
      );
    }
    final local = await _localDao.getById('sale_payments', remote.id);
    if (local != null) {
      final classification = await _classify(
        snapshot,
        'pos',
        'sale_payments',
        remote.id,
        local,
        parentSaleId: remote.saleId,
        profileId: profileId,
        remoteCashSessionId: sale['cash_session_id']?.toString(),
      );
      if (!classification.canAcceptRemote) {
        await _preservedIssue(
          profileId,
          snapshot,
          entityType: 'sale_payments',
          entityId: remote.id,
          classification: classification,
          tombstone: remote.state == OperationalBootstrapRecordState.tombstone,
        );
        return false;
      }
    }
    await _localDao.applySalePayment(remote, branchId: snapshot.branchId);
    await _resolveEntityIssues(
      profileId,
      snapshot,
      entityType: 'sale_payments',
      entityId: remote.id,
    );
    return true;
  }

  @override
  Future<void> finalizeDataset({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  }) async {
    _validatePage(snapshot, page);
    final seen = await _seenIds(profileId, snapshot, page.dataset);
    if (page.dataset == 'cash_registers') {
      await _sweepRegisters(profileId, snapshot, seen);
    } else if (page.dataset == 'open_cash_sessions') {
      await _sweepSessions(profileId, snapshot, seen);
    } else if (page.dataset == 'session_sales') {
      await _sweepSales(profileId, snapshot, seen);
    } else if (page.dataset == 'session_sale_items') {
      await _sweepChildren(
        profileId,
        snapshot,
        seen,
        entityTable: 'sale_items',
      );
    } else if (page.dataset == 'session_sale_payments') {
      await _sweepChildren(
        profileId,
        snapshot,
        seen,
        entityTable: 'sale_payments',
      );
    }
  }

  Future<void> _sweepRegisters(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    Set<String> seen,
  ) async {
    for (final local in await _localDao.rowsForScope(
      table: 'cash_registers',
      businessId: snapshot.businessId,
      branchId: snapshot.branchId,
    )) {
      if (seen.contains(local['id']) || _afterSnapshot(local, snapshot)) {
        continue;
      }
      final classification = await _classify(
        snapshot,
        'cash',
        'cash_registers',
        local['id'].toString(),
        local,
      );
      if (classification.canAcceptRemote) {
        await _localDao.softInvalidate(
          table: 'cash_registers',
          id: local['id'].toString(),
          at: snapshot.snapshotAt,
        );
      }
    }
  }

  Future<void> _sweepSessions(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    Set<String> seen,
  ) async {
    for (final register in await _localDao.rowsForScope(
      table: 'cash_registers',
      businessId: snapshot.businessId,
      branchId: snapshot.branchId,
    )) {
      final sessions = await _localDao.openSessionsForRegister(
        businessId: snapshot.businessId,
        branchId: snapshot.branchId,
        cashRegisterId: register['id'].toString(),
      );
      if (sessions.length > 1) {
        await _openIssue(
          profileId,
          snapshot,
          entityType: 'cash_sessions',
          entityId: register['id'].toString(),
          issueType: 'multiple_clean_open_sessions',
          severity: 'blocking',
          message: 'More than one local session is open for the same register.',
        );
        continue;
      }
      for (final local in sessions) {
        if (seen.contains(local['id']) || _afterSnapshot(local, snapshot)) {
          continue;
        }
        final classification = await _classify(
          snapshot,
          'cash',
          'cash_sessions',
          local['id'].toString(),
          local,
        );
        // A dirty open session may be a valid offline operation not yet remote.
        if (classification.canAcceptRemote) {
          await _localDao.softInvalidate(
            table: 'cash_sessions',
            id: local['id'].toString(),
            at: snapshot.snapshotAt,
          );
        }
      }
    }
  }

  Future<void> _sweepSales(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    Set<String> seen,
  ) async {
    final remoteSessions = await _seenIds(
      profileId,
      snapshot,
      'open_cash_sessions',
    );
    for (final sessionId in remoteSessions) {
      for (final local in await _localDao.salesForSession(sessionId)) {
        if (seen.contains(local['id']) || _afterSnapshot(local, snapshot)) {
          continue;
        }
        final classification = await _classify(
          snapshot,
          'pos',
          'sales',
          local['id'].toString(),
          local,
        );
        if (classification.canAcceptRemote) {
          await _localDao.softInvalidate(
            table: 'sales',
            id: local['id'].toString(),
            at: snapshot.snapshotAt,
          );
        }
      }
    }
  }

  Future<void> _sweepChildren(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    Set<String> seen, {
    required String entityTable,
  }) async {
    final remoteSales = await _seenIds(profileId, snapshot, 'session_sales');
    for (final saleId in remoteSales) {
      final rows = entityTable == 'sale_items'
          ? await _localDao.saleItemsForSale(saleId)
          : await _localDao.salePaymentsForSale(saleId);
      for (final local in rows) {
        if (seen.contains(local['id']) || _afterSnapshot(local, snapshot)) {
          continue;
        }
        final classification = await _classify(
          snapshot,
          'pos',
          entityTable,
          local['id'].toString(),
          local,
          parentSaleId: saleId,
        );
        if (classification.canAcceptRemote) {
          await _localDao.softInvalidate(
            table: entityTable,
            id: local['id'].toString(),
            at: snapshot.snapshotAt,
          );
        }
      }
    }
  }

  void _validatePage(
    OperationalBootstrapSnapshotPage snapshot,
    OperationalBootstrapDatasetPage page,
  ) {
    if (snapshot.bundle != 'cash_pos' ||
        !datasets.contains(page.dataset) ||
        !snapshot.datasets.containsKey(page.dataset)) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message:
            'Cash/POS applier rejected ${snapshot.bundle}/${page.dataset}.',
      );
    }
  }

  bool _scopeMatches(
    OperationalBootstrapSnapshotPage snapshot,
    String businessId,
    String branchId,
  ) =>
      businessId == snapshot.businessId && branchId == snapshot.branchId;

  Future<CashPosEntityClassification> _classify(
    OperationalBootstrapSnapshotPage snapshot,
    String domain,
    String entityTable,
    String entityId,
    Map<String, dynamic> local, {
    String? parentSaleId,
    String? profileId,
    String? remoteCashSessionId,
  }) =>
      _localDao.classify(
        businessId: snapshot.businessId,
        branchId: snapshot.branchId,
        domain: domain,
        entityTable: entityTable,
        entityId: entityId,
        local: local,
        parentSaleId: parentSaleId,
        profileId: profileId,
        remoteCashSessionId: remoteCashSessionId,
      );

  Future<void> _preservedIssue(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot, {
    required String entityType,
    required String entityId,
    required CashPosEntityClassification classification,
    required bool tombstone,
  }) async {
    final orphan =
        classification.state == CashPosEntityState.dirtyWithoutOutbox;
    await _openIssue(
      profileId,
      snapshot,
      entityType: entityType,
      entityId: entityId,
      issueType: tombstone
          ? 'dirty_vs_tombstone'
          : orphan
              ? 'dirty_without_outbox'
              : 'dirty_vs_remote',
      severity: tombstone || orphan ? 'blocking' : 'warning',
      message: tombstone
          ? 'Dirty local Cash/POS state was preserved instead of applying a tombstone.'
          : 'Dirty local Cash/POS state was preserved instead of remote state.',
      metadata: {'classification': classification.state.name},
    );
  }

  bool _sessionEquivalent(
    Map<String, dynamic> local,
    CashSessionSnapshotRow remote,
  ) {
    return local['business_id']?.toString() == remote.businessId &&
        local['branch_id']?.toString() == remote.branchId &&
        local['cash_register_id']?.toString() == remote.cashRegisterId &&
        local['status']?.toString() == remote.status &&
        (local['opening_cash_amount'] as num?)?.toDouble() ==
            remote.openingCashAmount &&
        _sameDate(local['opened_at'], remote.openedAt) &&
        _sameDate(local['deleted_at'], remote.deletedAt);
  }

  bool _sameDate(Object? local, DateTime? remote) {
    final localDate = local is DateTime
        ? local.toUtc()
        : local is int
            ? DateTime.fromMillisecondsSinceEpoch(local, isUtc: true)
            : DateTime.tryParse(local?.toString() ?? '')?.toUtc();
    if (localDate == null || remote == null) {
      return localDate == null && remote == null;
    }
    return localDate.isAtSameMomentAs(remote);
  }

  Future<bool> _dependencyIssue(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot, {
    required String entityType,
    required String entityId,
    required String issueType,
    required String message,
    Map<String, Object?> metadata = const {},
  }) async {
    await _openIssue(
      profileId,
      snapshot,
      entityType: entityType,
      entityId: entityId,
      issueType: issueType,
      severity: 'blocking',
      message: message,
      metadata: metadata,
    );
    return false;
  }

  Future<void> _openIssue(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot, {
    required String entityType,
    required String entityId,
    required String issueType,
    required String severity,
    required String message,
    Map<String, Object?> metadata = const {},
  }) =>
      _issueDao
          .openOrUpdateIssue(
            ReconciliationIssueDraft(
              profileId: profileId,
              businessId: snapshot.businessId,
              branchId: snapshot.branchId,
              domain: 'cash_pos',
              entityType: entityType,
              entityId: entityId,
              issueType: issueType,
              severity: severity,
              message: message,
              metadataJson: jsonEncode({
                'snapshot_id': snapshot.snapshotId,
                ...metadata,
              }),
            ),
          )
          .then((_) {});

  Future<void> _resolveEntityIssues(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot, {
    required String entityType,
    required String entityId,
  }) async {
    for (final issueType in const [
      'scope_mismatch',
      'dependency_missing',
      'dirty_vs_tombstone',
      'dirty_without_outbox',
      'dirty_vs_remote',
    ]) {
      await _issueDao.resolveOpenIssue(
        profileId: profileId,
        businessId: snapshot.businessId,
        branchId: snapshot.branchId,
        domain: 'cash_pos',
        issueType: issueType,
        entityType: entityType,
        entityId: entityId,
      );
    }
  }

  Future<Set<String>> _seenIds(
    String profileId,
    OperationalBootstrapSnapshotPage snapshot,
    String dataset,
  ) async =>
      (await _seenRecordDao.getEntityIds(
        snapshotId: snapshot.snapshotId,
        profileId: profileId,
        businessId: snapshot.businessId,
        branchId: snapshot.branchId,
        bundle: snapshot.bundle,
        dataset: dataset,
      ))
          .toSet();

  bool _afterSnapshot(
    Map<String, dynamic> local,
    OperationalBootstrapSnapshotPage snapshot,
  ) {
    final raw = local['created_at'];
    final created = raw is DateTime
        ? raw.toUtc()
        : raw is int
            ? DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true)
            : DateTime.tryParse(raw?.toString() ?? '')?.toUtc();
    return created != null && created.isAfter(snapshot.snapshotAt);
  }
}
