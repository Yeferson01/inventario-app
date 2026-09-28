import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/cash/data/datasources/cash_session_local_dao.dart';
import 'package:inventario_frontend/features/sync/application/app_runtime_context_store.dart';
import 'package:inventario_frontend/features/sync/application/offline_operational_readiness_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _Harness harness;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    harness = _Harness();
  });

  tearDown(() => harness.close());

  test('OR-01 complete scoped recovery is ready offline', () async {
    await harness.seedReady(includeCash: true);

    final result = await harness.evaluate();

    expect(result.outcome, OfflineOperationalReadinessOutcome.ready);
    expect(result.offlineReady, isTrue);
  });

  test('OR-08 legitimately closed cash is ready without an open session',
      () async {
    await harness.seedReady(includeCash: true);
    final openSession = await CashSessionLocalDao(harness.database)
        .getOpenCashSessionForRegister(
      businessId: _Harness.businessId,
      branchId: _Harness.branchId,
      cashRegisterId: 'cash-register-1',
    );

    final result = await harness.evaluate();

    expect(openSession, isNull);
    expect(result.outcome, OfflineOperationalReadinessOutcome.ready);
    expect(result.offlineReady, isTrue);
  });

  test('OR-02 active authorization with incomplete bootstrap is denied',
      () async {
    await harness.seedReady(omitDataset: 'product_stock_balances');

    final result = await harness.evaluate();

    expect(
      result.outcome,
      OfflineOperationalReadinessOutcome.recoveryRequired,
    );
    expect(result.missingDatasets, [
      'product_operational/product_stock_balances',
    ]);
  });

  test('OR-03 blocker in the selected scope is denied', () async {
    await harness.seedReady();
    await harness.issues.openIssue(
      _issue(branchId: _Harness.branchId),
    );

    final result = await harness.evaluate();

    expect(
      result.outcome,
      OfflineOperationalReadinessOutcome.recoveryRequired,
    );
    expect(result.blockingIssueCount, 1);
  });

  test('OR-04 blocker from another branch does not block this scope', () async {
    await harness.seedReady();
    await harness.issues.openIssue(_issue(branchId: 'branch-other'));

    final result = await harness.evaluate();

    expect(result.outcome, OfflineOperationalReadinessOutcome.ready);
  });

  test('OR-05 legitimate pending mutations do not block offline readiness',
      () async {
    await harness.seedReady();
    await harness.database.customStatement('''
      insert into local_sync_batches (
        id, client_batch_id, business_id, branch_id, app_device_id, profile_id,
        domain, status, mutation_count
      ) values (
        'batch-pending', 'client-batch-pending', '${_Harness.businessId}',
        '${_Harness.branchId}', '${_Harness.appDeviceId}',
        '${_Harness.profileId}', 'inventory', 'pending', 1
      );
      insert into local_sync_mutations (
        id, local_sync_batch_id, client_batch_id, client_mutation_id,
        client_sequence, business_id, branch_id, app_device_id, profile_id,
        entity_table, entity_id, operation, payload_json, idempotency_key,
        status
      ) values (
        'mutation-pending', 'batch-pending', 'client-batch-pending',
        'client-mutation-pending', 1, '${_Harness.businessId}',
        '${_Harness.branchId}', '${_Harness.appDeviceId}',
        '${_Harness.profileId}', 'inventory_movements', 'movement-pending',
        'insert', '{}', 'pending-key', 'pending'
      );
    ''');

    final result = await harness.evaluate();

    expect(result.outcome, OfflineOperationalReadinessOutcome.ready);
  });

  test('OR-06 known revoked authorization is denied', () async {
    await harness.seedReady(authorizationStatus: 'revoked');

    final result = await harness.evaluate();

    expect(
      result.outcome,
      OfflineOperationalReadinessOutcome.authorizationRevoked,
    );
  });

  test('OR-07 transient network does not affect last valid local readiness',
      () async {
    await harness.seedReady();

    final result = await harness.evaluate();

    expect(result.offlineReady, isTrue);
    expect(result.authorizationValidatedAt, isNotNull);
  });
}

ReconciliationIssueDraft _issue({required String branchId}) {
  return ReconciliationIssueDraft(
    profileId: _Harness.profileId,
    businessId: _Harness.businessId,
    branchId: branchId,
    domain: 'inventory_balance',
    entityType: 'inventory_movements',
    entityId: 'movement-1',
    issueType: 'ambiguous_acknowledgement',
    severity: 'blocking',
    message: 'Recovery cannot converge safely.',
  );
}

