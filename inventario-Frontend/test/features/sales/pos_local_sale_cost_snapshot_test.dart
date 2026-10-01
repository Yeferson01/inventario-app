import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_models.dart';
import 'package:inventario_frontend/core/models/product_sale_mode.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_creation_service.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_from_master_sync_service.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_service.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/purchase_local_dao.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_models.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_service.dart';
import 'package:inventario_frontend/features/sales/application/pos_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/sync/application/local_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';

void main() {
  test('price-only edit preserves old sale, COGS and retry payload', () async {
    final fixture = await _SaleFixture.create(averageCost: 600);
    addTearDown(fixture.close);
    await fixture.database.customStatement(
        'update products set sale_price = 1000, sale_price_cents = 100000 where id = ?',
        const [_productId]);
    final saleA = await fixture.sell(quantity: 1);
    final before = await fixture.database.customSelect(
        'select average_cost, cost_basis_cents from local_product_stock_balances where id = ?',
        variables: const [Variable<String>(_balanceId)]).getSingle();
    final priceUpdate = await InventoryProductFromMasterSyncService(
      database: fixture.database,
      productCreationService: InventoryProductCreationService(fixture.database),
      outboxService:
          LocalSyncOutboxService(LocalSyncOutboxDao(fixture.database)),
    ).updateSaleConfigurationAndQueueSync(
      businessId: _businessId,
      branchId: _branchId,
      profileId: _profileId,
      productId: _productId,
      deviceInstallationId: 'installation-1',
      saleMode: ProductSaleMode.unit,
      salePriceCents: 120000,
    );
    expect(priceUpdate?.changed, isTrue);
    final productCost = await fixture.database.customSelect(
        'select purchase_price from products where id = ?',
        variables: const [Variable<String>(_productId)]).getSingle();
    expect(productCost.read<double>('purchase_price'), 9999);
    final after = await fixture.database.customSelect(
        'select average_cost, cost_basis_cents from local_product_stock_balances where id = ?',
        variables: const [Variable<String>(_balanceId)]).getSingle();
    expect(after.data, before.data);
    final saleB = await fixture.sell(quantity: 1);
    Future<Map<String, dynamic>> item(String id) async =>
        (await fixture.database.customSelect(
          'select unit_price, subtotal, unit_cost_snapshot from sale_items where id = ?',
          variables: [Variable<String>(id)],
        ).getSingle())
            .data;
    expect((await item(saleA.lines.single.itemId))['unit_price'], 1000);
    expect((await item(saleA.lines.single.itemId))['subtotal'], 1000);
    expect((await item(saleB.lines.single.itemId))['unit_price'], 1200);
    expect((await item(saleA.lines.single.itemId))['unit_cost_snapshot'], 600);
    await PosSyncOutboxService(
      dao: PosLocalSaleDao(fixture.database),
      outboxService:
          LocalSyncOutboxService(LocalSyncOutboxDao(fixture.database)),
    ).enqueuePendingPosSales(
      businessId: _businessId,
      branchId: _branchId,
      profileId: _profileId,
      deviceInstallationId: 'installation-1',
    );
    final oldPayload = (await fixture.database.customSelect(
      "select payload_json from local_sync_mutations where entity_table='sale_items' and entity_id = ?",
      variables: [Variable<String>(saleA.lines.single.itemId)],
    ).getSingle())
        .read<String>('payload_json');
    expect(jsonDecode(oldPayload)['unit_price'], 1000);
  });

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
      CreatePurchaseLocalInput(
        businessId: _businessId,
        branchId: _branchId,
        profileId: _profileId,
        items: [
          PurchaseLocalItemInput(
            productId: _productId,
            quantity: 8,
            unitCostCents: BigInt.from(700000),
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

  test('FC-03 outbox preserves known, zero, and unknown cost snapshots',
      () async {
    for (final expectedCost in <double?>[6000, 0, null]) {
      final fixture = await _SaleFixture.create(averageCost: expectedCost);

      try {
        await fixture.sell(quantity: 1);
        final result = await PosSyncOutboxService(
          dao: PosLocalSaleDao(fixture.database),
          outboxService: LocalSyncOutboxService(
            LocalSyncOutboxDao(fixture.database),
          ),
        ).enqueuePendingPosSales(
          businessId: _businessId,
          branchId: _branchId,
          profileId: _profileId,
          deviceInstallationId: 'installation-1',
        );

        expect(result.salesEnqueued, 1);
        final mutation = await fixture.database.customSelect(
          '''
          select payload_json
          from local_sync_mutations
          where entity_table = 'sale_items'
          ''',
        ).getSingle();
        final payload = jsonDecode(mutation.read<String>('payload_json'))
            as Map<String, dynamic>;

        expect(payload, contains('unit_cost_snapshot'));
        expect(payload['unit_cost_snapshot'], expectedCost);
      } finally {
        await fixture.close();
      }
    }
  });

  test('payment event time is durable across midnight and outbox retry',
      () async {
    final fixture = await _SaleFixture.create(averageCost: 6000);
    addTearDown(fixture.close);
    final sale = await fixture.sell(quantity: 1);
    final event = DateTime.utc(2026, 11, 1, 4, 58); // Oct 31, 23:58 Bogotá.
    await fixture.database.customStatement(
      'update sale_payments set created_at = ? where sale_id = ?',
      [event.millisecondsSinceEpoch ~/ 1000, sale.saleId],
    );
    final dao = PosLocalSaleDao(fixture.database);
    final outbox = PosSyncOutboxService(
      dao: dao,
      outboxService: LocalSyncOutboxService(
        LocalSyncOutboxDao(fixture.database),
      ),
    );
    Future<Map<String, dynamic>> paymentPayload() async {
      final row = await fixture.database
          .customSelect(
            "select payload_json from local_sync_mutations where entity_table = 'sale_payments'",
          )
          .getSingle();
      return jsonDecode(row.read<String>('payload_json'))
          as Map<String, dynamic>;
    }

    await outbox.enqueuePendingPosSales(
      businessId: _businessId,
      branchId: _branchId,
      profileId: _profileId,
      deviceInstallationId: 'installation-1',
    );
    final first = await paymentPayload();
    expect(first['payment_event_time_contract'], 'v1');
    expect(first['paid_at'], event.toIso8601String());
    expect(first['created_at'], first['paid_at']);

    await outbox.enqueuePendingPosSales(
      businessId: _businessId,
      branchId: _branchId,
      profileId: _profileId,
      deviceInstallationId: 'installation-1',
    );
    expect(await paymentPayload(), first);
    final count = await fixture.database
        .customSelect(
          "select count(*) as count from local_sync_mutations where entity_table = 'sale_payments'",
        )
        .getSingle();
    expect(count.read<int>('count'), 1);
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
