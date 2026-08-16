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
}
