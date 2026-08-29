import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_transfer_models.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_transfer_service.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/inventory_movement_local_dao.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/product_stock_balance_local_dao.dart';
import 'package:inventario_frontend/features/inventory/data/models/product_stock_balance_models.dart';
import 'package:inventario_frontend/features/inventory/presentation/widgets/inventory_transfer_dialog.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';

void main() {
  test(
    'single-flight server result projects both ledger legs and balances without outbox',
    () async {
      final database = AppDatabase.executor(NativeDatabase.memory());
      addTearDown(database.close);
      await database.into(database.businesses).insert(
            BusinessesCompanion.insert(
              id: 'business-1',
              name: 'Cronos Business',
            ),
          );
      await database.into(database.products).insert(
            ProductsCompanion.insert(
              id: 'product-1',
              businessId: const Value('business-1'),
              name: 'Arroz',
              salePrice: 25,
            ),
          );

      final balanceDao = ProductStockBalanceLocalDao(database);
      final sourceStockUpdated = Completer<void>();
      final sourceStockEmissions = <int>[];
      final stockSubscription = balanceDao
          .watchProductsWithLocalStock(
        businessId: 'business-1',
        branchId: 'branch-origin',
        limit: null,
      )
          .listen((rows) {
        final stock = (rows.single['quantity_on_hand'] as num).toInt();
        sourceStockEmissions.add(stock);
        if (stock == 8 && !sourceStockUpdated.isCompleted) {
          sourceStockUpdated.complete();
        }
      });
      addTearDown(stockSubscription.cancel);

      final remote = Completer<InventoryTransferResult>();
      var remoteCalls = 0;
      final service = InventoryTransferService(
        database: database,
        executeRemote: (input) {
          remoteCalls += 1;
          return remote.future;
        },
        movementDao: InventoryMovementLocalDao(database),
        balanceDao: balanceDao,
      );
      const input = CreateInventoryTransferInput(
        businessId: 'business-1',
        fromBranchId: 'branch-origin',
        toBranchId: 'branch-destination',
        productId: 'product-1',
        quantity: 2,
        transferId: 'transfer-1',
        transferItemId: 'transfer-item-1',
        idempotencyKey: 'inventory-transfer:transfer-1',
      );

      final first = service.transfer(input);
      final second = service.transfer(input);
      expect(identical(first, second), isTrue);
      expect(remoteCalls, 1);

      remote.complete(_result());
      await Future.wait([first, second]);
      await sourceStockUpdated.future.timeout(const Duration(seconds: 2));
      expect(sourceStockEmissions, containsAllInOrder([0, 8]));

      final movements = await database
          .customSelect(
            'select * from local_inventory_movements order by branch_id',
          )
          .get();
      expect(movements, hasLength(2));
      expect(
        movements.map((row) => row.read<int>('quantity_change')).toSet(),
        {-2, 2},
      );
      expect(
        movements.every(
          (row) =>
              row.read<String>('movement_type') == 'transfer' &&
              row.read<String>('source_type') == 'transfer' &&
              row.read<String>('source_id') == 'transfer-1' &&
              row.read<int>('sync_status') == 1 &&
              row.read<String>('local_status') == 'synced',
        ),
        isTrue,
      );

      final balances = await database.customSelect(
        '''
        select branch_id, quantity_on_hand, quantity_available, average_cost
        from local_product_stock_balances
        order by branch_id
        ''',
      ).get();
      expect(balances, hasLength(2));
      expect(
        balances.map((row) => row.read<int>('quantity_on_hand')).toList(),
        [2, 8],
      );
      expect(
        balances.every((row) => row.read<double>('average_cost') == 12.5),
        isTrue,
      );
      expect(
        (await database.customSelect('select * from local_sync_batches').get()),
        isEmpty,
      );
      expect(
        (await database
            .customSelect('select * from local_sync_mutations')
            .get()),
        isEmpty,
      );
    },
  );

  testWidgets(
    'form excludes unauthorized destinations and prevents a double submit',
    (tester) async {
      final completer = Completer<InventoryTransferResult>();
      final inputs = <CreateInventoryTransferInput>[];
      final source = _context(
        branchId: 'branch-origin',
        branchName: 'Principal',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryTransferDialog(
              businessId: 'business-1',
              productId: 'product-1',
              productName: 'Arroz',
              availableQuantity: 8,
              sourceContext: source,
              destinationContexts: [
                source,
                _context(
                  branchId: 'branch-destination',
                  branchName: 'VendeMás',
                ),
                _context(
                  branchId: 'branch-no-permission',
                  branchName: 'Sin permiso',
                  permissions: const ['inventory.read'],
                ),
                _context(
                  businessId: 'business-2',
                  branchId: 'branch-foreign',
                  branchName: 'Sucursal ajena',
                ),
              ],
              onSubmit: (input) {
                inputs.add(input);
                return completer.future;
              },
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const Key('transfer-destination-selector')),
      );
      await tester.pumpAndSettle();
      expect(find.text('VendeMás'), findsOneWidget);
      expect(find.text('Sin permiso'), findsNothing);
      expect(find.text('Sucursal ajena'), findsNothing);
      expect(find.text('Principal'), findsOneWidget);
      expect(find.text('branch-destination'), findsNothing);

      await tester.tap(find.text('VendeMás'));
      await tester.enterText(
        find.byKey(const Key('transfer-quantity-field')),
        '2',
      );
      await tester.tap(find.byKey(const Key('confirm-inventory-transfer')));
      await tester.pump();

      expect(inputs, hasLength(1));
      expect(inputs.single.fromBranchId, 'branch-origin');
      expect(inputs.single.toBranchId, 'branch-destination');
      expect(inputs.single.quantity, 2);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('confirm-inventory-transfer')),
            )
            .onPressed,
        isNull,
      );

      completer.complete(_result());
      await tester.pumpAndSettle();
      expect(inputs, hasLength(1));
      expect(find.byType(InventoryTransferDialog), findsNothing);
    },
  );
}

