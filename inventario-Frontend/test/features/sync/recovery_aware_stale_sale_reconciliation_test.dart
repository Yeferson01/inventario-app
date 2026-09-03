import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_models.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_providers.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/sync/application/intentional_stale_sale_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_providers.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_orchestration_models.dart';
import 'package:inventario_frontend/features/sync/application/pos_sync_upload_provider.dart';
import 'package:inventario_frontend/features/sync/application/productive_stale_sale_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/recovery_blocked_stale_sale_service.dart';
import 'package:inventario_frontend/features/sync/application/unmaterialized_local_sale_discard_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/pos_sync_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_resolution_models.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/business_context_required_gate.dart';

void main() {
  testWidgets('A sale cash blocker offers productive review', (tester) async {
    final controller = _FakeController();
    await tester.pumpWidget(
      _app(
        controller: controller,
        entry: (_) async => _blockedEntry([_saleIssue()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recuperación requiere revisión'), findsOneWidget);
    expect(find.text('Revisar ventas'), findsOneWidget);
    expect(
        find.textContaining('1 venta no pudo sincronizarse'), findsOneWidget);
    expect(find.text('PRODUCTIVE CHILD').hitTestable(), findsNothing);
    await tester.tap(find.text('Revisar ventas'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Venta pendiente de reconciliación'), findsOneWidget);
    expect(find.textContaining('¿La venta ocurrió realmente?'), findsOneWidget);
  });

  test('B related Sale inventory movement is grouped as one resolution',
      () async {
    final service = RecoveryBlockedStaleSaleAssessmentService(
      loadPendingSales: ({
        required profileId,
        required businessId,
        required branchId,
      }) async =>
          [_FakeController.candidate],
      loadSaleMovements: ({required saleId}) async => [
        {
          'id': 'movement-a',
          'business_id': 'business-a',
          'branch_id': 'branch-a',
          'source_type': 'sale',
          'source_id': saleId,
        },
      ],
    );

    final result = await service.assess(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
      blockingIssues: [_saleIssue(), _inventoryIssue()],
    );

    expect(result.sales, hasLength(1));
    expect(result.relatedInventoryIssues, hasLength(1));
    expect(result.hardIssues, isEmpty);
    expect(result.isExclusivelyActionable, isTrue);
  });

  testWidgets('C unknown blocker remains hard without review bypass',
      (tester) async {
    final controller = _FakeController();
    await tester.pumpWidget(
      _app(
        controller: controller,
        entry: (_) async => _blockedEntry([_hardIssue()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recuperación bloqueada'), findsOneWidget);
    expect(find.text('Revisar ventas'), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('PRODUCTIVE CHILD').hitTestable(), findsNothing);
  });

  testWidgets('D resolving all Sales reruns recovery and admits Dashboard',
      (tester) async {
    final controller = _FakeController();
    var runs = 0;
    await tester.pumpWidget(
      _app(
        controller: controller,
        entry: (_) async {
          runs++;
          return runs == 1 ? _blockedEntry([_saleIssue()]) : _readyEntry();
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar ventas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, no ocurrió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmo: la venta NO ocurrió'));
    await tester.pumpAndSettle();

    expect(controller.discardCalls, 1);
    expect(runs, 2);
    expect(find.text('PRODUCTIVE CHILD'), findsOneWidget);
  });

  testWidgets('E resolve later keeps recovery gate and POS inaccessible',
      (tester) async {
    final controller = _FakeController();
    var runs = 0;
    await tester.pumpWidget(
      _app(
        controller: controller,
        entry: (_) async {
          runs++;
          return _blockedEntry([_saleIssue()]);
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar ventas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolver después').first);
    await tester.pumpAndSettle();

    expect(controller.discardCalls, 0);
    expect(controller.reconcileCalls, 0);
    expect(runs, 1);
    expect(find.text('Recuperación requiere revisión'), findsOneWidget);
    expect(find.text('PRODUCTIVE CHILD').hitTestable(), findsNothing);
  });
}

Widget _app({
  required _FakeController controller,
  required Future<OperationalBootstrapEntryResult> Function(
    ProductiveOperationalEntryRequest request,
  ) entry,
}) {
  final assessment = RecoveryBlockedStaleSaleAssessmentService(
    loadPendingSales: controller.loadPending,
    loadSaleMovements: ({required saleId}) async => [
      {
        'id': 'movement-a',
        'business_id': 'business-a',
        'branch_id': 'branch-a',
        'source_type': 'sale',
        'source_id': saleId,
      },
    ],
  );
  final navigatorKey = GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: [
      productiveOperationalEntryProvider.overrideWith(
        (ref, request) => entry(request),
      ),
      authenticatedAccessResolverProvider.overrideWith(
        (ref, profileId) async => AuthenticatedAccessResult(
          outcome: AuthenticatedAccessOutcome.existingContexts,
          contexts: [_context()],
          pendingInvitations: const [],
          message: 'authorized',
        ),
      ),
      recoveryBlockedStaleSaleAssessmentServiceProvider.overrideWithValue(
        assessment,
      ),
      productiveStaleSaleReconciliationServiceProvider.overrideWithValue(
        controller,
      ),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => BusinessContextRequiredGate(
        profileId: 'profile-a',
        navigatorContextResolver: () =>
            navigatorKey.currentState?.overlay?.context,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(body: Text('PRODUCTIVE CHILD')),
    ),
  );
}

OperationalBootstrapEntryResult _blockedEntry(
  List<OperationalBootstrapBlockingIssue> issues,
) {
  return OperationalBootstrapEntryResult(
    outcome: OperationalBootstrapEntryOutcome.bootstrapRecoveryBlocked,
    contexts: [_context()],
    message: 'blocked',
    offlineReady: false,
    canRequestAdministrativeSetup: false,
    profileId: 'profile-a',
    installationId: 'installation-a',
    selectedContext: _context(),
    device: const RegisteredAppDeviceResult(
      appDeviceId: 'device-a',
      businessId: 'business-a',
      branchId: 'branch-a',
      installationId: 'installation-a',
      status: 'active',
      raw: {},
    ),
    runtime: ResolvedBusinessRuntime(
      profileId: 'profile-a',
      businessId: 'business-a',
      businessName: 'Business A',
      branchId: 'branch-a',
      branchName: 'Principal',
      cashRegisterId: 'register-a',
      cashRegisterName: 'Caja A',
      receiptSequenceId: 'sequence-a',
      receiptSequenceName: 'Sequence A',
      receiptPrefix: 'A',
      openCashSession: null,
      runtimeReady: true,
      resolvedAt: DateTime.utc(2026, 9, 1),
    ),
    bootstrapResult: OperationalBootstrapResult(
      outcome: OperationalBootstrapOutcome.recoveryBlocked,
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
      appDeviceId: 'device-a',
      requiredBundles: const ['core', 'product_operational', 'cash_pos'],
      completedBundles: const ['core'],
      blockingIssues: issues,
      warnings: const [],
      recoveredCounts: const {},
      checkpoints: const [],
      offlineReady: false,
      message: 'blocked',
      canonicalCashRegisterId: 'register-a',
    ),
  );
}

OperationalBootstrapEntryResult _readyEntry() {
  return OperationalBootstrapEntryResult(
    outcome: OperationalBootstrapEntryOutcome.runtimeReadyAndBootstrapCompleted,
    contexts: [_context()],
    message: 'ready',
    offlineReady: true,
    canRequestAdministrativeSetup: false,
    profileId: 'profile-a',
    selectedContext: _context(),
  );
}

AuthorizedOperationalContext _context() => AuthorizedOperationalContext(
      profileId: 'profile-a',
      businessId: 'business-a',
      businessName: 'Business A',
      businessStatus: 'active',
      businessUpdatedAt: DateTime.utc(2026, 9, 1),
      branchId: 'branch-a',
      branchName: 'Principal',
      branchStatus: 'active',
      branchUpdatedAt: DateTime.utc(2026, 9, 1),
      membershipIds: const ['membership-a'],
      membershipsUpdatedAt: DateTime.utc(2026, 9, 1),
      effectiveRoles: const [],
      effectivePermissions: const [
        'sales.create',
        'sales.reconcile_stale_cash_session',
        'cash.open',
      ],
    );

OperationalBootstrapBlockingIssue _saleIssue() =>
    const OperationalBootstrapBlockingIssue(
      issueType: 'sale_cash_session_rejected',
      domain: 'cash_pos',
      entityType: 'sales',
      entityId: 'sale-a',
      message: 'Sale rejected because cash session is closed.',
      metadata: {
        'remote_reason': 'closed',
        'sync_conflict_id': 'conflict-a',
      },
    );

OperationalBootstrapBlockingIssue _inventoryIssue() =>
    const OperationalBootstrapBlockingIssue(
      issueType: 'terminal_incompatible_inventory_movement',
      domain: 'inventory_balance',
      entityType: 'inventory_movements',
      entityId: 'movement-a',
      message: 'Rejected movement.',
    );

OperationalBootstrapBlockingIssue _hardIssue() =>
    const OperationalBootstrapBlockingIssue(
      issueType: 'unknown_blocker',
      domain: 'unknown',
      message: 'Unknown recovery blocker.',
    );

class _FakeController implements ProductiveStaleSaleReconciliationController {
  var resolved = false;
  var discardCalls = 0;
  var reconcileCalls = 0;

  static final candidate = StaleSaleResolutionCandidate(
    issueId: 'issue-a',
    saleId: 'sale-a',
    syncConflictId: 'conflict-a',
    businessId: 'business-a',
    branchId: 'branch-a',
    branchName: 'Principal',
    originalCashSessionId: 'session-s1',
    cashRegisterId: 'register-a',
    total: 10,
    createdAt: DateTime.utc(2026, 9, 1),
    payments: const [
      StaleSalePaymentSummary(
        method: 'cash',
        amount: 10,
        status: 'completed',
      ),
    ],
    items: const [
      StaleSaleItemSummary(productName: 'Producto A', quantity: 1),
    ],
  );

  @override
  Future<List<StaleSaleResolutionCandidate>> loadPending({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async =>
      resolved ? const [] : [candidate];

  @override
  Future<String?> resolveOpenDestination(
    StaleSaleResolutionCandidate candidate,
  ) async =>
      'session-s2';

  @override
  Future<IntentionalStaleSaleReconciliationPreview> previewOccurred({
    required StaleSaleResolutionCandidate candidate,
    required String destinationCashSessionId,
    required IntentionalStaleSaleCashTreatment cashTreatment,
  }) =>
      throw UnimplementedError();

  @override
  Future<DiscardUnmaterializedLocalSaleResult> discardDidNotOccur({
    required String profileId,
    required String appDeviceId,
    required StaleSaleResolutionCandidate candidate,
  }) async {
    discardCalls++;
    resolved = true;
    return const DiscardUnmaterializedLocalSaleResult(
      remoteEvidence: UnmaterializedSaleRemoteEvidence(
        businessId: 'business-a',
        branchId: 'branch-a',
        saleId: 'sale-a',
        saleRows: 0,
        saleItemRows: 0,
        salePaymentRows: 0,
        inventoryMovementRows: 0,
        expectedConflictFound: true,
      ),
      remoteFinalization: SaleDidNotOccurRemoteResult(
        businessId: 'business-a',
        branchId: 'branch-a',
        saleId: 'sale-a',
        syncConflictId: 'conflict-sale-a',
        status: 'completed',
        resolutionStrategy: 'discard_unmaterialized_sale',
        idempotencyKey: 'sale-did-not-occur:sale-a:conflict-sale-a',
        mutationsTerminalized: 3,
        idempotent: false,
      ),
      localResult: DiscardUnmaterializedLocalSaleLocalResult(
        saleId: 'sale-a',
        alreadyDiscarded: false,
        movementsDiscarded: 1,
        mutationsTerminalized: 3,
        issuesResolved: 2,
        restoredQuantityByProduct: {'product-a': 1},
      ),
    );
  }

  @override
  Future<IntentionalStaleSaleReconciliationResult> reconcileDidOccur({
    required String profileId,
    required String appDeviceId,
    required Set<String> effectivePermissions,
    required StaleSaleResolutionCandidate candidate,
    required String destinationCashSessionId,
    required IntentionalStaleSaleCashTreatment cashTreatment,
  }) async {
    reconcileCalls++;
    throw UnimplementedError();
  }
}
