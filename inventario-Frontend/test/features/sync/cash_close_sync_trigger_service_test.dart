import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_models.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_service.dart';
import 'package:inventario_frontend/features/sync/application/app_sync_coordinator_models.dart';
import 'package:inventario_frontend/features/sync/application/cash_close_sync_trigger_service.dart';
import 'package:inventario_frontend/features/sync/application/cash_session_close_readiness_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/cash_session_close_readiness_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';
import 'package:inventario_frontend/features/sync/application/productive_manual_sync_service.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';

void main() {
  test('C4B1B same-device cash effect converges before close RPC', () async {
    final fixture = _Fixture(cashMovementInitiallyPending: true);
    await fixture.closeService.closeCashSession(_closeInput);
    expect(fixture.events.indexOf('cash'),
        lessThan(fixture.events.indexOf('close')));
    expect(fixture.closeCalls, 1);
  });

  test('C4B1B failed cash effect blocks close RPC', () async {
    final fixture = _Fixture(
      cashMovementInitiallyPending: true,
      retryableDomain: ProductiveSyncDomain.cash,
    );
    await expectLater(fixture.closeService.closeCashSession(_closeInput),
        throwsA(isA<CashCloseSyncBlockedException>()));
    expect(fixture.closeCalls, 0);
    fixture.retryableDomain = null;
    await fixture.closeService.closeCashSession(_closeInput);
    expect(fixture.closeCalls, 1);
  });
  test('CC-01 clean close runs productive sync before authoritative close',
      () async {
    final fixture = _Fixture();

    final result = await fixture.closeService.closeCashSession(_closeInput);

    expect(result.closeResult.status, 'closed');
    expect(fixture.events, [..._syncOrder, 'close']);
    expect(fixture.closeCalls, 1);
    expect(fixture.seenTrigger, ProductiveSyncTrigger.cashClose);
  });

  test('CC-02 pending sale publishes POS before close', () async {
    final fixture = _Fixture();

    await fixture.closeService.closeCashSession(_closeInput);

    expect(fixture.events.indexOf('pos'),
        lessThan(fixture.events.indexOf('close')));
  });

  test('CC-03 retryable Purchase is attempted but does not block cash close',
      () async {
    final fixture = _Fixture(
      pendingPurchases: 1,
      retryableDomain: ProductiveSyncDomain.purchases,
    );

    final result = await fixture.closeService.closeCashSession(_closeInput);

    expect(fixture.events.indexOf('purchases'),
        lessThan(fixture.events.indexOf('close')));
    expect(
      result.nonCriticalPendingDomains,
      contains(ProductiveSyncDomain.purchases),
    );
    expect(fixture.closeCalls, 1);
  });

  test('CC-04 Product dependency runs before Purchase and close', () async {
    final fixture = _Fixture();

    await fixture.closeService.closeCashSession(_closeInput);

    expect(
      fixture.events.indexOf('catalog-upload'),
      lessThan(fixture.events.indexOf('purchases')),
    );
    expect(
      fixture.events.indexOf('purchases'),
      lessThan(fixture.events.indexOf('close')),
    );
  });

  test('CC-05 independent Inventory is processed before close', () async {
    final fixture = _Fixture();

    await fixture.closeService.closeCashSession(_closeInput);

    expect(
      fixture.events.indexOf('inventory'),
      lessThan(fixture.events.indexOf('close')),
    );
  });

  test('CC-06 mixed domains keep one dependency-safe order and one close',
      () async {
    final fixture = _Fixture();

    await fixture.closeService.closeCashSession(_closeInput);

    expect(fixture.events, [..._syncOrder, 'close']);
    expect(fixture.closeCalls, 1);
  });

  test('CC-07 retryable POS failure blocks authoritative close', () async {
    final fixture = _Fixture(
      pendingSales: 1,
      retryableDomain: ProductiveSyncDomain.pos,
    );

    await expectLater(
      fixture.closeService.closeCashSession(_closeInput),
      throwsA(
        isA<CashCloseSyncBlockedException>().having(
          (error) => error.reason,
          'reason',
          CashCloseSyncBlockReason.sessionNotReady,
        ),
      ),
    );
    expect(fixture.closeCalls, 0);
  });

  test('CC-08 unrelated global attention does not block clean session close',
      () async {
    final fixture = _Fixture(requiresAttention: true);
    await fixture.closeService.closeCashSession(_closeInput);
    expect(fixture.closeCalls, 1);
  });

  test('CC-09 offline does not fake a local or authoritative close', () async {
    final fixture = _Fixture(isOnline: false);

    await expectLater(
      fixture.closeService.closeCashSession(_closeInput),
      throwsA(isA<CashCloseSyncBlockedException>()),
    );
    expect(fixture.events, isEmpty);
    expect(fixture.closeCalls, 0);
  });

  test('CC-10 active manual sync is shared and close RPC runs exactly once',
      () async {
    final gate = Completer<ProductiveSyncDomainResult>();
    final fixture = _Fixture(firstDomainGate: gate);

    final manual = fixture.productive.run();
    await Future<void>.delayed(Duration.zero);
    final close = fixture.closeService.closeCashSession(_closeInput);
    await Future<void>.delayed(Duration.zero);

    expect(fixture.events, ['catalog-upload']);
    expect(fixture.closeCalls, 0);
    gate.complete(
      const ProductiveSyncDomainResult.succeeded(
        ProductiveSyncDomain.catalog,
      ),
    );
    await manual;
    await close;

    expect(fixture.events, [..._syncOrder, 'close']);
    expect(fixture.closeCalls, 1);
  });
}

