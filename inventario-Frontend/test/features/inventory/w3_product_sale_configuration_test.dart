import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/models/product_sale_mode.dart';
import 'package:inventario_frontend/core/money/cop_price_input.dart';
import 'package:inventario_frontend/features/catalog/application/catalog_barcode_lookup_service.dart';
import 'package:inventario_frontend/features/catalog/data/datasources/catalog_local_dao.dart';
import 'package:inventario_frontend/features/inventory/application/business_product_creation_models.dart';
import 'package:inventario_frontend/features/inventory/application/business_product_creation_service.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_creation_service.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_from_master_sync_service.dart';
import 'package:inventario_frontend/features/sync/application/local_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';

void main() {
  const context = BusinessProductCreationContext(
    businessId: 'business-a',
    branchId: 'branch-a',
    profileId: 'profile-a',
    appDeviceId: 'device-a',
    deviceInstallationId: 'installation-a',
    effectivePermissions: {'products.create', 'products.update'},
  );
  late AppDatabase database;
  late BusinessProductCreationService service;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    await database.customStatement(
        "insert into businesses (id, name) values ('business-a', 'A')");
    final creation = InventoryProductCreationService(database);
    service = BusinessProductCreationService(
      barcodeLookupService: CatalogBarcodeLookupService(
        lookupByBarcode: CatalogLocalDao(database).lookupByBarcode,
      ),
      productSyncService: InventoryProductFromMasterSyncService(
        database: database,
        productCreationService: creation,
        outboxService: LocalSyncOutboxService(LocalSyncOutboxDao(database)),
      ),
    );
  });
  tearDown(() => database.close());

  test('COP parser yields exact cents and rejects ambiguous/overflow input',
      () {
    expect(parseCopPriceCents('12000'), 1200000);
    expect(parseCopPriceCents('12.000'), 1200000);
    expect(parseCopPriceCents('12000,50'), 1200050);
    expect(parseCopPriceCents('12.000,50'), 1200050);
    expect(parseCopPriceCents('12.50'), isNull);
    expect(parseCopPriceCents('9999999999,99'), 999999999999);
    expect(parseCopPriceCents('10000000000'), isNull);
    expect(exactPesosFromCents(80000), '800.00');
    expect(ProductSaleMode.unit.salePriceBasisQuantity, 1);
    expect(ProductSaleMode.weight.salePriceBasisQuantity, 500);
  });

  test('UNIT legacy and explicit WEIGHT create through local outbox', () async {
    final unit = await service.createOrUse(
      context: context,
      fields: const BusinessProductOwnedFields(
          name: 'Unit', purchasePrice: 0, salePrice: 3500, unit: 'kg'),
    );
    final weight = await service.createOrUse(
      context: context,
      fields: const BusinessProductOwnedFields(
          name: 'Papa',
          purchasePrice: 0,
          salePrice: 800,
          saleMode: ProductSaleMode.weight,
          salePriceCents: 80000),
    );
    expect(unit.succeeded, isTrue);
    expect(weight.succeeded, isTrue);
    final rows = await database.customSelect('''
      select name, unit, sale_mode, sale_price_cents
      from products order by name
    ''').get();
    expect(
        rows.map((row) => row.data).toList(),
        containsAll([
          containsPair('sale_mode', 'weight'),
          containsPair('sale_mode', 'unit'),
        ]));
    expect((weight.product?['sale_mode']), 'weight');
    expect((weight.product?['sale_price_cents']), 80000);
    expect((weight.product?['sale_price']), '800.00');
    expect(rows.first.read<String>('unit'), 'unidad');
    expect(rows.last.read<String>('unit'), 'kg');
    final mutations = await database.customSelect('''
      select payload_json from local_sync_mutations where entity_table = 'products'
    ''').get();
    expect(mutations, hasLength(2));
    expect(
        mutations.any((row) =>
            row.read<String>('payload_json').contains('"sale_mode":"weight"')),
        isTrue);
  });

  test('price edit and mode switch are transactional; no-op adds no outbox',
      () async {
    final created = await service.createOrUse(
      context: context,
      fields: const BusinessProductOwnedFields(
          name: 'Papa',
          purchasePrice: 0,
          salePrice: 800,
          saleMode: ProductSaleMode.unit,
          salePriceCents: 80000),
    );
    final productId = created.productId!;
    final update = await service.updateSaleConfiguration(
      BusinessProductSaleConfigurationUpdateInput(
          context: context,
          productId: productId,
          saleMode: ProductSaleMode.weight,
          salePriceCents: 90000),
    );
    expect(update.succeeded, isTrue);
    expect(update.changed, isTrue);
    final row = await database.customSelect(
      'select sale_mode, sale_price_cents from products where id = ?',
      variables: [Variable<String>(productId)],
    ).getSingle();
    expect(row.read<String>('sale_mode'), 'weight');
    expect(row.read<int>('sale_price_cents'), 90000);
    final before = await database
        .customSelect('select count(*) as n from local_sync_mutations')
        .getSingle();
    final repeat = await service.updateSaleConfiguration(
      BusinessProductSaleConfigurationUpdateInput(
          context: context,
          productId: productId,
          saleMode: ProductSaleMode.weight,
          salePriceCents: 90000),
    );
    final after = await database
        .customSelect('select count(*) as n from local_sync_mutations')
        .getSingle();
    expect(repeat.changed, isFalse);
    expect(after.read<int>('n'), before.read<int>('n'));
  });

  test('stock and each historical ledger type block both mode directions',
      () async {
    for (final history in ['stock', 'movement', 'sale', 'purchase']) {
      final created = await service.createOrUse(
        context: context,
        fields: BusinessProductOwnedFields(
            name: 'History $history',
            purchasePrice: 0,
            salePrice: 800,
            saleMode: ProductSaleMode.unit,
            salePriceCents: 80000),
      );
      final id = created.productId!;
      if (history == 'stock') {
        await database
            .customStatement('''insert into local_product_stock_balances
          (id, business_id, branch_id, product_id, quantity_on_hand)
          values ('$history', 'business-a', 'branch-a', '$id', 5)''');
      } else if (history == 'movement') {
        await database.customStatement('''insert into local_inventory_movements
          (id, business_id, product_id, movement_type, quantity_change,
           idempotency_key, occurred_at)
          values ('$history', 'business-a', '$id', 'purchase', 1,
                  '$history', 1758814200)''');
      } else if (history == 'sale') {
        await database.customStatement('''insert into sale_items
          (id, product_id, quantity, unit_price, subtotal)
          values ('$history', '$id', 1, 800, 800)''');
      } else {
        await database.customStatement('''insert into purchase_items
          (id, product_id, quantity, unit_cost, subtotal)
          values ('$history', '$id', 1, 500, 500)''');
      }
      final result = await service.updateSaleConfiguration(
        BusinessProductSaleConfigurationUpdateInput(
            context: context,
            productId: id,
            saleMode: ProductSaleMode.weight,
            salePriceCents: 80000),
      );
      expect(result.succeeded, isFalse, reason: history);
      expect(result.message, contains('No puedes cambiar'), reason: history);
      final row = await database
          .customSelect("select sale_mode from products where id = '$id'")
          .getSingle();
      expect(row.read<String>('sale_mode'), 'unit');
    }
    final weighted = await service.createOrUse(
      context: context,
      fields: const BusinessProductOwnedFields(
          name: 'Weighted history',
          purchasePrice: 0,
          salePrice: 800,
          saleMode: ProductSaleMode.weight,
          salePriceCents: 80000),
    );
    await database.customStatement('''insert into sale_items
      (id, product_id, quantity, unit_price, subtotal)
      values ('weighted-sale', '${weighted.productId}', 735, 800, 1176)''');
    final reverse = await service.updateSaleConfiguration(
      BusinessProductSaleConfigurationUpdateInput(
          context: context,
          productId: weighted.productId!,
          saleMode: ProductSaleMode.unit,
          salePriceCents: 80000),
    );
    expect(reverse.succeeded, isFalse);
  });
}