class _Harness {
  _Harness() : database = AppDatabase.executor(NativeDatabase.memory()) {
    authorization = AuthorizedOperationalContextLocalDao(database);
    checkpoints = OperationalBootstrapCheckpointLocalDao(database);
    issues = ReconciliationIssueLocalDao(database);
    runtime = AppRuntimeContextStore();
    service = OfflineOperationalReadinessService(
      authenticatedProfileId: () => profileId,
      authorizationDao: authorization,
      runtimeStore: runtime,
      checkpointDao: checkpoints,
      issueDao: issues,
      cashSessionDao: CashSessionLocalDao(database),
    );
  }

  static const profileId = 'profile-1';
  static const businessId = 'business-1';
  static const branchId = 'branch-1';
  static const installationId = 'installation-1';
  static const appDeviceId = 'device-1';

  final AppDatabase database;
  late final AuthorizedOperationalContextLocalDao authorization;
  late final OperationalBootstrapCheckpointLocalDao checkpoints;
  late final ReconciliationIssueLocalDao issues;
  late final AppRuntimeContextStore runtime;
  late final OfflineOperationalReadinessService service;

  Future<void> seedReady({
    String authorizationStatus = 'active',
    String? omitDataset,
    bool includeCash = false,
  }) async {
    final validatedAt = DateTime.utc(2026, 9, 15, 12);
    await authorization.replaceContext(
      AuthorizedOperationalContextProjection(
        profileId: profileId,
        businessId: businessId,
        branchId: branchId,
        effectivePermissions: [
          'inventory.read',
          if (includeCash) 'cash.read',
        ],
        effectiveRoles: const ['warehouse'],
        applicableMembershipIds: const ['membership-1'],
        authorizationValidatedAt: validatedAt,
        snapshotId: 'snapshot-core',
        status: authorizationStatus,
      ),
    );
    if (includeCash) {
      await database.customStatement(
        '''insert into businesses (id, name)
           values ('$businessId', 'Business')''',
      );
      await database.customStatement(
        '''insert into branches (id, business_id, name)
           values ('$branchId', '$businessId', 'Branch')''',
      );
      await database.customStatement(
        '''insert into cash_registers
             (id, business_id, branch_id, name, status)
           values
             ('cash-register-1', '$businessId', '$branchId',
              'Main register', 'active')''',
      );
    }
    await runtime.saveContext(
      AppRuntimeContext(
        profileId: profileId,
        businessId: businessId,
        branchId: branchId,
        installationId: installationId,
        appDeviceId: appDeviceId,
        cashRegisterId: includeCash ? 'cash-register-1' : null,
      ),
    );
    for (final item in [
      (bundle: 'core', dataset: 'context'),
      (bundle: 'product_operational', dataset: 'categories'),
      (bundle: 'product_operational', dataset: 'products'),
      (bundle: 'product_operational', dataset: 'product_barcodes'),
      (bundle: 'product_operational', dataset: 'product_stock_balances'),
      if (includeCash) ...const [
        (bundle: 'cash_pos', dataset: 'cash_registers'),
        (bundle: 'cash_pos', dataset: 'open_cash_sessions'),
        (bundle: 'cash_pos', dataset: 'cash_movements'),
        (bundle: 'cash_pos', dataset: 'session_sales'),
        (bundle: 'cash_pos', dataset: 'session_sale_items'),
        (bundle: 'cash_pos', dataset: 'session_sale_payments'),
      ],
    ]) {
      if (item.dataset == omitDataset) continue;
      final scope = OperationalBootstrapScope(
        profileId: profileId,
        businessId: businessId,
        branchId: branchId,
        appDeviceId: appDeviceId,
        bundle: item.bundle,
        dataset: item.dataset,
      );
      await checkpoints.beginOrRestart(
        scope: scope,
        snapshotId: 'snapshot-${item.dataset}',
        snapshotAt: validatedAt,
        authorizationValidatedAt: validatedAt,
      );
      await checkpoints.markComplete(scope);
    }
  }

  Future<OfflineOperationalReadinessResult> evaluate() {
    return service.evaluate(
      const OfflineOperationalReadinessRequest(
        profileId: profileId,
        businessId: businessId,
        branchId: branchId,
        installationId: installationId,
      ),
    );
  }

  Future<void> close() => database.close();
}
