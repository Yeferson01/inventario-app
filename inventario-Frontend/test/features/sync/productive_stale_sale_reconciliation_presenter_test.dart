import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/sync/application/intentional_stale_sale_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/productive_stale_sale_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/unmaterialized_local_sale_discard_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/pos_sync_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/productive_stale_sale_reconciliation_presenter.dart';

void main() {
  testWidgets('in-flight reconciliation does not present the same Sale twice',
      (tester) async {
    final gate = Completer<void>();
    final fake = _FakeController(reconcileGate: gate);
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    Future<void> present() => ProductiveStaleSaleReconciliationPresenter.show(
          context: hostContext,
          service: fake,
          profileId: 'profile-a',
          businessId: 'business-a',
          branchId: 'branch-a',
          appDeviceId: 'device-a',
          effectivePermissions: const {
            'sales.reconcile_stale_cash_session',
            'sales.create',
          },
          onOpenCash: ({
            required saleId,
            required originalCashSessionId,
            required cashRegisterId,
          }) async {},
        );

    final first = present();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, ocurrió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No estaba incluido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmo: la venta SÍ ocurrió'));
    await tester.pump();
    expect(find.text('Reconciliando venta…'), findsOneWidget);

    final second = present();
    await tester.pump();
    expect(find.text('Venta pendiente de reconciliación'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    await first;
    await second;
    expect(fake.reconcileCalls, 1);
  });

  testWidgets('an in-flight Sale does not block a different Sale',
      (tester) async {
    final gate = Completer<void>();
    final firstFake = _FakeController(reconcileGate: gate);
    final secondFake = _FakeController(saleId: 'sale-b');
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    Future<void> present(_FakeController fake) =>
        ProductiveStaleSaleReconciliationPresenter.show(
          context: hostContext,
          service: fake,
          profileId: 'profile-a',
          businessId: 'business-a',
          branchId: 'branch-a',
          appDeviceId: 'device-a',
          effectivePermissions: const {
            'sales.reconcile_stale_cash_session',
            'sales.create',
          },
          onOpenCash: ({
            required saleId,
            required originalCashSessionId,
            required cashRegisterId,
          }) async {},
        );

    final first = present(firstFake);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, ocurrió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No estaba incluido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmo: la venta SÍ ocurrió'));
    await tester.pump();
    expect(find.text('Reconciliando venta…'), findsOneWidget);

    final second = present(secondFake);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('¿La venta ocurrió realmente?'), findsOneWidget);
    await tester.tap(find.text('Resolver después').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await second;

    gate.complete();
    await tester.pumpAndSettle();
    await first;
    expect(firstFake.reconcileCalls, 1);
    expect(secondFake.reconcileCalls, 0);
  });

  testWidgets('completed reconciliation closes and advances once',
      (tester) async {
    var presenterClosed = 0;
    final fake = _FakeController();
    await _pumpHarness(
      tester,
      fake,
      onPresenterClosed: () => presenterClosed++,
    );
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, ocurrió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No estaba incluido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmo: la venta SÍ ocurrió'));
    await tester.pumpAndSettle();

    expect(fake.reconcileCalls, 1);
    expect(presenterClosed, 1);
    expect(find.text('Venta pendiente de reconciliación'), findsNothing);
  });

  testWidgets('failed reconciliation keeps the Sale visible for retry',
      (tester) async {
    final fake = _FakeController(
      reconcileFailure: StateError('reconciliation failed'),
    );
    await _pumpHarness(tester, fake);
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, ocurrió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No estaba incluido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmo: la venta SÍ ocurrió'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo resolver la venta'), findsOneWidget);
    expect(fake.resolved, isFalse);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    expect(find.textContaining('¿La venta ocurrió realmente?'), findsOneWidget);
  });

  testWidgets('closed-session rejection opens the productive flow',
      (tester) async {
    final fake = _FakeController(pendingCount: 2);
    await _pumpHarness(tester, fake);
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    expect(find.text('2 ventas pendientes de reconciliación'), findsOneWidget);
    expect(find.textContaining('¿La venta ocurrió realmente?'), findsOneWidget);
  });

  testWidgets('did-occur action requires reconcile and sales.create',
      (tester) async {
    final fake = _FakeController();
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    final presentation = ProductiveStaleSaleReconciliationPresenter.show(
      context: hostContext,
      service: fake,
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
      appDeviceId: 'device-a',
      effectivePermissions: const {
        'sales.reconcile_stale_cash_session',
      },
      onOpenCash: ({
        required saleId,
        required originalCashSessionId,
        required cashRegisterId,
      }) async {},
    );
    await tester.pumpAndSettle();

    expect(find.text('Sí, ocurrió'), findsNothing);
    expect(
        find.textContaining('requiere un usuario autorizado'), findsOneWidget);
    await tester.tap(find.text('Resolver después'));
    await tester.pumpAndSettle();
    await presentation;
    expect(fake.reconcileCalls, 0);
  });

  testWidgets('did-not-occur delegates to discard service contract',
      (tester) async {
    final fake = _FakeController();
    var presenterClosed = false;
    await _pumpHarness(
      tester,
      fake,
      onPresenterClosed: () => presenterClosed = true,
    );
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, no ocurrió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmo: la venta NO ocurrió'));
    await tester.pumpAndSettle();
    expect(fake.discardCalls, 1);
    expect(fake.reconcileCalls, 0);
    expect(fake.loadCalls, 2);
    expect(presenterClosed, isTrue);
    expect(find.textContaining('¿La venta ocurrió realmente?'), findsNothing);
  });

  testWidgets('occurred Sale with S2 delegates selected treatment',
      (tester) async {
    final fake = _FakeController();
    await _pumpHarness(tester, fake);
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, ocurrió'));
    await tester.pumpAndSettle();
    expect(find.text('Tratamiento del efectivo'), findsOneWidget);
    await tester.tap(find.text('No estaba incluido'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmo: la venta SÍ ocurrió'));
    await tester.pumpAndSettle();
    expect(fake.reconcileCalls, 1);
    expect(
      fake.lastTreatment,
      IntentionalStaleSaleCashTreatment.notIncludedInDestinationOpening,
    );
  });

  testWidgets('missing S2 asks to open cash and does not reconcile',
      (tester) async {
    final fake = _FakeController(destinationId: null);
    var openCashCalls = 0;
    await _pumpHarness(
      tester,
      fake,
      onOpenCash: () async => openCashCalls++,
    );
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, ocurrió'));
    await tester.pumpAndSettle();
    expect(find.text('No hay una caja abierta'), findsOneWidget);
    expect(find.text('Tratamiento del efectivo'), findsNothing);
    await tester.tap(find.text('Abrir caja'));
    await tester.pumpAndSettle();
    expect(openCashCalls, 1);
    expect(fake.reconcileCalls, 0);
  });

  testWidgets('opening cash re-queries S2 before asking cash treatment',
      (tester) async {
    final fake = _FakeController(
      destinationSequence: [null, 'session-s2'],
    );
    var openCashCalls = 0;
    await _pumpHarness(
      tester,
      fake,
      onOpenCash: () async => openCashCalls++,
    );
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, ocurrió'));
    await tester.pumpAndSettle();
    expect(find.text('Tratamiento del efectivo'), findsNothing);
    await tester.tap(find.text('Abrir caja'));
    await tester.pumpAndSettle();

    expect(openCashCalls, 1);
    expect(fake.resolveCalls, 2);
    expect(find.text('Tratamiento del efectivo'), findsOneWidget);
    expect(fake.previewCalls, 0);
    await tester.tap(find.text('No estaba incluido'));
    await tester.pumpAndSettle();
    expect(fake.previewCalls, 1);
    expect(fake.lastPreviewDestination, 'session-s2');
  });

  testWidgets('original S1 is never accepted as destination fallback',
      (tester) async {
    final fake = _FakeController(destinationId: 'session-s1');
    await _pumpHarness(tester, fake);
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, ocurrió'));
    await tester.pumpAndSettle();

    expect(find.text('No hay una caja abierta'), findsOneWidget);
    expect(find.text('Tratamiento del efectivo'), findsNothing);
    expect(fake.previewCalls, 0);
  });

  testWidgets('already-discarded terminal Sale is removed idempotently',
      (tester) async {
    final fake = _FakeController(alreadyDiscarded: true);
    var presenterClosed = false;
    await _pumpHarness(
      tester,
      fake,
      onPresenterClosed: () => presenterClosed = true,
    );
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, no ocurrió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmo: la venta NO ocurrió'));
    await tester.pumpAndSettle();

    expect(fake.discardCalls, 1);
    expect(fake.loadCalls, 2);
    expect(fake.restoredQuantity, 0);
    expect(presenterClosed, isTrue);
    expect(find.textContaining('¿La venta ocurrió realmente?'), findsNothing);
  });

  testWidgets(
      'already-in-opening preview shows negative adjustment and zero net',
      (tester) async {
    final fake = _FakeController();
    await _pumpHarness(tester, fake);
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, ocurrió'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, ya estaba incluido'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ajuste: -\$10.00'), findsOneWidget);
    expect(
      find.textContaining('Impacto neto en efectivo: \$0.00'),
      findsOneWidget,
    );
  });

  testWidgets('resolve later leaves Sale and issue untouched', (tester) async {
    final fake = _FakeController();
    await _pumpHarness(tester, fake);
    await tester.tap(find.text('Abrir resolución'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolver después').first);
    await tester.pumpAndSettle();
    expect(fake.discardCalls, 0);
    expect(fake.reconcileCalls, 0);
  });
}

Future<void> _pumpHarness(
  WidgetTester tester,
  _FakeController fake, {
  Future<void> Function()? onOpenCash,
  Future<void> Function()? onRefreshCashContext,
  VoidCallback? onPresenterClosed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              await ProductiveStaleSaleReconciliationPresenter.show(
                context: context,
                service: fake,
                profileId: 'profile-a',
                businessId: 'business-a',
                branchId: 'branch-a',
                appDeviceId: 'device-a',
                effectivePermissions: const {
                  'sales.reconcile_stale_cash_session',
                  'sales.create',
                },
                onRefreshCashContext: ({
                  required saleId,
                  required originalCashSessionId,
                  required cashRegisterId,
                }) =>
                    (onRefreshCashContext ?? () async {})(),
                onOpenCash: ({
                  required saleId,
                  required originalCashSessionId,
                  required cashRegisterId,
                }) =>
                    (onOpenCash ?? () async {})(),
              );
              onPresenterClosed?.call();
            },
            child: const Text('Abrir resolución'),
          ),
        ),
      ),
    ),
  );
}

