import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_models.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_service.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/purchase_local_dao.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_models.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_service.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';

void main() {
  test('FC-01/02 captures known cost and preserves it after cost changes',
      () async {
    final fixture = await _SaleFixture.create(averageCost: 6000);
    addTearDown(fixture.close);

    final result = await fixture.sell(quantity: 2);
    final persisted = await fixture.costsFor(result);

    expect(persisted.itemCost, 6000);
    expect(persisted.movementCost, 6000);
    expect(result.lines.single.quantity * persisted.itemCost!, 12000);

    await PurchaseLocalService(
      dao: PurchaseLocalDao(fixture.database),
    ).createLocalPurchase(
      const CreatePurchaseLocalInput(
        businessId: _businessId,
        branchId: _branchId,
        profileId: _profileId,
        items: [
          PurchaseLocalItemInput(
            productId: _productId,
            quantity: 8,
            unitCost: 7000,
          ),
        ],
      ),
    );
    final changedBalance = await fixture.database.customSelect(
      'select average_cost from local_product_stock_balances where id = ?',
      variables: const [Variable<String>(_balanceId)],
    ).getSingle();
    expect(changedBalance.read<double>('average_cost'), 6500);

    final historical = await fixture.costsFor(result);
    expect(historical.itemCost, 6000);
    expect(historical.movementCost, 6000);
  });

  test('FC-04A preserves unknown cost as null and allows the sale', () async {
    final fixture = await _SaleFixture.create(averageCost: null);
    addTearDown(fixture.close);

    final result = await fixture.sell(quantity: 1);
    final persisted = await fixture.costsFor(result);

    expect(persisted.itemCost, null);
    expect(persisted.movementCost, null);
  });

  test('FC-04B preserves an explicitly recorded zero cost', () async {
    final fixture = await _SaleFixture.create(averageCost: 0);
    addTearDown(fixture.close);

    final result = await fixture.sell(quantity: 1);
    final persisted = await fixture.costsFor(result);

    expect(persisted.itemCost, 0);
    expect(persisted.movementCost, 0);
  });

  test('missing required branch balance remains rejected', () async {
    final fixture = await _SaleFixture.create(
      averageCost: 6000,
      includeBalance: false,
    );
    addTearDown(fixture.close);

    await expectLater(
      fixture.sell(quantity: 1),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('No hay saldo local'),
        ),
      ),
    );
  });
}

class _SaleFixture {
  _SaleFixture(this.database)
      : service = PosLocalSaleService(dao: PosLocalSaleDao(database));

  static Future<_SaleFixture> create({
    required double? averageCost,
    bool includeBalance = true,
  }) async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    final fixture = _SaleFixture(database);
    await database.customStatement(
      'insert into businesses (id, name) values (?, ?)',
      const [_businessId, 'Business'],
    );
    await database.customStatement(
      'insert into profiles (id, business_id) values (?, ?)',
      const [_profileId, _businessId],
    );
    await database.customStatement(
      'insert into branches (id, business_id, name) values (?, ?, ?)',
      const [_branchId, _businessId, 'Branch'],
    );
    await database.customStatement(
      'insert into branches (id, business_id, name) values (?, ?, ?)',
      const [_otherBranchId, _businessId, 'Other branch'],
    );
    await database.customStatement(
      '''
      insert into products (id, business_id, name, purchase_price, sale_price)
      values (?, ?, ?, ?, ?)
      ''',
      const [_productId, _businessId, 'Product', 9999, 8000],
    );
    if (includeBalance) {
      await database.customStatement(
        '''
        insert into local_product_stock_balances (
          id, business_id, branch_id, product_id, quantity_on_hand,
          quantity_available, average_cost
        ) values (?, ?, ?, ?, ?, ?, ?)
        ''',
        [_balanceId, _businessId, _branchId, _productId, 10, 10, averageCost],
      );
      await database.customStatement(
        '''
        insert into local_product_stock_balances (
          id, business_id, branch_id, product_id, quantity_on_hand,
          quantity_available, average_cost
        ) values (?, ?, ?, ?, ?, ?, ?)
        ''',
        const [
          'other-balance',
          _businessId,
          _otherBranchId,
          _productId,
          10,
          10,
          1234,
        ],
      );
    }
    return fixture;
  }

  final AppDatabase database;
  final PosLocalSaleService service;

  Future<PosLocalSaleResult> sell({required int quantity}) {
    return service.createLocalSale(
      CreatePosLocalSaleInput(
        businessId: _businessId,
        branchId: _branchId,
        profileId: _profileId,
        cashRegisterId: 'cash-register',
        cashSessionId: 'cash-session',
        items: [
          PosLocalSaleItemInput(productId: _productId, quantity: quantity),
        ],
      ),
    );
  }

  Future<_PersistedCosts> costsFor(PosLocalSaleResult result) async {
    final item = await database.customSelect(
      'select unit_cost_snapshot from sale_items where id = ?',
      variables: [Variable<String>(result.lines.single.itemId)],
    ).getSingle();
    final movement = await database.customSelect(
      'select unit_cost from local_inventory_movements where id = ?',
      variables: [
        Variable<String>(result.lines.single.inventoryMovementId),
      ],
    ).getSingle();
    return _PersistedCosts(
      itemCost: item.readNullable<double>('unit_cost_snapshot'),
      movementCost: movement.readNullable<double>('unit_cost'),
    );
  }

  Future<void> close() => database.close();
}

class _PersistedCosts {
  const _PersistedCosts({
    required this.itemCost,
    required this.movementCost,
  });

  final double? itemCost;
  final double? movementCost;
}

const _businessId = 'business-1';
const _branchId = 'branch-1';
const _otherBranchId = 'branch-2';
const _profileId = 'profile-1';
const _productId = 'product-1';
const _balanceId = 'balance-1';