InventoryTransferResult _result() {
  final occurredAt = DateTime.utc(2026, 8, 29, 12);
  return InventoryTransferResult(
    transferId: 'transfer-1',
    transferItemId: 'transfer-item-1',
    businessId: 'business-1',
    fromBranchId: 'branch-origin',
    toBranchId: 'branch-destination',
    productId: 'product-1',
    quantity: 2,
    unitCostSnapshot: 12.5,
    idempotentReplay: false,
    sourceMovement: InventoryTransferMovementProjection(
      id: 'movement-source',
      businessId: 'business-1',
      branchId: 'branch-origin',
      productId: 'product-1',
      quantityChange: -2,
      unitCost: 12.5,
      sourceId: 'transfer-1',
      idempotencyKey: 'transfer:transfer-1:item:transfer-item-1:out',
      occurredAt: occurredAt,
      metadata: const {'direction': 'out'},
    ),
    destinationMovement: InventoryTransferMovementProjection(
      id: 'movement-destination',
      businessId: 'business-1',
      branchId: 'branch-destination',
      productId: 'product-1',
      quantityChange: 2,
      unitCost: 12.5,
      sourceId: 'transfer-1',
      idempotencyKey: 'transfer:transfer-1:item:transfer-item-1:in',
      occurredAt: occurredAt,
      metadata: const {'direction': 'in'},
    ),
    sourceBalance: RemoteProductStockBalance(
      remoteBalanceId: 'balance-source',
      businessId: 'business-1',
      branchId: 'branch-origin',
      productId: 'product-1',
      quantityOnHand: 8,
      quantityReserved: 0,
      quantityAvailable: 8,
      averageCost: 12.5,
      lastMovementAt: occurredAt,
      remoteUpdatedAt: occurredAt,
    ),
    destinationBalance: RemoteProductStockBalance(
      remoteBalanceId: 'balance-destination',
      businessId: 'business-1',
      branchId: 'branch-destination',
      productId: 'product-1',
      quantityOnHand: 2,
      quantityReserved: 0,
      quantityAvailable: 2,
      averageCost: 12.5,
      lastMovementAt: occurredAt,
      remoteUpdatedAt: occurredAt,
    ),
  );
}

AuthorizedOperationalContext _context({
  String profileId = 'profile-1',
  String businessId = 'business-1',
  required String branchId,
  required String branchName,
  List<String> permissions = const ['inventory.read', 'inventory.transfer'],
}) {
  return AuthorizedOperationalContext(
    profileId: profileId,
    businessId: businessId,
    businessName: 'Cronos Business',
    businessStatus: 'active',
    businessUpdatedAt: DateTime.utc(2026, 8, 29),
    branchId: branchId,
    branchName: branchName,
    branchStatus: 'active',
    branchUpdatedAt: DateTime.utc(2026, 8, 29),
    membershipIds: const ['membership-1'],
    membershipsUpdatedAt: DateTime.utc(2026, 8, 29),
    effectiveRoles: const [],
    effectivePermissions: permissions,
  );
}
