import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/models/product_sale_mode.dart';
import 'package:inventario_frontend/core/quantity/weight_quantity_input.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_models.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_service.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_money.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_sync_outbox_service.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/purchase_local_dao.dart';
import 'package:inventario_frontend/features/sync/application/local_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';

void main() {
  test('grams, kg and commercial pounds parse exactly and fail closed', () {
    expect(parseWeightQuantity('8500', WeightInputUnit.gram), 8500);
    expect(parseWeightQuantity('8', WeightInputUnit.kilogram), 8000);
    expect(parseWeightQuantity('8.5', WeightInputUnit.kilogram), 8500);
    expect(parseWeightQuantity('8,5', WeightInputUnit.kilogram), 8500);
    expect(parseWeightQuantity('8.250', WeightInputUnit.kilogram), 8250);
    expect(parseWeightQuantity('1', WeightInputUnit.commercialPound), 500);
    expect(parseWeightQuantity('1.5', WeightInputUnit.commercialPound), 750);
    expect(parseWeightQuantity('1,25', WeightInputUnit.commercialPound), 625);
    expect(parseWeightQuantity('0.01', WeightInputUnit.commercialPound), 5);
    expect(parseWeightQuantity('8.2505', WeightInputUnit.kilogram), isNull);
    expect(
        parseWeightQuantity('1.001', WeightInputUnit.commercialPound), isNull);
    expect(parseWeightQuantity('8.5', WeightInputUnit.gram), isNull);
    expect(parseWeightQuantity('-1', WeightInputUnit.kilogram), isNull);
    expect(parseWeightQuantity('0', WeightInputUnit.gram), isNull);
    expect(parseWeightQuantity('99999999999999999999', WeightInputUnit.gram),
        isNull);
  });

  test('basis quotes use W2A and remain equivalent without floats', () {
    final pounds = _weight('10', WeightInputUnit.kilogram, '800', 500);
    final kilograms = _weight('10', WeightInputUnit.kilogram, '1600', 1000);
    final oneAndHalf =
        _weight('1.5', WeightInputUnit.commercialPound, '800', 500);
    expect(pounds.quantity, 10000);
    expect(pounds.unitCostCents, BigInt.from(80000));
    expect(pounds.costBasisQuantitySnapshot, 500);
    expect(_subtotal(pounds), BigInt.from(1600000));
    expect(kilograms.quantity, 10000);
    expect(kilograms.unitCostCents, BigInt.from(160000));
    expect(kilograms.costBasisQuantitySnapshot, 1000);
    expect(_subtotal(kilograms), _subtotal(pounds));
    expect(oneAndHalf.quantity, 750);
    expect(_subtotal(oneAndHalf), BigInt.from(120000));
    expect(() => _weight('8.2505', WeightInputUnit.kilogram, '800', 500),
        throwsArgumentError);
    expect(() => _weight('10', WeightInputUnit.kilogram, '800', 250),
        throwsArgumentError);
    expect(() => _weight('10', WeightInputUnit.kilogram, '-800', 500),
        throwsArgumentError);
    expect(() => _weight('10', WeightInputUnit.kilogram, '10000000000', 500),
        throwsArgumentError);
    expect(
      () => _subtotal(_weight(
        '999999999999999',
        WeightInputUnit.kilogram,
        '800',
        500,
      )),
      throwsRangeError,
    );
    expect(
      purchaseBasisLineTotalCents(
        quotedCostCents: BigInt.from(80000),
        quantity: 10,
        costBasisQuantity: 1,
      ),
      BigInt.from(800000),
    );
  });

  group('local weighted purchase', () {
    late AppDatabase db;
    late PurchaseLocalDao dao;
    late PurchaseLocalService service;

    setUp(() async {
      db = AppDatabase.executor(NativeDatabase.memory());
      dao = PurchaseLocalDao(db);
      service = PurchaseLocalService(dao: dao, enableWeightedDomain: true);
      await db.into(db.businesses).insert(
            BusinessesCompanion.insert(id: 'business', name: 'Business'),
          );
      await db.into(db.branches).insert(BranchesCompanion.insert(
            id: 'branch',
            businessId: 'business',
            name: 'Branch',
          ));
      await db
          .into(db.profiles)
          .insert(ProfilesCompanion.insert(id: 'profile'));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'weight-product',
            businessId: const Value('business'),
            name: 'Papa',
            salePrice: 800,
            saleMode: const Value('weight'),
            salePriceCents: const Value(80000),
          ));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: 'unit-product',
            businessId: const Value('business'),
            name: 'Bolsa',
            salePrice: 800,
          ));
    });

    tearDown(() async => db.close());

    test('10 kg at 800/lb persists immutable snapshots, movement and basis',
        () async {
      final result = await _create(
          service, _weight('10', WeightInputUnit.kilogram, '800', 500));
      expect(result.totalCents, BigInt.from(1600000));
      expect(result.lines.single.quantity, 10000);
      expect(result.lines.single.saleModeSnapshot, ProductSaleMode.weight);
      expect(result.lines.single.costBasisQuantitySnapshot, 500);
      final item = await _single(db, 'purchase_items');
      expect(item['quantity'], 10000);
      expect(item['sale_mode_snapshot'], 'weight');
      expect(item['cost_basis_quantity_snapshot'], 500);
      expect(item['unit_cost_cents'], 80000);
      expect(item['subtotal_cents'], 1600000);
      final movement = await _single(db, 'local_inventory_movements');
      expect(movement['quantity_change'], 10000);
      expect(movement['cost_effect_cents'], 1600000);
      final balance = await _single(db, 'local_product_stock_balances');
      expect(balance['quantity_on_hand'], 10000);
      expect(balance['cost_basis_cents'], 1600000);
      expect(balance['average_cost'], isNull);
    });

    test('10 kg at 1600/kg persists the same exact total', () async {
      final result = await _create(
          service, _weight('10', WeightInputUnit.kilogram, '1600', 1000));
      expect(result.totalCents, BigInt.from(1600000));
      final item = await _single(db, 'purchase_items');
      expect(item['quantity'], 10000);
      expect(item['cost_basis_quantity_snapshot'], 1000);
      expect(item['unit_cost_cents'], 160000);
      expect(item['subtotal_cents'], 1600000);
    });

    test('known replenishment uses W2B total basis, not last cost', () async {
      await _balance(db, 3000, 480000);
      await _create(
          service, _weight('10', WeightInputUnit.kilogram, '900', 500));
      final balance = await _single(db, 'local_product_stock_balances');
      expect(balance['quantity_on_hand'], 13000);
      expect(balance['cost_basis_cents'], 2280000);
      final movement = await _single(db, 'local_inventory_movements');
      expect(movement['cost_effect_cents'], 1800000);
    });

    test('an empty unknown balance adopts the exact receipt cost', () async {
      await _balance(db, 0, null);
      await _create(
          service, _weight('1', WeightInputUnit.kilogram, '800', 500));
      final balance = await _single(db, 'local_product_stock_balances');
      expect(balance['quantity_on_hand'], 1000);
      expect(balance['cost_basis_cents'], 160000);
    });

    test('unknown prior cost remains unknown but receipt effect is known',
        () async {
      await _balance(db, 3000, null);
      await _create(
          service, _weight('10', WeightInputUnit.kilogram, '900', 500));
      final balance = await _single(db, 'local_product_stock_balances');
      expect(balance['quantity_on_hand'], 13000);
      expect(balance['cost_basis_cents'], isNull);
      expect(
          (await _single(db, 'local_inventory_movements'))['cost_effect_cents'],
          1800000);
    });

    test('three receipts sum exact subtotals across variable quotes', () async {
      await _create(
          service, _weight('10', WeightInputUnit.kilogram, '900', 500));
      await _create(
          service, _weight('5', WeightInputUnit.kilogram, '800', 500));
      await _create(
          service, _weight('3', WeightInputUnit.kilogram, '1000', 500));
      final balance = await _single(db, 'local_product_stock_balances');
      expect(balance['quantity_on_hand'], 18000);
      expect(balance['cost_basis_cents'], 3200000);
    });

    test('mode mismatch blocks both paths before any local write', () async {
      await expectLater(
        _create(
            service,
            PurchaseLocalItemInput(
              productId: 'weight-product',
              quantity: 1,
              unitCostCents: BigInt.from(80000),
            )),
        throwsStateError,
      );
      await expectLater(
        _create(
            service,
            PurchaseLocalItemInput(
              productId: 'unit-product',
              quantity: 500,
              unitCostCents: BigInt.from(80000),
              saleModeSnapshot: ProductSaleMode.weight,
              costBasisQuantitySnapshot: 500,
            )),
        throwsStateError,
      );
      final count = await db
          .customSelect(
            'select count(*) as total from purchases',
          )
          .getSingle();
      expect(count.read<int>('total'), 0);
    });

    test('productive service remains closed to weighted purchases', () async {
      final productiveService = PurchaseLocalService(dao: dao);
      await expectLater(
        _create(productiveService,
            _weight('1', WeightInputUnit.kilogram, '800', 500)),
        throwsStateError,
      );
      final count = await db
          .customSelect(
            'select count(*) as total from purchases',
          )
          .getSingle();
      expect(count.read<int>('total'), 0);
    });

    test('weight outbox freezes grams, basis, cents and subtotal on retry',
        () async {
      final result = await _create(
          service, _weight('10', WeightInputUnit.kilogram, '800', 500));
      final outbox = PurchaseSyncOutboxService(
        dao: dao,
        outboxService: LocalSyncOutboxService(LocalSyncOutboxDao(db)),
      );
      Future<void> enqueue() async {
        await outbox.enqueuePendingPurchases(
          businessId: 'business',
          branchId: 'branch',
          profileId: 'profile',
          deviceInstallationId: 'installation',
        );
      }

      await enqueue();
      final first = await _itemPayload(db);
      expect(first['contract_version'], 'weighted_purchase_v1');
      expect(first['sale_mode_snapshot'], 'weight');
      expect(first['quantity'], 10000);
      expect(first['cost_basis_quantity'], 500);
      expect(first['unit_cost_cents'], 80000);
      expect(first['subtotal_cents'], 1600000);
      await enqueue();
      final second = await _itemPayload(db);
      for (final field in [
        'quantity',
        'sale_mode_snapshot',
        'cost_basis_quantity',
        'unit_cost_cents',
        'subtotal_cents',
      ]) {
        expect(second[field], first[field]);
      }
      final item = await _single(db, 'purchase_items');
      expect(item['purchase_id'], result.purchaseId);
      final mutationCount = await db.customSelect('''
        select count(*) as total from local_sync_mutations
        where entity_table = 'purchase_items'
      ''').getSingle();
      expect(mutationCount.read<int>('total'), 1);
      expect(
          (await _single(
              db, 'local_product_stock_balances'))['quantity_on_hand'],
          10000);
    });

    test('outbox refuses a malformed stored weighted subtotal', () async {
      await _create(
          service, _weight('10', WeightInputUnit.kilogram, '800', 500));
      await db.customUpdate(
        'update purchase_items set subtotal_cents = 1',
        updates: {db.purchaseItems},
      );
      final outbox = PurchaseSyncOutboxService(
        dao: dao,
        outboxService: LocalSyncOutboxService(LocalSyncOutboxDao(db)),
      );
      await expectLater(
        outbox.enqueuePendingPurchases(
          businessId: 'business',
          branchId: 'branch',
          profileId: 'profile',
        ),
        throwsStateError,
      );
      final mutations = await db
          .customSelect(
            'select count(*) as total from local_sync_mutations',
          )
          .getSingle();
      expect(mutations.read<int>('total'), 0);
    });

    test('outbox cannot downgrade a weighted purchase item to UNIT', () async {
      await _create(
          service, _weight('10', WeightInputUnit.kilogram, '800', 500));
      await db.customUpdate(
        "update purchase_items set sale_mode_snapshot = 'unit'",
        updates: {db.purchaseItems},
      );
      final outbox = PurchaseSyncOutboxService(
        dao: dao,
        outboxService: LocalSyncOutboxService(LocalSyncOutboxDao(db)),
      );
      await expectLater(
        outbox.enqueuePendingPurchases(
          businessId: 'business',
          branchId: 'branch',
          profileId: 'profile',
        ),
        throwsStateError,
      );
      final mutations = await db
          .customSelect(
            'select count(*) as total from local_sync_mutations',
          )
          .getSingle();
      expect(mutations.read<int>('total'), 0);
    });
  });
}

