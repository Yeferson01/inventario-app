import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/database/database_provider.dart';
import 'package:inventario_frontend/core/providers/connectivity_provider.dart';
import 'package:inventario_frontend/features/cash/application/cash_movement_models.dart';
import 'package:inventario_frontend/features/cash/application/cash_movement_service.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_models.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_provider.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/purchase_local_dao.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_models.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_provider.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status_provider.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status_revision_provider.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';

void main() {
  test('RX-01 local Sale refreshes productive status automatically', () async {
    final harness = await _Harness.create(isOnline: true);
    addTearDown(harness.close);

    expect((await harness.current()).pendingSales, 0);
    await harness.insertSale();

    final status = await harness.waitFor((value) => value.pendingSales == 1);
    expect(status.pendingSales, 1);
  });

  test('RX-02 local Purchase refreshes productive status automatically',
      () async {
    final harness = await _Harness.create(isOnline: true);
    addTearDown(harness.close);

    expect((await harness.current()).pendingPurchases, 0);
    await harness.insertPurchase();

    final status =
        await harness.waitFor((value) => value.pendingPurchases == 1);
    expect(status.pendingPurchases, 1);
  });

  test('RX-03 Sale and Purchase refresh together without provider invalidation',
      () async {
    final harness = await _Harness.create(isOnline: true);
    addTearDown(harness.close);

    await harness.insertSale();
    await harness.insertPurchase();

    final status = await harness.waitFor(
      (value) => value.pendingSales == 1 && value.pendingPurchases == 1,
    );
    expect(status.totalPending, 2);
  });

  test('RX-04 application ACK hook refreshes 1/1 back to 0/0', () async {
    final harness = await _Harness.create(isOnline: true);
    addTearDown(harness.close);
    await harness.insertSale();
    await harness.insertPurchase();
    await harness.waitFor(
      (value) => value.pendingSales == 1 && value.pendingPurchases == 1,
    );

    await harness.projectAckAndNotify();

    final status = await harness.waitFor(
      (value) => value.pendingSales == 0 && value.pendingPurchases == 0,
    );
    expect(status.allUpToDate, isTrue);
  });

  test('RX-05 foreign scope writes do not change current scope counts',
      () async {
    final harness = await _Harness.create(isOnline: true);
    addTearDown(harness.close);

    await harness.insertSale(
      businessId: 'business-b',
      branchId: 'branch-b',
    );
    await harness.insertPurchase(
      businessId: 'business-b',
      branchId: 'branch-b',
    );
    await harness.waitForEmission();

    expect(harness.latest.pendingSales, 0);
    expect(harness.latest.pendingPurchases, 0);
  });

  test('RX-06 local state remains reactive while connectivity is offline',
      () async {
    final harness = await _Harness.create(isOnline: false);
    addTearDown(harness.close);

    await harness.insertSale();

    final status = await harness.waitFor((value) => value.pendingSales == 1);
    expect(status.connectivity, ProductiveSyncConnectivity.offline);
  });

  test('RX-07 committed cash outflow refreshes query-derived status once',
      () async {
    final harness = await _Harness.create(isOnline: true);
    addTearDown(harness.close);
    final service = await harness.prepareCashMovementService();

    expect((await harness.current()).allUpToDate, isTrue);
    final initialRevision = harness.revision;
    final request = harness.cashRequest(
      direction: CashMovementDirection.outflow,
      category: 'maintenance',
      key: 'outflow-1',
    );
    final first = await service.recordMovement(request);
    expect(first.alreadyRecorded, isFalse);
    expect(harness.revision, initialRevision + 1);
    expect(
        (await harness.waitFor((value) => value.pendingCashOperations == 1))
            .allUpToDate,
        isFalse);

    final revision = harness.revision;
    final retry = await service.recordMovement(request);
    expect(retry.alreadyRecorded, isTrue);
    expect(harness.revision, revision);
    harness.notifyLocalChange();
    expect((await harness.current()).totalPending, 1);

    await harness.projectCashAckAndNotify();
    expect(
        (await harness.waitFor((value) => value.pendingCashOperations == 0))
            .allUpToDate,
        isTrue);
  });

  test('RX-08 committed cash inflow refreshes pending status', () async {
    final harness = await _Harness.create(isOnline: true);
    addTearDown(harness.close);
    final service = await harness.prepareCashMovementService();

    await service.recordMovement(harness.cashRequest(
      direction: CashMovementDirection.inflow,
      category: 'owner_contribution',
      key: 'inflow-1',
    ));
    final status =
        await harness.waitFor((value) => value.pendingCashOperations == 1);
    expect(status.totalPending, 1);
  });

  test('RX-09 rejected cash movement does not notify pending status', () async {
    final harness = await _Harness.create(isOnline: true);
    addTearDown(harness.close);
    final service = await harness.prepareCashMovementService();
    final revision = harness.revision;

    await expectLater(
      service.recordMovement(harness.cashRequest(
        direction: CashMovementDirection.outflow,
        category: 'maintenance',
        key: 'too-much',
        amountCents: BigInt.from(20000),
      )),
      throwsA(isA<CashMovementException>()),
    );
    expect(harness.revision, revision);
    expect((await harness.current()).allUpToDate, isTrue);
  });
}

