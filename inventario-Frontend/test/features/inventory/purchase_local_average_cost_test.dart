import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/product_stock_balance_local_dao.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/purchase_local_dao.dart';

void main() {
  const businessId = 'business-1';
  const branchA = 'branch-a';
  const branchB = 'branch-b';
  const productId = 'product-1';

  late AppDatabase database;
  late PurchaseLocalDao purchaseDao;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    purchaseDao = PurchaseLocalDao(database);

    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(id: businessId, name: 'Negocio'),
        );
    await database.into(database.branches).insert(
          BranchesCompanion.insert(
            id: branchA,
            businessId: businessId,
            name: 'Sucursal A',
          ),
        );
    await database.into(database.branches).insert(
          BranchesCompanion.insert(
            id: branchB,
            businessId: businessId,
            name: 'Sucursal B',
          ),
        );
    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: productId,
            businessId: const Value(businessId),
            name: 'Producto',
            salePrice: 10,
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  test('new balance adopts the incoming purchase unit cost', () async {
    await _insertPurchase(
      purchaseDao,
      operationId: 'new-balance',
      businessId: businessId,
      branchId: branchA,
      productId: productId,
      quantity: 5,
      unitCost: 20,
    );

    final balance = await _balance(database, branchA, productId);
    expect(balance['quantity_on_hand'], 5);
    expect(balance['quantity_available'], 5);
    expect(balance['average_cost'], 20.0);
  });

  test('existing balance uses the backend weighted-average formula', () async {
    await _insertBalance(
      database,
      id: 'balance-a',
      businessId: businessId,
      branchId: branchA,
      productId: productId,
      quantity: 10,
      averageCost: 2,
    );

    await _insertPurchase(
      purchaseDao,
      operationId: 'weighted',
      businessId: businessId,
      branchId: branchA,
      productId: productId,
      quantity: 5,
      unitCost: 4,
    );

    final balance = await _balance(database, branchA, productId);
    expect(balance['quantity_on_hand'], 15);
    expect(balance['quantity_available'], 15);
    expect(balance['average_cost'], 2.67);
  });

  test('zero stock replaces historical average and preserves branch scope',
      () async {
    await _insertBalance(
      database,
      id: 'balance-a',
      businessId: businessId,
      branchId: branchA,
      productId: productId,
      quantity: 0,
      averageCost: 12.5,
    );
    await _insertBalance(
      database,
      id: 'balance-b',
      businessId: businessId,
      branchId: branchB,
      productId: productId,
      quantity: 7,
      averageCost: 9,
    );

    await _insertPurchase(
      purchaseDao,
      operationId: 'zero-stock',
      businessId: businessId,
      branchId: branchA,
      productId: productId,
      quantity: 5,
      unitCost: 20,
    );

    final balanceA = await _balance(database, branchA, productId);
    final balanceB = await _balance(database, branchB, productId);
    expect(balanceA['quantity_on_hand'], 5);
    expect(balanceA['average_cost'], 20.0);
    expect(balanceB['quantity_on_hand'], 7);
    expect(balanceB['average_cost'], 9.0);
  });

  test('positive movement without unit cost preserves the current average',
      () async {
    await _insertBalance(
      database,
      id: 'balance-a',
      businessId: businessId,
      branchId: branchA,
      productId: productId,
      quantity: 10,
      averageCost: 3.25,
    );

    await _insertPurchase(
      purchaseDao,
      operationId: 'without-cost',
      businessId: businessId,
      branchId: branchA,
      productId: productId,
      quantity: 2,
      unitCost: 8,
      movementUnitCost: null,
    );

    final balance = await _balance(database, branchA, productId);
    expect(balance['quantity_on_hand'], 12);
    expect(balance['average_cost'], 3.25);
  });

  test('retry of the same purchase cannot apply quantity or cost twice',
      () async {
    await _insertBalance(
      database,
      id: 'balance-a',
      businessId: businessId,
      branchId: branchA,
      productId: productId,
      quantity: 10,
      averageCost: 2,
    );

    Future<void> operation() => _insertPurchase(
          purchaseDao,
          operationId: 'same-operation',
          businessId: businessId,
          branchId: branchA,
          productId: productId,
          quantity: 5,
          unitCost: 4,
        );

    await operation();
    await expectLater(operation(), throwsA(anything));

    final balance = await _balance(database, branchA, productId);
    final movements = await database
        .customSelect(
          'select count(*) as total from local_inventory_movements',
        )
        .getSingle();
    expect(balance['quantity_on_hand'], 15);
    expect(balance['average_cost'], 2.67);
    expect(movements.read<int>('total'), 1);
  });

  test('stock stream emits when only average_cost changes', () async {
    await _insertBalance(
      database,
      id: 'balance-a',
      businessId: businessId,
      branchId: branchA,
      productId: productId,
      quantity: 10,
      averageCost: 2,
    );
    final stockDao = ProductStockBalanceLocalDao(database);
    final iterator = StreamIterator(
      stockDao.watchProductsWithLocalStock(
        businessId: businessId,
        branchId: branchA,
        limit: null,
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.single['stock_average_cost'], 2.0);

    await (database.update(database.localProductStockBalances)
          ..where((row) => row.id.equals('balance-a')))
        .write(
      const LocalProductStockBalancesCompanion(
        averageCost: Value(4.5),
      ),
    );

    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.single['stock_average_cost'], 4.5);
    await iterator.cancel();
  });
}

