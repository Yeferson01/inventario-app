import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.executor(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('checkpoint resumes one semantic scope and records page progress',
      () async {
    final dao = OperationalBootstrapCheckpointLocalDao(database);
    const scope = OperationalBootstrapScope(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
      appDeviceId: 'device-d',
      bundle: 'product_operational',
      dataset: 'product_stock_balances',
    );
    final now = DateTime.utc(2026, 8, 15);

    await dao.beginOrRestart(
      scope: scope,
      snapshotId: 'snapshot-1',
      snapshotAt: now,
      authorizationValidatedAt: now,
      convergenceStatus: 'pre_acknowledgement',
    );
    await dao.markApplying(scope, convergenceStatus: 'pending');
    final seenDao = OperationalBootstrapSeenRecordLocalDao(database);
    await database.transaction(() async {
      await seenDao.recordSeen(
        const SeenRecordDraft(
          snapshotId: 'snapshot-1',
          profileId: 'profile-p',
          businessId: 'business-a',
          branchId: 'branch-x',
          bundle: 'product_operational',
          dataset: 'product_stock_balances',
          entityId: 'balance-1',
        ),
      );
      await dao.commitPageProgress(
        scope: scope,
        nextPageToken: 'page-2',
        rowsReceived: 1000,
      );
    });

    var checkpoint = await dao.get(scope);
    expect(checkpoint?['status'], 'applying');
    expect(checkpoint?['rows_received'], 1000);
    expect(checkpoint?['pages_applied'], 1);
    expect(checkpoint?['next_page_token'], 'page-2');
    expect(
      await seenDao.exists(
        const SeenRecordDraft(
          snapshotId: 'snapshot-1',
          profileId: 'profile-p',
          businessId: 'business-a',
          branchId: 'branch-x',
          bundle: 'product_operational',
          dataset: 'product_stock_balances',
          entityId: 'balance-1',
        ),
      ),
      isTrue,
    );

    await dao.markRestartRequired(scope, reason: 'token expired');
    checkpoint = await dao.get(scope);
    expect(checkpoint?['status'], 'restart_required');
    expect(checkpoint?['convergence_status'], 'restart_required');
  });

  test('seen journal records a page of 1000 entities idempotently', () async {
    final dao = OperationalBootstrapSeenRecordLocalDao(database);
    final records = List.generate(
      1000,
      (index) => SeenRecordDraft(
        snapshotId: 'snapshot-1',
        profileId: 'profile-p',
        businessId: 'business-a',
        branchId: 'branch-x',
        bundle: 'product_operational',
        dataset: 'products',
        entityId: 'product-$index',
      ),
    );

    await dao.recordSeenBatch(records);
    await dao.recordSeen(records.first);

    final ids = await dao.getEntityIds(
      snapshotId: 'snapshot-1',
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
      bundle: 'product_operational',
      dataset: 'products',
    );
    expect(ids, hasLength(1000));
    expect(await dao.exists(records.last), isTrue);

    final deleted = await dao.deleteBySnapshot(
      snapshotId: 'snapshot-1',
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
      bundle: 'product_operational',
      dataset: 'products',
    );
    expect(deleted, 1000);
  });

  test('authoritative context replacement removes permissions no longer sent',
      () async {
    final dao = AuthorizedOperationalContextLocalDao(database);
    final now = DateTime.utc(2026, 8, 15);

    await dao.replaceContext(
      AuthorizedOperationalContextProjection(
        profileId: 'profile-p',
        businessId: 'business-a',
        branchId: 'branch-x',
        effectivePermissions: const ['sales.create', 'inventory.read'],
        effectiveRoles: const ['cashier'],
        applicableMembershipIds: const ['membership-1'],
        authorizationValidatedAt: now,
        snapshotId: 'snapshot-1',
      ),
    );
    await dao.replaceContext(
      AuthorizedOperationalContextProjection(
        profileId: 'profile-p',
        businessId: 'business-a',
        branchId: 'branch-x',
        effectivePermissions: const ['sales.create'],
        effectiveRoles: const ['cashier'],
        applicableMembershipIds: const ['membership-1'],
        authorizationValidatedAt: now.add(const Duration(minutes: 1)),
        snapshotId: 'snapshot-2',
      ),
    );

    expect(
      await dao.getEffectivePermissions(
        profileId: 'profile-p',
        businessId: 'business-a',
        branchId: 'branch-x',
      ),
      ['sales.create'],
    );
    expect(
      await dao.exists(
        profileId: 'profile-p',
        businessId: 'business-a',
        branchId: 'branch-x',
      ),
      isTrue,
    );
  });

  test('blocker query returns only open blocking issues', () async {
    final dao = ReconciliationIssueLocalDao(database);
    final warningId = await dao.openIssue(
      const ReconciliationIssueDraft(
        profileId: 'profile-p',
        businessId: 'business-a',
        branchId: 'branch-x',
        domain: 'inventory',
        issueType: 'scope_mismatch',
        severity: 'warning',
        message: 'warning',
      ),
    );
    await dao.resolveIssue(warningId);
    final blockerId = await dao.openIssue(
      const ReconciliationIssueDraft(
        profileId: 'profile-p',
        businessId: 'business-a',
        branchId: 'branch-x',
        domain: 'inventory',
        entityType: 'inventory_movement',
        entityId: 'movement-1',
        issueType: 'missing_source_item_id',
        severity: 'blocking',
        message: 'source item missing',
      ),
    );

    var blockers = await dao.getOpenBlockingIssues(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    expect(blockers.map((issue) => issue['id']), [blockerId]);

    await dao.resolveIssue(blockerId);
    blockers = await dao.getOpenBlockingIssues(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    expect(blockers, isEmpty);
  });

  test('B1A same blocker enriches unresolved scope without changing identity',
      () async {
    final dao = ReconciliationIssueLocalDao(database);
    final unresolved = _saleItemIssue();
    final id = await dao.openOrUpdateIssue(unresolved);
    final promoted = await dao.openOrUpdateIssue(_saleItemIssue(
      cashSessionId: 'session-s',
      status: ReconciliationScopeResolutionStatus.resolvedSession,
    ));
    final repeated = await dao.openOrUpdateIssue(_saleItemIssue(
      cashSessionId: 'session-s',
      status: ReconciliationScopeResolutionStatus.resolvedSession,
    ));

    expect(promoted, id);
    expect(repeated, id);
    final issues = await dao.getIssues(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
      domain: 'cash_pos',
    );
    expect(issues, hasLength(1));
    expect(issues.single['cash_session_id'], 'session-s');
    expect(issues.single['scope_resolution_status'], 'resolved_session');
  });

  test('B1A contradictory session creates blocker and preserves prior scope',
      () async {
    final dao = ReconciliationIssueLocalDao(database);
    await dao.openOrUpdateIssue(_saleItemIssue(
      cashSessionId: 'session-s',
      status: ReconciliationScopeResolutionStatus.resolvedSession,
    ));
    await dao.openOrUpdateIssue(_saleItemIssue(
      cashSessionId: 'session-s2',
      status: ReconciliationScopeResolutionStatus.resolvedSession,
    ));

    final issues = await dao.getIssues(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
      domain: 'cash_pos',
    );
    expect(issues, hasLength(2));
    expect(
      issues.singleWhere((row) => row['issue_type'] == 'dependency_missing')[
          'cash_session_id'],
      'session-s',
    );
    expect(
      issues.singleWhere((row) =>
          row['issue_type'] == 'scope_provenance_conflict')['severity'],
      'blocking',
    );
  });

  test('B1A issue provenance survives database reopen', () async {
    final directory = await Directory.systemTemp.createTemp('b1a-provenance-');
    final file =
        File('${directory.path}${Platform.pathSeparator}issues.sqlite');
    try {
      final first = AppDatabase.executor(NativeDatabase(file));
      await ReconciliationIssueLocalDao(first).openOrUpdateIssue(
        _saleItemIssue(
          cashSessionId: 'session-s',
          status: ReconciliationScopeResolutionStatus.resolvedSession,
        ),
      );
      await first.close();

      final reopened = AppDatabase.executor(NativeDatabase(file));
      try {
        final issues = await ReconciliationIssueLocalDao(reopened).getIssues(
          profileId: 'profile-p',
          businessId: 'business-a',
          branchId: 'branch-x',
          domain: 'cash_pos',
        );
        expect(issues.single['cash_session_id'], 'session-s');
        expect(issues.single['cash_register_id'], 'register-r');
        expect(issues.single['scope_resolution_status'], 'resolved_session');
      } finally {
        await reopened.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('B1A scoped issue read distinguishes two sessions and unresolved',
      () async {
    final dao = ReconciliationIssueLocalDao(database);
    await dao.openOrUpdateIssue(_saleItemIssue(
      cashSessionId: 'session-s',
      status: ReconciliationScopeResolutionStatus.resolvedSession,
    ));
    await dao.openOrUpdateIssue(const ReconciliationIssueDraft(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
      domain: 'cash_pos',
      entityType: 'sale_payments',
      entityId: 'payment-2',
      saleId: 'sale-2',
      cashRegisterId: 'register-r',
      cashSessionId: 'session-s2',
      scopeResolutionStatus:
          ReconciliationScopeResolutionStatus.resolvedSession,
      issueType: 'dependency_missing',
      severity: 'blocking',
      message: 'missing',
    ));
    await dao.openOrUpdateIssue(const ReconciliationIssueDraft(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
      domain: 'cash_pos',
      entityType: 'sale_items',
      entityId: 'item-3',
      saleId: 'sale-3',
      issueType: 'dependency_missing',
      severity: 'blocking',
      message: 'missing',
    ));
    await dao.openOrUpdateIssue(const ReconciliationIssueDraft(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-y',
      domain: 'cash_pos',
      entityType: 'sale_items',
      entityId: 'item-other',
      cashSessionId: 'session-y',
      scopeResolutionStatus:
          ReconciliationScopeResolutionStatus.resolvedSession,
      issueType: 'dependency_missing',
      severity: 'blocking',
      message: 'other',
    ));

    final current = await dao.getOpenBlockingIssues(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    expect(current, hasLength(3));
    expect(current.map((row) => row['cash_session_id']).toSet(),
        {'session-s', 'session-s2', null});
    expect(
        current.map((row) => row['entity_id']), isNot(contains('item-other')));
  });
}

ReconciliationIssueDraft _saleItemIssue({
  String? cashSessionId,
  ReconciliationScopeResolutionStatus status =
      ReconciliationScopeResolutionStatus.unresolved,
}) =>
    ReconciliationIssueDraft(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
      domain: 'cash_pos',
      entityType: 'sale_items',
      entityId: 'item-1',
      saleId: 'sale-1',
      cashRegisterId: 'register-r',
      cashSessionId: cashSessionId,
      scopeResolutionStatus: status,
      scopeEvidenceType: 'parent_sale_snapshot',
      issueType: 'dependency_missing',
      severity: 'blocking',
      message: 'Parent sale unavailable locally.',
    );
