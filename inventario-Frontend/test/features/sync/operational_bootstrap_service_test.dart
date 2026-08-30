import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_models.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_service.dart';
import 'package:inventario_frontend/features/cash/data/datasources/cash_session_local_dao.dart';
import 'package:inventario_frontend/features/sync/application/cash_pos_snapshot_applier.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_orchestration_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/cash_pos_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/inventory_balance_reconciliation_models.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_bootstrap_models.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.executor(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('owner and cashier capabilities recover every required bundle',
      () async {
    for (final permissions in [
      const [
        'settings.business',
        'sales.create',
        'cash.read',
        'inventory.read',
      ],
      const ['sales.create', 'cash.open', 'cash.read', 'inventory.read'],
    ]) {
      final harness = _Harness(database, permissions: permissions);
      final result = await harness.service.run(_request());

      expect(result.outcome, OperationalBootstrapOutcome.ready);
      expect(result.offlineReady, isTrue);
      expect(
        result.requiredBundles,
        ['core', 'product_operational', 'cash_pos'],
      );
      expect(harness.calls, contains('inventory'));
      expect(harness.calls, contains('cash_pos'));

      await database.close();
      database = AppDatabase.executor(NativeDatabase.memory());
    }
  });

  test('warehouse and real technician permissions omit cash by capability',
      () async {
    for (final permissions in [
      const ['inventory.read', 'inventory.purchase'],
      const ['products.read', 'inventory.read'],
    ]) {
      final harness = _Harness(database, permissions: permissions);
      final result = await harness.service.run(_request());

      expect(result.outcome, OperationalBootstrapOutcome.ready);
      expect(result.requiredBundles, ['core', 'product_operational']);
      expect(harness.calls, isNot(contains('cash_pos')));

      await database.close();
      database = AppDatabase.executor(NativeDatabase.memory());
    }
  });

  test('custom role behavior depends only on sales.create', () async {
    final harness = _Harness(
      database,
      permissions: const ['sales.create'],
    );

    final result = await harness.service.run(_request());

    expect(result.offlineReady, isTrue);
    expect(
      result.requiredBundles,
      ['core', 'product_operational', 'cash_pos'],
    );
  });

  test('runtime setup result is typed and capability-authorized', () async {
    final owner = _Harness(
      database,
      permissions: const ['settings.business', 'inventory.read'],
    );
    final ownerResult = await owner.service.run(
      _request(runtimeReady: false, cashRegisterId: null),
    );

    expect(
      ownerResult.outcome,
      OperationalBootstrapOutcome.runtimeSetupRequired,
    );
    expect(ownerResult.runtimeSetupAllowed, isTrue);

    await database.close();
    database = AppDatabase.executor(NativeDatabase.memory());
    final branchManager = _Harness(
      database,
      permissions: const ['settings.branches', 'inventory.read'],
    );
    final branchManagerResult = await branchManager.service.run(
      _request(runtimeReady: false, cashRegisterId: null),
    );

    expect(
      branchManagerResult.outcome,
      OperationalBootstrapOutcome.runtimeSetupRequired,
    );
    expect(branchManagerResult.runtimeSetupAllowed, isFalse);

    await database.close();
    database = AppDatabase.executor(NativeDatabase.memory());
    final cashier = _Harness(
      database,
      permissions: const ['sales.create', 'cash.read'],
    );
    final cashierResult = await cashier.service.run(
      _request(runtimeReady: false, cashRegisterId: null),
    );

    expect(
      cashierResult.outcome,
      OperationalBootstrapOutcome.runtimeSetupRequired,
    );
    expect(cashierResult.runtimeSetupAllowed, isFalse);
    expect(cashier.calls, isNot(contains('cash_pos')));
  });

  test('authentication and explicit runtime scope are validated before core',
      () async {
    final wrongUser = _Harness(
      database,
      permissions: const ['inventory.read'],
      authenticatedProfileId: 'profile-b',
    );
    final wrongUserResult = await wrongUser.service.run(_request());

    expect(wrongUserResult.outcome, OperationalBootstrapOutcome.failed);
    expect(wrongUser.calls, isEmpty);

    await database.close();
    database = AppDatabase.executor(NativeDatabase.memory());
    final staleRuntime = _Harness(
      database,
      permissions: const ['inventory.read'],
    );
    final staleRuntimeResult = await staleRuntime.service.run(
      _request(runtimeAppDeviceId: 'device-from-another-context'),
    );

    expect(staleRuntimeResult.outcome, OperationalBootstrapOutcome.failed);
    expect(staleRuntime.calls, isEmpty);
  });

  test('online revocation invalidates projection and short-circuits domains',
      () async {
    final harness = _Harness(
      database,
      permissions: const ['sales.create'],
      coreRevoked: true,
    );
    await harness.seedAuthorization();

    final result = await harness.service.run(_request());
    final projection = await harness.authorizationDao.getContextRecord(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
    );

    expect(result.outcome, OperationalBootstrapOutcome.authorizationRevoked);
    expect(result.offlineReady, isFalse);
    expect(projection!.status, 'revoked');
    expect(harness.calls, ['core/*']);
  });

  test('inventory ambiguous blocker prevents cash recovery', () async {
    final harness = _Harness(
      database,
      permissions: const ['sales.create', 'inventory.read'],
      inventoryBlocked: true,
    );

    final result = await harness.service.run(_request());

    expect(result.outcome, OperationalBootstrapOutcome.recoveryBlocked);
    expect(result.offlineReady, isFalse);
    expect(
      result.blockingIssues.map((issue) => issue.issueType),
      contains('inventory_movement_ambiguous'),
    );
    expect(harness.calls, isNot(contains('cash_pos')));
  });

  test('repairable canonical cash conflict reaches cash reconciliation',
      () async {
    final harness = _Harness(
      database,
      permissions: const ['sales.create', 'cash.open', 'inventory.read'],
    );
    await harness.issueDao.openOrUpdateIssue(
      const ReconciliationIssueDraft(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-x',
        domain: 'cash_pos',
        entityType: 'cash_registers',
        entityId: 'register-y',
        issueType: 'canonical_entity_conflict',
        severity: 'blocking',
        message: 'Legacy register conflicts with canonical register-x.',
      ),
    );

    final result = await harness.service.run(_request());

    expect(harness.calls, contains('cash_pos'));
    expect(result.outcome, OperationalBootstrapOutcome.ready);
    expect(result.offlineReady, isTrue);
    expect(result.blockingIssues, isEmpty);
  });

  test('cash open-session conflict is blocking and creates no session',
      () async {
    final harness = _Harness(
      database,
      permissions: const ['sales.create', 'cash.open'],
      cashBlocked: true,
    );

    final result = await harness.service.run(_request());

    expect(result.outcome, OperationalBootstrapOutcome.recoveryBlocked);
    expect(
      result.blockingIssues.map((issue) => issue.issueType),
      contains('cash_open_session_conflict'),
    );
    expect(await _count(database, 'cash_sessions'), 0);
  });

  test('empty Drift becomes ready without creating outbox', () async {
    final harness = _Harness(
      database,
      permissions: const ['sales.create', 'cash.read', 'inventory.read'],
    );

    final result = await harness.service.run(_request());

    expect(result.offlineReady, isTrue);
    expect(await _count(database, 'businesses'), 1);
    expect(await _count(database, 'products'), 1);
    expect(await _count(database, 'local_product_stock_balances'), 1);
    expect(await _count(database, 'cash_registers'), 1);
    expect(await _count(database, 'cash_sessions'), 1);
    expect(await _count(database, 'local_sync_batches'), 0);
    expect(await _count(database, 'local_sync_mutations'), 0);
  });

  test('partial Drift and repeated run remain globally idempotent', () async {
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(id: 'business-a', name: 'Existing'),
        );
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'category-a',
            businessId: const Value('business-a'),
            name: 'Existing category',
          ),
        );
    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: 'product-a',
            businessId: const Value('business-a'),
            categoryId: const Value('category-a'),
            name: 'Existing product',
            salePrice: 10,
          ),
        );
    await _insertPendingOutbox(database);
    final harness = _Harness(
      database,
      permissions: const ['sales.create', 'cash.read', 'inventory.read'],
    );

    final first = await harness.service.run(_request());
    final second = await harness.service.run(_request());

    expect(first.offlineReady, isTrue);
    expect(second.offlineReady, isTrue);
    expect(await _count(database, 'products'), 1);
    expect(await _count(database, 'local_product_stock_balances'), 1);
    expect(await _count(database, 'cash_registers'), 1);
    expect(await _count(database, 'local_reconciliation_issues'), 0);
    expect(await _count(database, 'local_sync_batches'), 1);
    expect(await _count(database, 'local_sync_mutations'), 1);
  });

  test('app kill after products page resumes without repeating core/category',
      () async {
    final harness = _Harness(
      database,
      permissions: const ['inventory.read'],
      failDatasetOnce: 'products',
    );

    final interrupted = await harness.service.run(_request());
    final resumed = await harness.service.run(_request());

    expect(
      interrupted.outcome,
      OperationalBootstrapOutcome.networkUnavailableWithCachedContext,
    );
    expect(interrupted.offlineReady, isFalse);
    expect(resumed.offlineReady, isTrue);
    expect(harness.calls.where((call) => call == 'core/*').length, 1);
    expect(
      harness.calls
          .where((call) => call == 'product_operational/categories')
          .length,
      1,
    );
    expect(
      harness.calls
          .where((call) => call == 'product_operational/products')
          .length,
      2,
    );
  });

  test('transient inventory failure preserves completed products on retry',
      () async {
    final harness = _Harness(
      database,
      permissions: const ['inventory.read'],
      inventoryNetworkFailureOnce: true,
    );

    final interrupted = await harness.service.run(_request());
    final resumed = await harness.service.run(_request());

    expect(
      interrupted.outcome,
      OperationalBootstrapOutcome.networkUnavailableWithCachedContext,
    );
    expect(resumed.offlineReady, isTrue);
    expect(harness.calls.where((call) => call == 'core/*').length, 1);
    for (final dataset in const [
      'categories',
      'products',
      'product_barcodes',
    ]) {
      expect(
        harness.calls
            .where((call) => call == 'product_operational/$dataset')
            .length,
        1,
      );
    }
    expect(harness.calls.where((call) => call == 'inventory').length, 2);
  });

  test('cached context network failure exposes checkpoint state without TTL',
      () async {
    final harness = _Harness(
      database,
      permissions: const ['inventory.read'],
      coreNetworkFailure: true,
    );
    await harness.seedAuthorization();

    final result = await harness.service.run(_request());

    expect(
      result.outcome,
      OperationalBootstrapOutcome.networkUnavailableWithCachedContext,
    );
    expect(result.offlineReady, isFalse);
    expect(result.authorizationValidatedAt, isNotNull);
    expect(result.checkpoints, isNotEmpty);
    expect(result.checkpoints.every((item) => !item.present), isTrue);
  });

  test('other profile and branch issues/checkpoints never block this scope',
      () async {
    final harness = _Harness(
      database,
      permissions: const ['inventory.read'],
    );
    await ReconciliationIssueLocalDao(database).openIssue(
      const ReconciliationIssueDraft(
        profileId: 'profile-b',
        businessId: 'business-a',
        branchId: 'branch-y',
        domain: 'inventory_balance',
        issueType: 'foreign_scope_blocker',
        severity: 'blocking',
        message: 'Must not block branch X.',
      ),
    );
    await harness.checkpointDao.beginOrRestart(
      scope: const OperationalBootstrapScope(
        profileId: 'profile-b',
        businessId: 'business-a',
        branchId: 'branch-y',
        appDeviceId: 'device-b',
        bundle: 'product_operational',
        dataset: 'products',
      ),
      snapshotId: 'foreign-snapshot',
      snapshotAt: _now,
      authorizationValidatedAt: _now,
    );

    final result = await harness.service.run(_request());

    expect(result.offlineReady, isTrue);
    expect(result.blockingIssues, isEmpty);
  });

  test('cash opening remains guarded while canonical X is not materialized',
      () async {
    final harness = _Harness(
      database,
      permissions: const ['sales.create', 'cash.open'],
      cashNetworkFailure: true,
    );

    final result = await harness.service.run(_request());
    final cashService = CashSessionLocalService(
      dao: CashSessionLocalDao(database),
    );

    expect(
      result.outcome,
      OperationalBootstrapOutcome.networkUnavailableWithCachedContext,
    );
    await expectLater(
      cashService.openCashSession(
        const OpenCashSessionInput(
          businessId: 'business-a',
          branchId: 'branch-x',
          profileId: 'profile-a',
          cashRegisterId: 'register-x',
          openingCashAmount: 20,
          deviceInstallationId: 'installation-a',
        ),
      ),
      throwsA(isA<CashRecoveryRequiredException>()),
    );
    expect(await _count(database, 'cash_registers'), 0);
  });
}

