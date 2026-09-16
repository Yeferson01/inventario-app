import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status.dart';

void main() {
  const scope = ProductiveSyncScope(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-a',
  );

  test('PS-01 clean scope is all up to date', () async {
    final status = await _service().load(
      scope: scope,
      isOnline: true,
      isSyncing: false,
    );

    expect(status.allUpToDate, isTrue);
    expect(status.totalPending, 0);
    expect(status.requiresAttention, isFalse);
  });

  test('PS-02 counts dirty sales as business operations', () async {
    final status = await _service(
      sales: const [
        {'id': 'sale-1'},
        {'id': 'sale-2'},
      ],
    ).load(scope: scope, isOnline: true, isSyncing: false);

    expect(status.pendingSales, 2);
    expect(status.allUpToDate, isFalse);
    expect(status.requiresAttention, isFalse);
  });

  test('PS-03 one sale with many mutations remains one pending sale', () async {
    final status = await _service(
      sales: const [
        {'id': 'sale-1'},
      ],
      outboxRows: [
        _posPendingMutation,
        {
          ..._posPendingMutation,
          'entity_table': 'sale_items',
          'entity_id': 'item-1',
        },
        {
          ..._posPendingMutation,
          'entity_table': 'sale_items',
          'entity_id': 'item-2',
        },
        {
          ..._posPendingMutation,
          'entity_table': 'sale_payments',
          'entity_id': 'payment-1',
        },
      ],
    ).load(scope: scope, isOnline: true, isSyncing: false);

    expect(status.pendingSales, 1);
    expect(status.totalPending, 1);
  });

  test('PS-04 counts one dirty purchase', () async {
    final status = await _service(
      purchases: const [
        {'id': 'purchase-1'},
      ],
    ).load(scope: scope, isOnline: true, isSyncing: false);

    expect(status.pendingPurchases, 1);
    expect(status.allUpToDate, isFalse);
  });

  test('PS-05 offline pending remains safe and does not require attention',
      () async {
    final status = await _service(
      sales: const [
        {'id': 'sale-1'},
      ],
    ).load(scope: scope, isOnline: false, isSyncing: false);

    expect(status.connectivity, ProductiveSyncConnectivity.offline);
    expect(status.pendingSales, 1);
    expect(status.requiresAttention, isFalse);
    expect(status.allUpToDate, isFalse);
  });

  test('PS-06 open blocking issue requires attention', () async {
    final status = await _service(
      issues: const [
        {'id': 'issue-1'},
      ],
    ).load(scope: scope, isOnline: true, isSyncing: false);

    expect(status.openIssueCount, 1);
    expect(status.requiresAttention, isTrue);
    expect(status.allUpToDate, isFalse);
  });

  test('PS-07 foreign scope does not contaminate the current scope', () async {
    const records = [
      (businessId: 'business-b', branchId: 'branch-b', id: 'sale-foreign'),
    ];
    final service = ProductiveSyncStatusService(
      pendingSalesLoader: ({required businessId, required branchId}) async {
        return records
            .where(
              (record) =>
                  record.businessId == businessId &&
                  record.branchId == branchId,
            )
            .map((record) => {'id': record.id})
            .toList();
      },
      pendingPurchasesLoader: _emptyOperations,
      cashReadinessLoader: _emptyCash,
      openIssuesLoader: ({
        required profileId,
        required businessId,
        required branchId,
      }) async {
        expect(profileId, scope.profileId);
        expect(businessId, scope.businessId);
        expect(branchId, scope.branchId);
        return const [];
      },
      outboxStatusRowsLoader: _emptyOperations,
      blockedPurchaseDependenciesLoader: _noBlockedDependencies,
    );

    final status = await service.load(
      scope: scope,
      isOnline: true,
      isSyncing: false,
    );

    expect(status.pendingSales, 0);
    expect(status.openIssueCount, 0);
    expect(status.allUpToDate, isTrue);
  });

  test('PS-08 active single flight is exposed as syncing', () async {
    final status = await _service().load(
      scope: scope,
      isOnline: true,
      isSyncing: true,
    );

    expect(status.isSyncing, isTrue);
    expect(status.allUpToDate, isFalse);
  });

  test('product and inventory counts group mutations by logical batch',
      () async {
    final status = await _service(
      outboxRows: const [
        {
          'batch_id': 'catalog-operation-1',
          'domain': 'catalog',
          'batch_status': 'pending',
          'mutation_status': 'pending',
          'entity_table': 'products',
          'entity_id': 'product-1',
        },
        {
          'batch_id': 'catalog-operation-1',
          'domain': 'catalog',
          'batch_status': 'pending',
          'mutation_status': 'pending',
          'entity_table': 'product_barcodes',
          'entity_id': 'barcode-1',
        },
        {
          'batch_id': 'inventory-operation-1',
          'domain': 'inventory',
          'batch_status': 'error',
          'mutation_status': 'pending',
          'entity_table': 'inventory_movements',
          'entity_id': 'movement-1',
        },
      ],
    ).load(scope: scope, isOnline: true, isSyncing: false);

    expect(status.pendingProductOperations, 1);
    expect(status.pendingInventoryOperations, 1);
    expect(status.totalPending, 2);
  });

  test('partial outbox and blocked dependency require attention', () async {
    final status = await _service(
      outboxRows: const [
        {
          'batch_id': 'partial-1',
          'domain': 'catalog',
          'batch_status': 'partial',
          'mutation_status': 'conflict',
          'entity_table': 'products',
          'entity_id': 'product-1',
        },
      ],
      blockedDependencies: 1,
    ).load(scope: scope, isOnline: true, isSyncing: false);

    expect(status.attentionOperationCount, 2);
    expect(status.requiresAttention, isTrue);
  });
}

const _posPendingMutation = {
  'batch_id': 'pos-operation-1',
  'domain': 'pos',
  'batch_status': 'pending',
  'mutation_status': 'pending',
  'entity_table': 'sales',
  'entity_id': 'sale-1',
};

ProductiveSyncStatusService _service({
  List<Map<String, dynamic>> sales = const [],
  List<Map<String, dynamic>> purchases = const [],
  Map<String, dynamic> cash = const {},
  List<Map<String, dynamic>> issues = const [],
  List<Map<String, dynamic>> outboxRows = const [],
  int blockedDependencies = 0,
}) {
  return ProductiveSyncStatusService(
    pendingSalesLoader: ({required businessId, required branchId}) async {
      return sales;
    },
    pendingPurchasesLoader: ({required businessId, required branchId}) async {
      return purchases;
    },
    cashReadinessLoader: ({required businessId, required branchId}) async {
      return cash;
    },
    openIssuesLoader: ({
      required profileId,
      required businessId,
      required branchId,
    }) async {
      return issues;
    },
    outboxStatusRowsLoader: ({
      required businessId,
      required branchId,
    }) async {
      return outboxRows;
    },
    blockedPurchaseDependenciesLoader: ({
      required businessId,
      required branchId,
    }) async {
      return blockedDependencies;
    },
  );
}

Future<List<Map<String, dynamic>>> _emptyOperations({
  required String businessId,
  required String branchId,
}) async {
  return const [];
}

Future<Map<String, dynamic>> _emptyCash({
  required String businessId,
  required String branchId,
}) async {
  return const {};
}

Future<int> _noBlockedDependencies({
  required String businessId,
  required String branchId,
}) async {
  return 0;
}