const _syncOrder = [
  'catalog-upload',
  'cash',
  'pos',
  'purchases',
  'inventory',
  'catalog-refresh',
  'status',
];

const _closeInput = CloseCashSessionInput(
  businessId: 'business-1',
  branchId: 'branch-1',
  profileId: 'profile-1',
  actualClosingAmount: 100,
);

class _Fixture {
  _Fixture({
    this.isOnline = true,
    this.pendingSales = 0,
    this.pendingPurchases = 0,
    this.retryableDomain,
    this.requiresAttention = false,
    this.firstDomainGate,
    this.cashMovementInitiallyPending = false,
  }) {
    movementSynced = !cashMovementInitiallyPending;
    productive = ProductiveManualSyncService(
      inputLoader: () async => AppSyncCoordinatorInput(
        businessId: 'business-1',
        branchId: 'branch-1',
        profileId: 'profile-1',
        installationId: 'installation-1',
        isOnline: isOnline,
      ),
      contextValidator: (input) async {
        seenTrigger = switch (input.metadata?['sync_trigger']) {
          'cash_close' => ProductiveSyncTrigger.cashClose,
          'scheduled' => ProductiveSyncTrigger.scheduled,
          _ => ProductiveSyncTrigger.manual,
        };
        return const AppRuntimeContext(
          businessId: 'business-1',
          branchId: 'branch-1',
          profileId: 'profile-1',
          installationId: 'installation-1',
          appDeviceId: 'device-1',
        );
      },
      catalogUploadRunner: _catalog,
      cashRunner: (context) => _domain(ProductiveSyncDomain.cash, 'cash'),
      posRunner: (context) => _domain(ProductiveSyncDomain.pos, 'pos'),
      purchasesRunner: (context) =>
          _domain(ProductiveSyncDomain.purchases, 'purchases'),
      inventoryRunner: (context) =>
          _domain(ProductiveSyncDomain.inventory, 'inventory'),
      catalogRefreshRunner: _catalog,
      statusLoader: ({
        required scope,
        required isOnline,
        required isSyncing,
      }) async {
        events.add('status');
        return ProductiveSyncStatus(
          scope: scope,
          connectivity: ProductiveSyncConnectivity.online,
          isSyncing: false,
          pendingSales: pendingSales,
          pendingPurchases: pendingPurchases,
          pendingCashOperations: 0,
          pendingProductOperations: 0,
          pendingInventoryOperations: 0,
          openIssueCount: requiresAttention ? 1 : 0,
          attentionOperationCount: 0,
        );
      },
    );
    final cash = _RecordingCashSessionService(this);
    closeService = CashCloseSyncTriggerService(
      productiveSyncService: productive,
      cashSessionService: cash,
      closeReadinessService: CashSessionCloseReadinessService(
        evidenceLoader: (
                {required profileId,
                required businessId,
                required branchId}) async =>
            CashSessionCloseEvidence(
          session: const {
            'id': 'session-1',
            'cash_register_id': 'register-1',
            'local_status': 'synced',
            'sync_status': 0,
          },
          cashMovements: movementSynced
              ? const []
              : const [
                  {'id': 'cm', 'local_status': 'dirty', 'sync_status': 1}
                ],
          outboxMutations: const [],
          dirtyPosCount: retryableDomain == ProductiveSyncDomain.pos ? 1 : 0,
          openIssues: const [],
        ),
        dependencyReadinessLoader: (_) async => BatchDependencyReadiness.ready,
      ),
    );
  }

  final bool isOnline;
  final int pendingSales;
  final int pendingPurchases;
  ProductiveSyncDomain? retryableDomain;
  final bool requiresAttention;
  final Completer<ProductiveSyncDomainResult>? firstDomainGate;
  final bool cashMovementInitiallyPending;
  late bool movementSynced;
  final events = <String>[];
  late final ProductiveManualSyncService productive;
  late final CashCloseSyncTriggerService closeService;
  ProductiveSyncTrigger? seenTrigger;
  int closeCalls = 0;
  int _catalogCalls = 0;

  Future<ProductiveSyncDomainResult> _catalog(
    ProductiveSyncExecutionContext context,
  ) async {
    _catalogCalls++;
    events.add(_catalogCalls == 1 ? 'catalog-upload' : 'catalog-refresh');
    if (_catalogCalls == 1 && firstDomainGate != null) {
      return firstDomainGate!.future;
    }
    return const ProductiveSyncDomainResult.succeeded(
      ProductiveSyncDomain.catalog,
    );
  }

  Future<ProductiveSyncDomainResult> _domain(
    ProductiveSyncDomain domain,
    String event,
  ) async {
    events.add(event);
    if (retryableDomain == domain) {
      return ProductiveSyncDomainResult.failedRetryable(domain);
    }
    if (domain == ProductiveSyncDomain.cash) movementSynced = true;
    return ProductiveSyncDomainResult.succeeded(domain);
  }
}

class _RecordingCashSessionService implements CashSessionLocalService {
  _RecordingCashSessionService(this.fixture);

  final _Fixture fixture;

  @override
  Future<CloseCashSessionResult> closeCashSession(CloseCashSessionInput input,
      {String? expectedCashSessionId}) async {
    expect(expectedCashSessionId, 'session-1');
    fixture.events.add('close');
    fixture.closeCalls++;
    return CloseCashSessionResult(
      cashSessionId: 'session-1',
      cashRegisterId: 'register-1',
      businessId: input.businessId,
      branchId: input.branchId,
      expectedCashAmount: 100,
      actualClosingAmount: input.actualClosingAmount,
      differenceAmount: input.actualClosingAmount - 100,
      status: 'closed',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