final _now = DateTime.utc(2026, 8, 20, 10);

OperationalBootstrapRequest _request({
  bool runtimeReady = true,
  String? cashRegisterId = 'register-x',
  String runtimeAppDeviceId = 'device-a',
}) {
  return OperationalBootstrapRequest(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-x',
    installationId: 'installation-a',
    appDeviceId: 'device-a',
    mode: OperationalBootstrapMode.recovery,
    runtime: OperationalBootstrapRuntimeResolution(
      businessId: 'business-a',
      branchId: 'branch-x',
      installationId: 'installation-a',
      appDeviceId: runtimeAppDeviceId,
      runtimeReady: runtimeReady,
      cashRegisterId: cashRegisterId,
      cashSessionId: 'session-x',
      receiptSequenceId: 'receipt-x',
    ),
  );
}

class _Harness {
  _Harness(
    this.database, {
    required this.permissions,
    this.coreRevoked = false,
    this.coreNetworkFailure = false,
    this.inventoryBlocked = false,
    this.cashBlocked = false,
    this.cashNetworkFailure = false,
    this.inventoryNetworkFailureOnce = false,
    this.failDatasetOnce,
    this.authenticatedProfileId = 'profile-a',
  })  : authorizationDao = AuthorizedOperationalContextLocalDao(database),
        checkpointDao = OperationalBootstrapCheckpointLocalDao(database),
        issueDao = ReconciliationIssueLocalDao(database) {
    service = OperationalBootstrapService.withRunners(
      download: _download,
      reconcileInventory: _inventory,
      recoverCashPos: _cash,
      authorizationContextDao: authorizationDao,
      checkpointDao: checkpointDao,
      issueDao: issueDao,
      authenticatedProfileId: () => authenticatedProfileId,
      onProgress: progress.add,
    );
  }

