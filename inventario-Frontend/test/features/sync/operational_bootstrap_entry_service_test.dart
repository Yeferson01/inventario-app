import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_selected_sync_context_store.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_service.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_orchestration_models.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_integration_failure.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_resolution_models.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';

void main() {
  test('multiple authorized contexts require explicit selection', () async {
    final harness = _EntryHarness()
      ..contexts = [
        _context(branchId: 'branch-x'),
        _context(branchId: 'branch-y'),
      ];

    final result = await harness.service.run(_request());

    expect(result.outcome, OperationalBootstrapEntryOutcome.selectionRequired);
    expect(result.contexts, hasLength(2));
    expect(harness.registerCalls, 0);
  });

  test('one concrete context is selected automatically and persisted',
      () async {
    final harness = _EntryHarness();

    final result = await harness.service.run(_request());

    expect(
      result.outcome,
      OperationalBootstrapEntryOutcome.runtimeReadyAndBootstrapCompleted,
    );
    expect(harness.stored?.branchId, 'branch-x');
  });

  test('stale profile-scoped selection is cleared and never bootstrapped',
      () async {
    final harness = _EntryHarness()
      ..contexts = [
        _context(branchId: 'branch-y'),
        _context(branchId: 'branch-z'),
      ]
      ..stored = const AppSelectedSyncContext(
        businessId: 'business-1',
        branchId: 'branch-x',
        profileId: 'profile-1',
      );

    final result = await harness.service.run(_request());

    expect(result.outcome, OperationalBootstrapEntryOutcome.selectionRequired);
    expect(harness.clearCalls, 1);
    expect(harness.bootstrapCalls, 0);
  });

  test('explicit stale selection is rejected before device registration',
      () async {
    final harness = _EntryHarness();

    final result = await harness.service.run(
      _request(
        selection: const OperationalContextSelection(
          businessId: 'business-other',
          branchId: 'branch-other',
        ),
      ),
    );

    expect(
        result.outcome, OperationalBootstrapEntryOutcome.authorizationRevoked);
    expect(harness.registerCalls, 0);
    expect(harness.bootstrapCalls, 0);
  });

  test('canonical scope and runtime ids are handed to bootstrap unchanged',
      () async {
    final harness = _EntryHarness();

    final result = await harness.service.run(_request());

    final input = harness.lastBootstrapRequest!;
    expect(input.profileId, 'profile-1');
    expect(input.businessId, 'business-1');
    expect(input.branchId, 'branch-x');
    expect(input.installationId, 'installation-1');
    expect(input.appDeviceId, 'device-1');
    expect(input.runtime.cashRegisterId, 'cash-1');
    expect(input.runtime.cashSessionId, 'session-1');
    expect(result.offlineReady, isTrue);
  });

  test('cashier with existing runtime never requests administrative ensure',
      () async {
    final harness = _EntryHarness()
      ..contexts = [
        _context(permissions: const ['sales.create', 'cash.open'])
      ];

    final result = await harness.service.run(_request());

    expect(harness.resolveCalls, 1);
    expect(harness.bootstrapCalls, 1);
    expect(
      result.outcome,
      OperationalBootstrapEntryOutcome.runtimeReadyAndBootstrapCompleted,
    );
  });

  test('cashier with missing runtime returns setup required without bootstrap',
      () async {
    final harness = _EntryHarness()..runtime = _runtime(ready: false);

    final result = await harness.service.run(_request());

    expect(
        result.outcome, OperationalBootstrapEntryOutcome.runtimeSetupRequired);
    expect(result.canRequestAdministrativeSetup, isFalse);
    expect(harness.bootstrapCalls, 0);
  });

  test('warehouse or technician capability does not enable runtime setup',
      () async {
    final harness = _EntryHarness()
      ..contexts = [
        _context(permissions: const ['inventory.read'])
      ]
      ..runtime = _runtime(ready: false);

    final result = await harness.service.run(_request());

    expect(
        result.outcome, OperationalBootstrapEntryOutcome.runtimeSetupRequired);
    expect(result.canRequestAdministrativeSetup, isFalse);
  });

  test('settings.branches alone does not enable administrative setup',
      () async {
    final harness = _EntryHarness()
      ..contexts = [
        _context(permissions: const ['settings.branches'])
      ]
      ..runtime = _runtime(ready: false);

    final result = await harness.service.run(_request());

    expect(result.canRequestAdministrativeSetup, isFalse);
    expect(harness.bootstrapCalls, 0);
  });

  test('settings.business exposes separate administrative action capability',
      () async {
    final harness = _EntryHarness()
      ..contexts = [
        _context(permissions: const ['settings.business'])
      ]
      ..runtime = _runtime(ready: false);

    final result = await harness.service.run(_request());

    expect(
        result.outcome, OperationalBootstrapEntryOutcome.runtimeSetupRequired);
    expect(result.canRequestAdministrativeSetup, isTrue);
    expect(harness.bootstrapCalls, 0);
  });

  test('blocked device short-circuits resolve and bootstrap', () async {
    final harness = _EntryHarness()
      ..registerFailure = const OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.deviceBlocked,
        message: 'blocked',
      );

    final result = await harness.service.run(_request());

    expect(result.outcome, OperationalBootstrapEntryOutcome.deviceBlocked);
    expect(harness.registerCalls, 1);
    expect(harness.resolveCalls, 0);
    expect(harness.bootstrapCalls, 0);
  });

  test('bootstrap recovery blocker is propagated with offlineReady false',
      () async {
    final harness = _EntryHarness()
      ..bootstrapResult = _bootstrapResult(
        outcome: OperationalBootstrapOutcome.recoveryBlocked,
        offlineReady: false,
        issues: const [
          OperationalBootstrapBlockingIssue(
            issueType: 'ambiguous_ack',
            domain: 'inventory',
            message: 'Movement acknowledgement is ambiguous.',
          ),
        ],
      );

    final result = await harness.service.run(_request());

    expect(
      result.outcome,
      OperationalBootstrapEntryOutcome.bootstrapRecoveryBlocked,
    );
    expect(result.offlineReady, isFalse);
    expect(result.bootstrapResult?.blockingIssues, hasLength(1));
  });

  test('bootstrap authorization revocation is propagated', () async {
    final harness = _EntryHarness()
      ..bootstrapResult = _bootstrapResult(
        outcome: OperationalBootstrapOutcome.authorizationRevoked,
        offlineReady: false,
      );

    final result = await harness.service.run(_request());

    expect(
        result.outcome, OperationalBootstrapEntryOutcome.authorizationRevoked);
  });

  test('bootstrap transient result is propagated', () async {
    final harness = _EntryHarness()
      ..bootstrapResult = _bootstrapResult(
        outcome:
            OperationalBootstrapOutcome.networkUnavailableWithCachedContext,
        offlineReady: false,
      );

    final result = await harness.service.run(_request());

    expect(result.outcome, OperationalBootstrapEntryOutcome.transientFailure);
  });

  test('device receives the exact explicit branch and no local device id',
      () async {
    final harness = _EntryHarness();

    await harness.service.run(
      _request(
        selection: const OperationalContextSelection(
          businessId: 'business-1',
          branchId: 'branch-x',
        ),
      ),
    );

    expect(harness.lastDeviceInput!.branchId, 'branch-x');
    expect(harness.lastDeviceInput!.installationId, 'installation-1');
  });
}