class _Harness {
  _Harness._(this.database, this.container, this.subscription, this.emitted);

  static const request = ProductiveSyncStatusRequest(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-a',
    isSyncing: false,
  );

  final AppDatabase database;
  final ProviderContainer container;
  final ProviderSubscription<AsyncValue<ProductiveSyncStatus>> subscription;
  final List<ProductiveSyncStatus> emitted;

  ProductiveSyncStatus get latest => emitted.last;
  int get revision => container.read(productiveSyncStatusRevisionProvider);

  void notifyLocalChange() => container
      .read(productiveSyncStatusRevisionProvider.notifier)
      .markLocalStateChanged();

  static Future<_Harness> create({required bool isOnline}) async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    final saleDao = PosLocalSaleDao(database);
    final purchaseDao = PurchaseLocalDao(database);
    final statusService = ProductiveSyncStatusService(
      pendingSalesLoader: ({required businessId, required branchId}) {
        return saleDao.getPendingDirtySales(
          businessId: businessId,
          branchId: branchId,
          limit: 0x7fffffff,
        );
      },
      pendingPurchasesLoader: ({required businessId, required branchId}) {
        return purchaseDao.getPendingDirtyPurchases(
          businessId: businessId,
          branchId: branchId,
          limit: 0x7fffffff,
        );
      },
      cashReadinessLoader: ({required businessId, required branchId}) async {
        final pendingMovements = await database.customSelect('''
          select count(*) as count from local_cash_movements
          where business_id = ? and branch_id = ?
            and (local_status <> 'synced' or sync_status <> 0)
        ''', variables: [
          Variable<String>(businessId),
          Variable<String>(branchId),
        ]).getSingle();
        return {
          'dirty_cash_register_count': 0,
          'dirty_cash_session_count': 0,
          'dirty_cash_movement_count': pendingMovements.read<int>('count'),
          'pending_sales_without_cash_count': 0,
        };
      },
      openIssuesLoader: ({
        required profileId,
        required businessId,
        required branchId,
      }) async {
        return const [];
      },
      outboxStatusRowsLoader: ({
        required businessId,
        required branchId,
      }) async {
        return const [];
      },
      blockedPurchaseDependenciesLoader: ({
        required businessId,
        required branchId,
      }) async {
        return 0;
      },
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        isOnlineStreamProvider.overrideWith((ref) => Stream.value(isOnline)),
        productiveSyncStatusServiceProvider.overrideWithValue(statusService),
      ],
    );
    final emitted = <ProductiveSyncStatus>[];
    final subscription = container.listen(
      productiveSyncStatusProvider(request),
      (_, next) => next.whenData(emitted.add),
      fireImmediately: true,
    );
    final harness = _Harness._(database, container, subscription, emitted);
    await harness._seedScope('business-a', 'branch-a');
    await harness._seedScope('business-b', 'branch-b');
    await harness.current();
    return harness;
  }

  Future<ProductiveSyncStatus> current() async {
    final value = await container.read(
      productiveSyncStatusProvider(request).future,
    );
    if (emitted.isEmpty) emitted.add(value);
    return value;
  }

  Future<ProductiveSyncStatus> waitFor(
    bool Function(ProductiveSyncStatus value) predicate,
  ) async {
    if (emitted.isNotEmpty && predicate(latest)) return latest;
    final completer = Completer<ProductiveSyncStatus>();
    late final ProviderSubscription<AsyncValue<ProductiveSyncStatus>> listener;
    listener = container.listen(
      productiveSyncStatusProvider(request),
      (_, next) => next.whenData((value) {
        if (!completer.isCompleted && predicate(value)) {
          completer.complete(value);
        }
      }),
    );
    try {
      return await completer.future.timeout(const Duration(seconds: 1));
    } finally {
      listener.close();
    }
  }

  Future<void> waitForEmission() async {
    final before = emitted.length;
    final completer = Completer<void>();
    late final ProviderSubscription<AsyncValue<ProductiveSyncStatus>> listener;
    listener = container.listen(
      productiveSyncStatusProvider(request),
      (_, next) => next.whenData((_) {
        if (!completer.isCompleted && emitted.length > before) {
          completer.complete();
        }
      }),
    );
    try {
      await completer.future.timeout(const Duration(seconds: 1));
    } finally {
      listener.close();
    }
  }

  Future<void> insertSale({
    String businessId = 'business-a',
    String branchId = 'branch-a',
  }) async {
    await container.read(posLocalSaleServiceProvider).createLocalSale(
          CreatePosLocalSaleInput(
            businessId: businessId,
            branchId: branchId,
            profileId: 'profile-a',
            cashRegisterId: 'cash-register-a',
            cashSessionId: 'cash-session-a',
            items: [
              PosLocalSaleItemInput(
                productId: 'product-$businessId',
                quantity: 1,
              ),
            ],
          ),
        );
  }

  Future<void> insertPurchase({
    String businessId = 'business-a',
    String branchId = 'branch-a',
  }) async {
    await container.read(purchaseLocalServiceProvider).createLocalPurchase(
          CreatePurchaseLocalInput(
            businessId: businessId,
            branchId: branchId,
            profileId: 'profile-a',
            items: [
              PurchaseLocalItemInput(
                productId: 'product-$businessId',
                quantity: 1,
                unitCostCents: BigInt.from(50000),
              ),
            ],
          ),
        );
  }

  Future<CashMovementService> prepareCashMovementService() async {
    await database.into(database.cashRegisters).insert(
          CashRegistersCompanion.insert(
            id: 'cash-register-a',
            businessId: const Value('business-a'),
            branchId: const Value('branch-a'),
            name: const Value('Main'),
          ),
        );
    await database.into(database.cashSessions).insert(
          CashSessionsCompanion.insert(
            id: 'cash-session-a',
            businessId: const Value('business-a'),
            branchId: const Value('branch-a'),
            cashRegisterId: const Value('cash-register-a'),
            openedByProfileId: const Value('profile-a'),
            openingCashAmount: const Value(100),
          ),
        );
    await AuthorizedOperationalContextLocalDao(database).replaceContext(
      AuthorizedOperationalContextProjection(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-a',
        effectivePermissions: const ['cash.disburse', 'cash.receive'],
        effectiveRoles: const [],
        applicableMembershipIds: const [],
        authorizationValidatedAt: DateTime.now().toUtc(),
        snapshotId: 'cash-reactivity',
      ),
    );
    return CashMovementService(
      database: database,
      onCommitted: notifyLocalChange,
      loadCurrentContext: () async => const AppCurrentContext(
        businessId: 'business-a',
        branchId: 'branch-a',
        profileId: 'profile-a',
        installationId: 'install-a',
        appDeviceId: 'device-a',
        cashRegisterId: 'cash-register-a',
        cashSessionId: 'cash-session-a',
        isOnline: false,
        authorizationContextReady: true,
        permissions: AppPermissionSet({'cash.disburse', 'cash.receive'}),
      ),
    );
  }

  CashMovementRequest cashRequest({
    required CashMovementDirection direction,
    required String category,
    required String key,
    BigInt? amountCents,
  }) =>
      CashMovementRequest(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-a',
        cashRegisterId: 'cash-register-a',
        cashSessionId: 'cash-session-a',
        direction: direction,
        category: category,
        amountCents: amountCents ?? BigInt.from(5000),
        idempotencyKey: key,
      );

  Future<void> projectCashAckAndNotify() async {
    await database.customStatement(
      "update local_cash_movements set local_status = 'synced', sync_status = 0",
    );
    notifyLocalChange();
  }

  Future<void> projectAckAndNotify() async {
    await database.customStatement(
      "update sales set local_status = 'synced', sync_status = 0",
    );
    await database.customStatement(
      "update purchases set local_status = 'synced', sync_status = 0",
    );
    container
        .read(productiveSyncStatusRevisionProvider.notifier)
        .markLocalStateChanged();
  }

  Future<void> _seedScope(String businessId, String branchId) async {
    await database.customStatement(
      'insert or ignore into businesses (id, name) values (?, ?)',
      [businessId, businessId],
    );
    await database.customStatement(
      'insert or ignore into branches (id, business_id, name) values (?, ?, ?)',
      [branchId, businessId, branchId],
    );
    await database.customStatement(
      'insert or ignore into profiles (id, business_id) values (?, ?)',
      ['profile-a', businessId],
    );
    await database.customStatement(
      '''
      insert or ignore into products (
        id, business_id, name, sale_price
      ) values (?, ?, ?, 1000)
      ''',
      ['product-$businessId', businessId, 'Product $businessId'],
    );
    await database.customStatement(
      '''
      insert or ignore into local_product_stock_balances (
        id, business_id, branch_id, product_id,
        quantity_on_hand, quantity_reserved, quantity_available, average_cost
      ) values (?, ?, ?, ?, 10, 0, 10, 500)
      ''',
      [
        'balance-$branchId',
        businessId,
        branchId,
        'product-$businessId',
      ],
    );
  }

  Future<void> close() async {
    subscription.close();
    container.dispose();
    await database.close();
  }
}