  final AppDatabase database;
  final List<String> permissions;
  final bool coreRevoked;
  final bool coreNetworkFailure;
  final bool inventoryBlocked;
  final bool cashBlocked;
  final bool cashNetworkFailure;
  final bool inventoryNetworkFailureOnce;
  final String? failDatasetOnce;
  final String authenticatedProfileId;
  final AuthorizedOperationalContextLocalDao authorizationDao;
  final OperationalBootstrapCheckpointLocalDao checkpointDao;
  final ReconciliationIssueLocalDao issueDao;
  final List<String> calls = [];
  final List<OperationalBootstrapProgress> progress = [];
  final Set<String> _failedDatasets = {};
  var _inventoryCalls = 0;
  late final OperationalBootstrapService service;

  Future<void> seedAuthorization() {
    return authorizationDao.replaceContext(
      AuthorizedOperationalContextProjection(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-x',
        effectivePermissions: permissions,
        effectiveRoles: const ['fixture-role'],
        applicableMembershipIds: const ['membership-a'],
        authorizationValidatedAt: _now,
        snapshotId: 'core-snapshot',
      ),
    );
  }

  Future<OperationalBootstrapDownloadResult> _download(
    OperationalBootstrapDownloadRequest request, {
    bool restart = false,
  }) async {
    final dataset = request.dataset ?? '*';
    calls.add('${request.bundle}/$dataset');
    if (request.bundle == 'core') {
      if (coreRevoked) {
        throw const OperationalBootstrapException(
          kind: OperationalBootstrapFailureKind.forbidden,
          message: 'Membership revoked.',
        );
      }
      if (coreNetworkFailure) {
        throw const OperationalBootstrapException(
          kind: OperationalBootstrapFailureKind.networkTransient,
          message: 'Network unavailable.',
        );
      }
      await _materializeCore();
      await seedAuthorization();
      await _complete('core', 'context');
      return _downloadResult(request, dataset: null, rows: 1);
    }

    if (failDatasetOnce == request.dataset &&
        _failedDatasets.add(request.dataset!)) {
      await checkpointDao.beginOrRestart(
        scope: request.scopeFor(request.dataset!),
        snapshotId: 'product-snapshot',
        snapshotAt: _now,
        authorizationValidatedAt: _now,
      );
      await checkpointDao.markFailed(
        request.scopeFor(request.dataset!),
        error: 'simulated app kill',
      );
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.networkTransient,
        message: 'Simulated app kill after the first product page.',
      );
    }

