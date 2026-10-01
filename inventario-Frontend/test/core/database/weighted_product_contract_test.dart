import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/models/product_sale_mode.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/inventory_adjustment_local_dao.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/product_stock_balance_local_dao.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/purchase_local_dao.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_adjustment_models.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/cash_pos_reconciliation_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/product_operational_reconciliation_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/cash_pos_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/inventory_balance_reconciliation_models.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_bootstrap_models.dart';
import 'package:inventario_frontend/features/sync/data/models/product_operational_snapshot_models.dart';

void main() {
  test('real schema 17 rows migrate to 18 without reinterpreting quantities',
      () async {
    final source = AppDatabase.executor(NativeDatabase.memory());
    await source.customSelect('select name from sqlite_master limit 1').get();
    const newColumns = <String, List<String>>{
      'products': ['sale_mode', 'sale_price_cents'],
      'sale_items': [
        'sale_mode_snapshot',
        'price_basis_quantity_snapshot',
        'price_cents_snapshot',
        'line_total_cents',
        'cogs_cents',
      ],
      'purchase_items': ['sale_mode_snapshot', 'cost_basis_quantity_snapshot'],
      'local_product_stock_balances': [
        'cost_basis_cents',
        'remote_cost_basis_cents',
      ],
      'local_inventory_movements': ['cost_effect_cents'],
    };
    for (final entry in newColumns.entries) {
      for (final column in entry.value) {
        await source
            .customStatement('alter table ${entry.key} drop column $column');
      }
    }
    final schema = await source.customSelect('''
      select sql from sqlite_master
      where sql is not null and name not like 'sqlite_%'
      order by case type when 'table' then 0 when 'index' then 1
                         when 'trigger' then 2 else 3 end, rowid
    ''').get();
    final statements = schema.map((row) => row.read<String>('sql')).toList();
    await source.close();

    final database = AppDatabase.executor(NativeDatabase.memory(setup: (raw) {
      for (final statement in statements) {
        raw.execute(statement);
      }
      raw.execute('''insert into products
        (id, name, sale_price, stock_quantity, unit)
        values ('legacy-product', 'Legacy kg label', 12.5, 7, 'kg')''');
      raw.execute('''insert into sale_items
        (id, quantity, unit_price, subtotal)
        values ('legacy-sale-item', 5, 12.5, 62.5)''');
      raw.execute('''insert into purchase_items
        (id, quantity, unit_cost, subtotal)
        values ('legacy-purchase-item', 9, 4.5, 40.5)''');
      raw.execute('''insert into local_product_stock_balances
        (id, business_id, branch_id, product_id, quantity_on_hand)
        values ('legacy-balance', 'business-a', 'branch-a', 'legacy-product', 13)''');
      raw.execute('''insert into local_inventory_movements
        (id, business_id, product_id, movement_type, quantity_change,
         idempotency_key, occurred_at)
        values ('legacy-movement', 'business-a', 'legacy-product', 'sale',
                -3, 'legacy-movement-key', 1758814200)''');
      raw.execute('pragma user_version = 17');
    }));
    addTearDown(database.close);

    final product = await database.customSelect('''
      select stock_quantity, unit, sale_mode, sale_price_cents
      from products where id = 'legacy-product'
    ''').getSingle();
    expect(database.schemaVersion, 18);
    expect(product.read<int>('stock_quantity'), 7);
    expect(product.read<String>('unit'), 'kg');
    expect(product.read<String>('sale_mode'), 'unit');
    expect(product.readNullable<int>('sale_price_cents'), isNull);

    final sale = await database.customSelect('''
      select quantity, sale_mode_snapshot, price_basis_quantity_snapshot,
             price_cents_snapshot, line_total_cents, cogs_cents
      from sale_items where id = 'legacy-sale-item'
    ''').getSingle();
    expect(sale.read<int>('quantity'), 5);
    expect(sale.read<String>('sale_mode_snapshot'), 'unit');
    expect(sale.read<int>('price_basis_quantity_snapshot'), 1);
    expect(sale.readNullable<int>('price_cents_snapshot'), isNull);
    expect(sale.readNullable<int>('line_total_cents'), isNull);
    expect(sale.readNullable<int>('cogs_cents'), isNull);

    final purchase = await database.customSelect('''
      select quantity, sale_mode_snapshot, cost_basis_quantity_snapshot
      from purchase_items where id = 'legacy-purchase-item'
    ''').getSingle();
    expect(purchase.read<int>('quantity'), 9);
    expect(purchase.read<String>('sale_mode_snapshot'), 'unit');
    expect(purchase.read<int>('cost_basis_quantity_snapshot'), 1);

    final balance = await database.customSelect('''
      select quantity_on_hand, cost_basis_cents, remote_cost_basis_cents
      from local_product_stock_balances where id = 'legacy-balance'
    ''').getSingle();
    expect(balance.read<int>('quantity_on_hand'), 13);
    expect(balance.readNullable<int>('cost_basis_cents'), isNull);
    expect(balance.readNullable<int>('remote_cost_basis_cents'), isNull);

    final movement = await database.customSelect('''
      select quantity_change, cost_effect_cents
      from local_inventory_movements where id = 'legacy-movement'
    ''').getSingle();
    expect(movement.read<int>('quantity_change'), -3);
    expect(movement.readNullable<int>('cost_effect_cents'), isNull);
  });

  test('fresh schema round-trips WEIGHT grams and exact cents', () async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.products).insert(ProductsCompanion.insert(
          id: 'weight-product',
          name: 'Weighted product',
          salePrice: 12000,
          saleMode: const Value('weight'),
          salePriceCents: const Value(1200000),
        ));
    final product = await (database.select(database.products)
          ..where((row) => row.id.equals('weight-product')))
        .getSingle();
    expect(ProductSaleMode.parse(product.saleMode), ProductSaleMode.weight);
    expect(product.salePriceCents, 1200000);
    expect(ProductSaleMode.weight.salePriceBasisQuantity, 500);

    await database.customStatement('''
      insert into sale_items
        (id, product_id, quantity, unit_price, subtotal,
         sale_mode_snapshot, price_basis_quantity_snapshot,
         price_cents_snapshot, line_total_cents, cogs_cents)
      values ('weighted-sale-item', 'weight-product', 735, 12000, 17640,
              'weight', 500, 1200000, 1764000, 500000)
    ''');
    final sale = await database.customSelect('''
      select quantity, sale_mode_snapshot, price_basis_quantity_snapshot,
             price_cents_snapshot, line_total_cents, cogs_cents
      from sale_items where id = 'weighted-sale-item'
    ''').getSingle();
    expect(sale.read<int>('quantity'), 735);
    expect(sale.read<String>('sale_mode_snapshot'), 'weight');
    expect(sale.read<int>('price_basis_quantity_snapshot'), 500);
    expect(sale.read<int>('price_cents_snapshot'), 1200000);
    expect(sale.read<int>('line_total_cents'), 1764000);
    expect(sale.read<int>('cogs_cents'), 500000);

    await database.customStatement('''
      insert into purchase_items
        (id, product_id, quantity, unit_cost, subtotal,
         sale_mode_snapshot, cost_basis_quantity_snapshot,
         unit_cost_cents, subtotal_cents)
      values ('weighted-purchase-item', 'weight-product', 735, 9000, 6615,
              'weight', 1000, 900000, 661500)
    ''');
    final purchase = await database.customSelect('''
      select quantity, sale_mode_snapshot, cost_basis_quantity_snapshot,
             unit_cost_cents, subtotal_cents
      from purchase_items where id = 'weighted-purchase-item'
    ''').getSingle();
    expect(purchase.read<int>('quantity'), 735);
    expect(purchase.read<String>('sale_mode_snapshot'), 'weight');
    expect(purchase.read<int>('cost_basis_quantity_snapshot'), 1000);
    expect(purchase.read<int>('unit_cost_cents'), 900000);
    expect(purchase.read<int>('subtotal_cents'), 661500);

    const largeCost = 2280000000000000;
    await database.customStatement('''
      insert into local_product_stock_balances
        (id, business_id, branch_id, product_id, quantity_on_hand,
         cost_basis_cents, remote_cost_basis_cents)
      values ('weighted-balance', 'business-a', 'branch-a', 'weight-product',
              13000, $largeCost, $largeCost)
    ''');
    final balance = await database.customSelect('''
      select quantity_on_hand, cost_basis_cents, remote_cost_basis_cents
      from local_product_stock_balances where id = 'weighted-balance'
    ''').getSingle();
    expect(balance.read<int>('quantity_on_hand'), 13000);
    expect(balance.read<int>('cost_basis_cents'), largeCost);
    expect(balance.read<int>('remote_cost_basis_cents'), largeCost);

    for (final (id, effect) in [('in', 500), ('out', -200)]) {
      await database.customStatement('''
        insert into local_inventory_movements
          (id, business_id, product_id, movement_type, quantity_change,
           cost_effect_cents, idempotency_key, occurred_at)
        values ('$id', 'business-a', 'weight-product', 'manual_adjustment',
                ${effect > 0 ? 1 : -1}, $effect, '$id-key', 1758814200)
      ''');
    }
    final effects = await database.customSelect('''
      select cost_effect_cents from local_inventory_movements order by id
    ''').get();
    expect(
        effects.map((row) => row.read<int>('cost_effect_cents')), [500, -200]);
    expect(() => ProductSaleMode.parse('volume'), throwsFormatException);
    expect(() => parseNullableExactCents(12.0, 'money'), throwsFormatException);
  });

  test('legacy UNIT operations reject a locally materialized WEIGHT product',
      () async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(id: 'business-a', name: 'Business A'),
        );
    await database.into(database.products).insert(ProductsCompanion.insert(
          id: 'weight-product',
          businessId: const Value('business-a'),
          name: 'Weighted product',
          salePrice: 12000,
          saleMode: const Value('weight'),
        ));

    expect(
      PosLocalSaleDao(database).getRequiredProductSnapshot(
        businessId: 'business-a',
        productId: 'weight-product',
      ),
      throwsStateError,
    );
    expect(
      PurchaseLocalDao(database).getRequiredProductSnapshot(
        businessId: 'business-a',
        productId: 'weight-product',
      ),
      throwsStateError,
    );
    expect(
      InventoryAdjustmentLocalDao(database)
          .validateProduct('business-a', 'weight-product'),
      throwsA(isA<InventoryAdjustmentException>()),
    );
  });

  test('bootstrap models preserve WEIGHT identity and staged remote cost',
      () async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(id: 'business-a', name: 'Business A'),
        );
    final productRow = OperationalBootstrapRow.fromJson({
      '_bootstrap_record_state': 'present',
      'id': 'remote-weight',
      'business_id': 'business-a',
      'name': 'Remote weight',
      'sale_price': 12000,
      'sale_mode': 'weight',
      'sale_price_cents': 1200000,
      'created_at': '2026-09-30T12:00:00Z',
      'updated_at': '2026-09-30T12:00:00Z',
    });
    final remote = ProductOperationalProductSnapshot.fromRow(productRow);
    await ProductOperationalReconciliationLocalDao(database)
        .upsertProduct(remote);
    final local = await (database.select(database.products)
          ..where((row) => row.id.equals('remote-weight')))
        .getSingle();
    expect(local.saleMode, 'weight');
    expect(local.salePriceCents, 1200000);
    expect(local.stockQuantity, 0);

    final legacy = ProductOperationalProductSnapshot.fromRow(
      OperationalBootstrapRow.fromJson({
        ...productRow.data,
        'id': 'legacy-remote',
      }
        ..remove('sale_mode')
        ..remove('sale_price_cents')),
    );
    expect(legacy.saleMode, ProductSaleMode.unit);
    expect(legacy.salePriceCents, isNull);
    expect(
      () => ProductOperationalProductSnapshot.fromRow(
        OperationalBootstrapRow.fromJson(
            {...productRow.data, 'sale_mode': 'kg'}),
      ),
      throwsFormatException,
    );

    final balance = InventoryBalanceSnapshotRow.fromBootstrapRow(
      OperationalBootstrapRow.fromJson({
        '_bootstrap_record_state': 'present',
        'id': 'remote-balance',
        'business_id': 'business-a',
        'branch_id': 'branch-a',
        'product_id': 'remote-weight',
        'quantity_on_hand': 735,
        'quantity_reserved': 0,
        'quantity_available': 735,
        'cost_basis_cents': '2280000000000000',
        'updated_at': '2026-09-30T12:00:00Z',
      }),
    );
    await ProductStockBalanceLocalDao(database).stageRemoteBaseByScope(
      businessId: balance.businessId,
      branchId: balance.branchId,
      productId: balance.productId,
      remoteBalanceId: balance.remoteBalanceId,
      remoteQuantityOnHand: balance.quantityOnHand,
      remoteQuantityReserved: balance.quantityReserved,
      remoteQuantityAvailable: balance.quantityAvailable,
      remoteAverageCost: balance.averageCost,
      remoteCostBasisCents: balance.costBasisCents,
      remoteUpdatedAt: balance.remoteUpdatedAt,
      remoteSnapshotId: 'snapshot-a',
      remoteTombstone: false,
      remoteDeletedAt: null,
    );
    final staged = await ProductStockBalanceLocalDao(database)
        .getProductBalance(
            businessId: 'business-a',
            branchId: 'branch-a',
            productId: 'remote-weight');
    expect(staged?['remote_quantity_on_hand'], 735);
    expect(staged?['remote_cost_basis_cents'], 2280000000000000);
    expect(staged?['cost_basis_cents'], isNull);

    final item = CashPosSaleItemSnapshotRow.fromRow(
      OperationalBootstrapRow.fromJson({
        '_bootstrap_record_state': 'present',
        'id': 'remote-sale-item',
        'sale_id': 'remote-sale',
        'product_id': 'remote-weight',
        'quantity': 735,
        'unit_price': 12000,
        'subtotal': 17640,
        'sale_mode_snapshot': 'weight',
        'price_basis_quantity_snapshot': 500,
        'price_cents_snapshot': 1200000,
        'line_total_cents': 1764000,
        'cogs_cents': 500000,
        'created_at': '2026-09-30T12:00:00Z',
        'updated_at': '2026-09-30T12:00:00Z',
      }),
    );
    expect(item.saleModeSnapshot, ProductSaleMode.weight);
    expect(item.quantity, 735);
    expect(item.priceBasisQuantitySnapshot, 500);
    expect(item.lineTotalCents, 1764000);
    await database.customStatement(
      "insert into sales (id, total) values ('remote-sale', 17640)",
    );
    await CashPosReconciliationLocalDao(database).applySaleItem(item);
    final persistedItem = await database.customSelect('''
      select quantity, sale_mode_snapshot, price_basis_quantity_snapshot,
             price_cents_snapshot, line_total_cents, cogs_cents
      from sale_items where id = 'remote-sale-item'
    ''').getSingle();
    expect(persistedItem.read<int>('quantity'), 735);
    expect(persistedItem.read<String>('sale_mode_snapshot'), 'weight');
    expect(persistedItem.read<int>('price_basis_quantity_snapshot'), 500);
    expect(persistedItem.read<int>('price_cents_snapshot'), 1200000);
    expect(persistedItem.read<int>('line_total_cents'), 1764000);
    expect(persistedItem.read<int>('cogs_cents'), 500000);
  });
}
