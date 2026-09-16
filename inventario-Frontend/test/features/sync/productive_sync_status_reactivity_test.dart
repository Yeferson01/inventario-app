import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/database/database_provider.dart';
import 'package:inventario_frontend/core/providers/connectivity_provider.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_models.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_provider.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/purchase_local_dao.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_models.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_provider.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status_provider.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status_revision_provider.dart';

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
        return const {
          'dirty_cash_register_count': 0,
          'dirty_cash_session_count': 0,
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
                unitCost: 500,
              ),
            ],
          ),
        );
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