PurchaseLocalItemInput _weight(
  String quantity,
  WeightInputUnit unit,
  String cost,
  int basis,
) =>
    PurchaseLocalItemInput.weightedFromText(
      productId: 'weight-product',
      quantityText: quantity,
      inputUnit: unit,
      quotedCostText: cost,
      costBasisQuantitySnapshot: basis,
    );

BigInt _subtotal(PurchaseLocalItemInput item) => purchaseBasisLineTotalCents(
      quotedCostCents: item.unitCostCents,
      quantity: item.quantity,
      costBasisQuantity: item.costBasisQuantitySnapshot,
    );

Future<PurchaseLocalResult> _create(
  PurchaseLocalService service,
  PurchaseLocalItemInput item,
) =>
    service.createLocalPurchase(CreatePurchaseLocalInput(
      businessId: 'business',
      branchId: 'branch',
      profileId: 'profile',
      deviceInstallationId: 'installation',
      items: [item],
    ));

Future<Map<String, dynamic>> _single(AppDatabase db, String table) async =>
    (await db.customSelect('select * from $table').getSingle()).data;

Future<void> _balance(AppDatabase db, int quantity, int? cost) =>
    db.into(db.localProductStockBalances).insert(
          LocalProductStockBalancesCompanion.insert(
            id: 'prior-balance',
            businessId: 'business',
            branchId: 'branch',
            productId: 'weight-product',
            quantityOnHand: Value(quantity),
            quantityAvailable: Value(quantity),
            costBasisCents: Value(cost),
          ),
        );

Future<Map<String, dynamic>> _itemPayload(AppDatabase db) async {
  final row = await db.customSelect('''
    select payload_json from local_sync_mutations
    where entity_table = 'purchase_items' limit 1
  ''').getSingle();
  return jsonDecode(row.read<String>('payload_json')) as Map<String, dynamic>;
}