Future<void> _insertBalance(
  AppDatabase database, {
  required String id,
  required String businessId,
  required String branchId,
  required String productId,
  required int quantity,
  required double averageCost,
}) {
  return database.into(database.localProductStockBalances).insert(
        LocalProductStockBalancesCompanion.insert(
          id: id,
          businessId: businessId,
          branchId: branchId,
          productId: productId,
          quantityOnHand: Value(quantity),
          quantityAvailable: Value(quantity),
          averageCost: Value(averageCost),
        ),
      );
}

Future<Map<String, dynamic>> _balance(
  AppDatabase database,
  String branchId,
  String productId,
) async {
  final row = await database.customSelect(
    '''
    select quantity_on_hand, quantity_available, average_cost
    from local_product_stock_balances
    where branch_id = ? and product_id = ?
    ''',
    variables: [Variable<String>(branchId), Variable<String>(productId)],
  ).getSingle();
  return row.data;
}

Future<void> _insertPurchase(
  PurchaseLocalDao dao, {
  required String operationId,
  required String businessId,
  required String branchId,
  required String productId,
  required int quantity,
  required double unitCost,
  Object? movementUnitCost = _movementCostNotProvided,
}) {
  final now = DateTime.utc(2026, 9, 4, 12);
  final purchaseId = 'purchase-$operationId';
  final itemId = 'item-$operationId';
  final movementId = 'movement-$operationId';
  final effectiveMovementCost =
      identical(movementUnitCost, _movementCostNotProvided)
          ? unitCost
          : movementUnitCost;

  return dao.insertPurchaseWithLocalInventoryImpact(
    purchase: {
      'id': purchaseId,
      'business_id': businessId,
      'branch_id': branchId,
      'supplier_id': null,
      'user_id': null,
      'total': quantity * unitCost,
      'status': 'completed',
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'last_synced_at': null,
      'invoice_photo_url': null,
      'processing_status': 'completed',
      'supplier_name': null,
      'idempotency_key': 'purchase-key-$operationId',
      'local_status': 'dirty',
      'metadata': const <String, dynamic>{},
      'version': 1,
      'sync_status': SyncStatus.pendingInsert.index,
    },
    items: [
      {
        'id': itemId,
        'purchase_id': purchaseId,
        'business_id': businessId,
        'branch_id': branchId,
        'product_id': productId,
        'quantity': quantity,
        'unit_cost': unitCost,
        'subtotal': quantity * unitCost,
        'idempotency_key': 'item-key-$operationId',
        'local_status': 'dirty',
        'metadata': const <String, dynamic>{},
        'version': 1,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
        'last_synced_at': null,
        'sync_status': SyncStatus.pendingInsert.index,
      },
    ],
    inventoryMovements: [
      {
        'id': movementId,
        'business_id': businessId,
        'branch_id': branchId,
        'product_id': productId,
        'movement_type': 'purchase',
        'quantity_change': quantity,
        'unit_cost': effectiveMovementCost,
        'source_type': 'purchase',
        'source_id': purchaseId,
        'reference_type': 'purchase_item',
        'reference_id': itemId,
        'notes': 'test purchase',
        'idempotency_key': 'movement-key-$operationId',
        'sync_status': SyncStatus.pendingInsert.index,
        'local_status': 'dirty',
        'version': 1,
        'occurred_at': now,
        'metadata': const <String, dynamic>{},
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
        'last_synced_at': null,
      },
    ],
  );
}

const _movementCostNotProvided = Object();