class _FakeController implements ProductiveStaleSaleReconciliationController {
  _FakeController({
    this.pendingCount = 1,
    this.saleId = 'sale-a',
    this.destinationId = 'session-s2',
    this.destinationSequence,
    this.alreadyDiscarded = false,
    this.reconcileGate,
    this.reconcileFailure,
  });

  final int pendingCount;
  final String saleId;
  final String? destinationId;
  final List<String?>? destinationSequence;
  final bool alreadyDiscarded;
  final Completer<void>? reconcileGate;
  final Object? reconcileFailure;
  var resolved = false;
  var loadCalls = 0;
  var resolveCalls = 0;
  var previewCalls = 0;
  var discardCalls = 0;
  var reconcileCalls = 0;
  var restoredQuantity = 0;
  String? lastPreviewDestination;
  IntentionalStaleSaleCashTreatment? lastTreatment;

  StaleSaleResolutionCandidate get candidate => StaleSaleResolutionCandidate(
        issueId: 'issue-$saleId',
        saleId: saleId,
        syncConflictId: 'conflict-$saleId',
        businessId: 'business-a',
        branchId: 'branch-a',
        branchName: 'Principal',
        originalCashSessionId: 'session-s1',
        cashRegisterId: 'register-a',
        total: 10,
        createdAt: DateTime(2026, 8, 31, 10),
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
  }) async {
    loadCalls++;
    return resolved
        ? const []
        : List<StaleSaleResolutionCandidate>.filled(pendingCount, candidate);
  }

  @override
  Future<String?> resolveOpenDestination(
    StaleSaleResolutionCandidate candidate,
  ) async {
    final index = resolveCalls++;
    final sequence = destinationSequence;
    if (sequence != null && index < sequence.length) return sequence[index];
    return destinationId;
  }

  @override
  Future<IntentionalStaleSaleReconciliationPreview> previewOccurred({
    required StaleSaleResolutionCandidate candidate,
    required String destinationCashSessionId,
    required IntentionalStaleSaleCashTreatment cashTreatment,
  }) async {
    previewCalls++;
    lastPreviewDestination = destinationCashSessionId;
    final adjustment = cashTreatment ==
            IntentionalStaleSaleCashTreatment
                .alreadyIncludedInDestinationOpening
        ? -10.0
        : 0.0;
    return IntentionalStaleSaleReconciliationPreview(
      local: IntentionalStaleSaleLocalPreview(
        saleId: candidate.saleId,
        saleTotal: 10,
        cashTotal: 10,
        originalCashSessionId: 'session-s1',
        destinationCashSessionId: destinationCashSessionId,
        destinationOpeningAmount: 110,
        destinationCurrentCashPayments: 0,
        affectedStock: const [],
      ),
      cashTreatment: cashTreatment,
      expectedAdjustment: adjustment,
      projectedExpectedCash: 110,
    );
  }

  @override
  Future<DiscardUnmaterializedLocalSaleResult> discardDidNotOccur({
    required String profileId,
    required String appDeviceId,
    required StaleSaleResolutionCandidate candidate,
  }) async {
    discardCalls++;
    resolved = true;
    restoredQuantity += alreadyDiscarded ? 0 : 1;
    return DiscardUnmaterializedLocalSaleResult(
      remoteEvidence: const UnmaterializedSaleRemoteEvidence(
        businessId: 'business-a',
        branchId: 'branch-a',
        saleId: 'sale-a',
        saleRows: 0,
        saleItemRows: 0,
        salePaymentRows: 0,
        inventoryMovementRows: 0,
        expectedConflictFound: true,
      ),
      remoteFinalization: const SaleDidNotOccurRemoteResult(
        businessId: 'business-a',
        branchId: 'branch-a',
        saleId: 'sale-a',
        syncConflictId: 'conflict-a',
        status: 'completed',
        resolutionStrategy: 'discard_unmaterialized_sale',
        idempotencyKey: 'discard-sale-a',
        mutationsTerminalized: 3,
        idempotent: false,
      ),
      localResult: DiscardUnmaterializedLocalSaleLocalResult(
        saleId: 'sale-a',
        alreadyDiscarded: alreadyDiscarded,
        movementsDiscarded: alreadyDiscarded ? 0 : 1,
        mutationsTerminalized: alreadyDiscarded ? 0 : 3,
        issuesResolved: alreadyDiscarded ? 0 : 1,
        restoredQuantityByProduct:
            alreadyDiscarded ? const {} : const {'product-a': 1},
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
    lastTreatment = cashTreatment;
    if (reconcileFailure != null) throw reconcileFailure!;
    if (reconcileGate != null) await reconcileGate!.future;
    resolved = true;
    return IntentionalStaleSaleReconciliationResult(
      remote: IntentionalStaleSaleRemoteResult(
        reconciliationId: 'reconciliation-a',
        businessId: 'business-a',
        branchId: 'branch-a',
        saleId: 'sale-a',
        cashRegisterId: 'register-a',
        originalCashSessionId: 'session-s1',
        destinationCashSessionId: destinationCashSessionId,
        syncConflictId: 'conflict-a',
        cashTreatment: cashTreatment.wireValue,
        cashReconciledTotal: 10,
        cashAdjustmentTotal: 0,
        cashAdjustmentAmount: 0,
        projectedExpectedCash: 120,
        status: 'completed',
        idempotent: false,
      ),
      local: const IntentionalStaleSaleLocalProjectionResult(
        saleId: 'sale-a',
        alreadyProjected: false,
        movementsAcknowledged: 1,
        mutationsSuperseded: 3,
        issuesResolved: 1,
        stockByProductBefore: {'product-a': 25},
        stockByProductAfter: {'product-a': 25},
      ),
      inventoryRefreshed: true,
      cashRefreshed: true,
    );
  }
}