    await _materializeProductDataset(request.dataset!);
    await _complete('product_operational', request.dataset!);
    return _downloadResult(request, dataset: request.dataset, rows: 1);
  }

  Future<InventoryBalanceReconciliationResult> _inventory(
    InventoryBalanceReconciliationRequest request, {
    bool restart = false,
  }) async {
    calls.add('inventory');
    _inventoryCalls += 1;
    if (inventoryNetworkFailureOnce && _inventoryCalls == 1) {
      final scope = OperationalBootstrapScope(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        appDeviceId: request.appDeviceId,
        bundle: 'product_operational',
        dataset: 'product_stock_balances',
      );
      await checkpointDao.beginOrRestart(
        scope: scope,
        snapshotId: 'balance-snapshot',
        snapshotAt: _now,
        authorizationValidatedAt: _now,
      );
      await checkpointDao.markFailed(scope, error: 'network unavailable');
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.networkTransient,
        message: 'Inventory acknowledgement network unavailable.',
      );
    }
    if (inventoryBlocked) {
      await issueDao.openOrUpdateIssue(
        const ReconciliationIssueDraft(
          profileId: 'profile-a',
          businessId: 'business-a',
          branchId: 'branch-x',
          domain: 'inventory_balance',
          entityType: 'inventory_movements',
          entityId: 'movement-a',
          issueType: 'inventory_movement_ambiguous',
          severity: 'blocking',
          message: 'Remote acknowledgement is ambiguous.',
        ),
      );
      await _complete(
        'product_operational',
        'product_stock_balances',
        convergenceStatus: 'blocked',
      );
      return const InventoryBalanceReconciliationResult(
        snapshotId: 'balance-snapshot',
        attempts: 1,
        movementsChecked: 1,
        balancesReconciled: 0,
        blockingIssues: 1,
        converged: false,
      );
    }
    await database
        .into(database.localProductStockBalances)
        .insertOnConflictUpdate(
          const LocalProductStockBalancesCompanion(
            id: Value('balance-a'),
            businessId: Value('business-a'),
            branchId: Value('branch-x'),
            productId: Value('product-a'),
            quantityOnHand: Value(8),
            quantityAvailable: Value(8),
            remoteBalanceId: Value('remote-balance-a'),
            remoteQuantityOnHand: Value(8),
            remoteQuantityReserved: Value(0),
            remoteQuantityAvailable: Value(8),
            remoteSnapshotId: Value('balance-snapshot'),
          ),
        );
    await _complete('product_operational', 'product_stock_balances');
    return const InventoryBalanceReconciliationResult(
      snapshotId: 'balance-snapshot',
      attempts: 1,
      movementsChecked: 0,
      balancesReconciled: 1,
      blockingIssues: 0,
      converged: true,
    );
  }

  Future<CashPosRecoveryResult> _cash(
    CashPosRecoveryRequest request, {
    bool restart = false,
  }) async {
    calls.add('cash_pos');
    if (cashNetworkFailure) {
      await checkpointDao.beginOrRestart(
        scope: OperationalBootstrapScope(
          profileId: request.profileId,
          businessId: request.businessId,
          branchId: request.branchId,
          appDeviceId: request.appDeviceId,
          bundle: 'cash_pos',
          dataset: 'cash_registers',
        ),
        snapshotId: 'cash-snapshot',
        snapshotAt: _now,
        authorizationValidatedAt: _now,
      );
      await checkpointDao.markFailed(
        OperationalBootstrapScope(
          profileId: request.profileId,
          businessId: request.businessId,
          branchId: request.branchId,
          appDeviceId: request.appDeviceId,
          bundle: 'cash_pos',
          dataset: 'cash_registers',
        ),
        error: 'network unavailable',
      );
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.networkTransient,
        message: 'Cash recovery network unavailable.',
      );
    }
    await database.into(database.cashRegisters).insertOnConflictUpdate(
          const CashRegistersCompanion(
            id: Value('register-x'),
            businessId: Value('business-a'),
            branchId: Value('branch-x'),
            name: Value('Canonical X'),
            status: Value('active'),
          ),
        );
    await issueDao.resolveOpenIssue(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
      domain: 'cash_pos',
      issueType: 'canonical_entity_conflict',
      entityType: 'cash_registers',
      entityId: 'register-y',
    );
    if (cashBlocked) {
      await issueDao.openOrUpdateIssue(
        const ReconciliationIssueDraft(
          profileId: 'profile-a',
          businessId: 'business-a',
          branchId: 'branch-x',
          domain: 'cash_pos',
          entityType: 'cash_sessions',
          entityId: 'session-b',
          issueType: 'cash_open_session_conflict',
          severity: 'blocking',
          message: 'Remote and local open sessions conflict.',
        ),
      );
    } else {
      await database.into(database.cashSessions).insertOnConflictUpdate(
            const CashSessionsCompanion(
              id: Value('session-x'),
              businessId: Value('business-a'),
              branchId: Value('branch-x'),
              cashRegisterId: Value('register-x'),
              openedByProfileId: Value('profile-a'),
              openingCashAmount: Value(20),
              status: Value('open'),
            ),
          );
    }
    for (final dataset in CashPosSnapshotApplier.datasets) {
      await _complete(
        'cash_pos',
        dataset,
        convergenceStatus: cashBlocked ? 'blocked' : 'complete',
      );
    }
    return CashPosRecoveryResult(
      snapshotId: 'cash-snapshot',
      cashContextReady: !cashBlocked,
      canonicalCashRegisterId: 'register-x',
      openCashSessionId: cashBlocked ? null : 'session-x',
      recoveredSalesCount: 0,
      blockingIssues: cashBlocked ? 1 : 0,
      completed: true,
    );
  }

  Future<void> _materializeCore() async {
    await database.into(database.businesses).insertOnConflictUpdate(
          BusinessesCompanion.insert(id: 'business-a', name: 'Business A'),
        );
    await database.into(database.profiles).insertOnConflictUpdate(
          const ProfilesCompanion(
            id: Value('profile-a'),
            businessId: Value('business-a'),
            fullName: Value('Profile A'),
          ),
        );
    await database.into(database.branches).insertOnConflictUpdate(
          BranchesCompanion.insert(
            id: 'branch-x',
            businessId: 'business-a',
            name: 'Branch X',
          ),
        );
  }

  Future<void> _materializeProductDataset(String dataset) async {
    if (dataset == 'categories') {
      await database.into(database.categories).insertOnConflictUpdate(
            CategoriesCompanion.insert(
              id: 'category-a',
              businessId: const Value('business-a'),
              name: 'Category A',
            ),
          );
      return;
    }
    if (dataset == 'products') {
      await database.into(database.products).insertOnConflictUpdate(
            ProductsCompanion.insert(
              id: 'product-a',
              businessId: const Value('business-a'),
              categoryId: const Value('category-a'),
              name: 'Product A',
              salePrice: 10,
            ),
          );
      return;
    }
    if (dataset == 'product_barcodes') {
      await database.into(database.localProductBarcodes).insertOnConflictUpdate(
            LocalProductBarcodesCompanion.insert(
              id: 'barcode-a',
              scope: 'business',
              businessId: const Value('business-a'),
              productId: const Value('product-a'),
              barcode: '7700000000001',
              barcodeNormalized: '7700000000001',
            ),
          );
    }
  }

  Future<void> _complete(
    String bundle,
    String dataset, {
    String convergenceStatus = 'complete',
  }) async {
    final scope = OperationalBootstrapScope(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
      appDeviceId: 'device-a',
      bundle: bundle,
      dataset: dataset,
    );
    await checkpointDao.beginOrRestart(
      scope: scope,
      snapshotId: '$bundle-snapshot',
      snapshotAt: _now,
      authorizationValidatedAt: _now,
    );
    await checkpointDao.markComplete(
      scope,
      convergenceStatus: convergenceStatus,
    );
  }

  OperationalBootstrapDownloadResult _downloadResult(
    OperationalBootstrapDownloadRequest request, {
    required String? dataset,
    required int rows,
  }) {
    return OperationalBootstrapDownloadResult(
      snapshotId: '${request.bundle}-snapshot',
      bundle: request.bundle,
      dataset: dataset,
      pagesApplied: 1,
      rowsReceived: rows,
      completed: true,
      resumed: false,
      restarted: false,
      authorizationValidatedAt: _now,
      checkpointStatus: OperationalBootstrapCheckpointStatus.complete,
      warnings: const [],
    );
  }
}

Future<int> _count(AppDatabase database, String table) async {
  final row = await database
      .customSelect('select count(*) as total from $table')
      .getSingle();
  return row.read<int>('total');
}

Future<void> _insertPendingOutbox(AppDatabase database) async {
  await database.into(database.localSyncBatches).insert(
        const LocalSyncBatchesCompanion(
          id: Value('batch-pending'),
          clientBatchId: Value('client-batch-pending'),
          businessId: Value('business-a'),
          branchId: Value('branch-x'),
          domain: Value('pos'),
          status: Value('pending'),
          mutationCount: Value(1),
        ),
      );
  await database.into(database.localSyncMutations).insert(
        const LocalSyncMutationsCompanion(
          id: Value('mutation-pending'),
          localSyncBatchId: Value('batch-pending'),
          clientBatchId: Value('client-batch-pending'),
          clientMutationId: Value('client-mutation-pending'),
          clientSequence: Value(1),
          businessId: Value('business-a'),
          branchId: Value('branch-x'),
          entityTable: Value('sales'),
          entityId: Value('sale-pending'),
          operation: Value('insert'),
          payloadJson: Value('{}'),
          idempotencyKey: Value('pending-idempotency'),
          status: Value('pending'),
        ),
      );
}