class _EntryHarness {
  List<AuthorizedOperationalContext> contexts = [_context()];
  AppSelectedSyncContext? stored;
  ResolvedBusinessRuntime runtime = _runtime();
  OperationalBootstrapResult bootstrapResult = _bootstrapResult();
  OperationalIntegrationException? registerFailure;
  int registerCalls = 0;
  int resolveCalls = 0;
  int bootstrapCalls = 0;
  int clearCalls = 0;
  RegisterAppDeviceInput? lastDeviceInput;
  OperationalBootstrapRequest? lastBootstrapRequest;

  OperationalBootstrapEntryService get service =>
      OperationalBootstrapEntryService(
        authenticatedProfileId: () => 'profile-1',
        discover: () async => contexts,
        installationId: () async => 'installation-1',
        registerDevice: (input) async {
          registerCalls++;
          lastDeviceInput = input;
          if (registerFailure != null) throw registerFailure!;
          return RegisteredAppDeviceResult(
            appDeviceId: 'device-1',
            businessId: input.businessId,
            branchId: input.branchId,
            installationId: input.installationId,
            status: 'active',
            raw: const {},
          );
        },
        resolveRuntime: ({
          required String profileId,
          required String businessId,
          required String branchId,
        }) async {
          resolveCalls++;
          return runtime;
        },
        bootstrap: (request) async {
          bootstrapCalls++;
          lastBootstrapRequest = request;
          return bootstrapResult;
        },
        readSelectedContext: (profileId) async => stored,
        writeSelectedContext: (context) async => stored = context,
        clearSelectedContext: (profileId) async {
          clearCalls++;
          stored = null;
        },
      );
}

OperationalBootstrapEntryRequest _request({
  OperationalContextSelection? selection,
}) =>
    OperationalBootstrapEntryRequest(
      mode: OperationalBootstrapMode.recovery,
      selection: selection,
    );

AuthorizedOperationalContext _context({
  String branchId = 'branch-x',
  List<String> permissions = const ['inventory.read'],
}) =>
    AuthorizedOperationalContext(
      profileId: 'profile-1',
      businessId: 'business-1',
      businessName: 'Business',
      businessStatus: 'active',
      businessUpdatedAt: DateTime.utc(2026, 8, 20),
      branchId: branchId,
      branchName: branchId,
      branchStatus: 'active',
      branchUpdatedAt: DateTime.utc(2026, 8, 20),
      membershipIds: const ['membership-1'],
      membershipsUpdatedAt: DateTime.utc(2026, 8, 20),
      effectiveRoles: const [
        AuthorizedOperationalRole(
          roleId: 'role-1',
          roleName: 'custom',
          isSystemRole: false,
          membershipIds: ['membership-1'],
        ),
      ],
      effectivePermissions: permissions,
    );

ResolvedBusinessRuntime _runtime({bool ready = true}) =>
    ResolvedBusinessRuntime(
      profileId: 'profile-1',
      businessId: 'business-1',
      businessName: 'Business',
      branchId: 'branch-x',
      branchName: 'X',
      cashRegisterId: ready ? 'cash-1' : null,
      cashRegisterName: ready ? 'Caja Principal' : null,
      receiptSequenceId: ready ? 'receipt-1' : null,
      receiptSequenceName: ready ? 'Recibos X' : null,
      receiptPrefix: ready ? 'POS' : null,
      openCashSession: ready
          ? ResolvedOpenCashSession(
              cashSessionId: 'session-1',
              cashRegisterId: 'cash-1',
              status: 'open',
              openedBy: 'profile-1',
              openedAt: DateTime.utc(2026, 8, 20),
            )
          : null,
      runtimeReady: ready,
      resolvedAt: DateTime.utc(2026, 8, 20),
    );

OperationalBootstrapResult _bootstrapResult({
  OperationalBootstrapOutcome outcome = OperationalBootstrapOutcome.ready,
  bool offlineReady = true,
  List<OperationalBootstrapBlockingIssue> issues = const [],
}) =>
    OperationalBootstrapResult(
      outcome: outcome,
      profileId: 'profile-1',
      businessId: 'business-1',
      branchId: 'branch-x',
      appDeviceId: 'device-1',
      requiredBundles: const ['core', 'product_operational'],
      completedBundles:
          offlineReady ? const ['core', 'product_operational'] : const ['core'],
      blockingIssues: issues,
      warnings: const [],
      recoveredCounts: const {},
      checkpoints: const [],
      offlineReady: offlineReady,
      message: outcome.name,
    );
