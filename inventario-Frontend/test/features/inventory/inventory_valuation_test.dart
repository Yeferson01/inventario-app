import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/database/database_provider.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_valuation_models.dart';
import 'package:inventario_frontend/features/inventory/application/product_stock_balance_providers.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/product_stock_balance_local_dao.dart';

void main() {
  group('inventory product valuation', () {
    test('uses exact cents for known, zero, unknown and invalid stock', () {
      final known = InventoryProductValuation.fromStock(
        quantityOnHand: 10,
        averageCost: 5,
      );
      final zeroStock = InventoryProductValuation.fromStock(
        quantityOnHand: 0,
        averageCost: null,
      );
      final zeroCost = InventoryProductValuation.fromStock(
        quantityOnHand: 3,
        averageCost: 0,
      );
      final unknown = InventoryProductValuation.fromStock(
        quantityOnHand: 3,
        averageCost: null,
      );
      final invalid = InventoryProductValuation.fromStock(
        quantityOnHand: -1,
        averageCost: 5,
      );

      expect(known.valueCents, BigInt.from(5000));
      expect(zeroStock.valueCents, BigInt.zero);
      expect(zeroCost.valueCents, BigInt.zero);
      expect(unknown.status, InventoryProductValuationStatus.unknownCost);
      expect(unknown.valueCents, null);
      expect(invalid.status, InventoryProductValuationStatus.invalidStock);
      expect(invalid.valueCents, null);
    });

    test('uses the contractual rounded average cost for purchase and sale', () {
      final weightedPurchase = InventoryProductValuation.fromStock(
        quantityOnHand: 15,
        averageCost: 2.67,
      );
      final afterSale = InventoryProductValuation.fromStock(
        quantityOnHand: 6,
        averageCost: 5,
      );

      expect(weightedPurchase.valueCents, BigInt.from(4005));
      expect(afterSale.valueCents, BigInt.from(3000));
      expect(
          formatInventoryMoneyCents(weightedPurchase.valueCents!), r'$40.05');
    });

    test('BigInt keeps values exact beyond the signed 64-bit range', () {
      final valuation = InventoryProductValuation.fromStock(
        quantityOnHand: 9223372036854775807,
        averageCost: 999999999999.99,
      );

      expect(valuation.status, InventoryProductValuationStatus.known);
      expect(
        valuation.valueCents!,
        greaterThan(BigInt.parse('9223372036854775807')),
      );
      expect(
        InventoryProductValuation.fromStock(
          quantityOnHand: 1,
          averageCost: double.infinity,
        ).status,
        InventoryProductValuationStatus.precisionAnomaly,
      );
      expect(
        InventoryProductValuation.fromStock(
          quantityOnHand: 1,
          averageCost: 1000000000000,
        ).status,
        InventoryProductValuationStatus.precisionAnomaly,
      );
    });

    test('partial summary reports unknown units without treating them as zero',
        () {
      final summary = InventoryValuationSummary.fromRows([
        {'quantity_on_hand': 10, 'stock_average_cost': 5},
        {'quantity_on_hand': 3, 'stock_average_cost': null},
        {'quantity_on_hand': 0, 'stock_average_cost': null},
        {'quantity_on_hand': -2, 'stock_average_cost': 10},
      ]);

      expect(summary.knownValueCents, BigInt.from(5000));
      expect(summary.unknownCostProductCount, 1);
      expect(summary.unknownCostUnitCount, BigInt.from(3));
      expect(summary.invalidStockProductCount, 1);
      expect(summary.isComplete, isFalse);
    });

    test('transfer valuation derives independently from resulting balances',
        () {
      final source = InventoryProductValuation.fromStock(
        quantityOnHand: 7,
        averageCost: 12.50,
      );
      final destination = InventoryProductValuation.fromStock(
        quantityOnHand: 3,
        averageCost: 12.50,
      );

      expect(source.valueCents, BigInt.from(8750));
      expect(destination.valueCents, BigInt.from(3750));
      expect(source.valueCents! + destination.valueCents!, BigInt.from(12500));
    });
  });

  group('branch valuation inputs', () {
    late AppDatabase database;
    late ProductStockBalanceLocalDao dao;

    setUp(() async {
      database = AppDatabase.executor(NativeDatabase.memory());
      dao = ProductStockBalanceLocalDao(database);
      await _insertBusiness(database, 'business-a');
      await _insertBusiness(database, 'business-b');
    });

    tearDown(() => database.close());

    test('isolates business and branch and treats missing balance as zero',
        () async {
      await _insertProduct(database, 'product-a', 'business-a');
      await _insertProduct(database, 'product-missing', 'business-a');
      await _insertProduct(database, 'product-b', 'business-b');
      await _insertBalance(
        database,
        id: 'balance-a',
        businessId: 'business-a',
        branchId: 'branch-a',
        productId: 'product-a',
        quantity: 10,
        averageCost: 5,
      );
      await _insertBalance(
        database,
        id: 'balance-other-branch',
        businessId: 'business-a',
        branchId: 'branch-b',
        productId: 'product-a',
        quantity: 99,
        averageCost: 99,
      );
      await _insertBalance(
        database,
        id: 'balance-other-business',
        businessId: 'business-b',
        branchId: 'branch-a',
        productId: 'product-b',
        quantity: 50,
        averageCost: 10,
      );

      final rows = await dao
          .watchBranchInventoryValuationInputs(
            businessId: 'business-a',
            branchId: 'branch-a',
          )
          .first;
      final summary = InventoryValuationSummary.fromRows(rows);

      expect(rows, hasLength(2));
      expect(summary.knownValueCents, BigInt.from(5000));
      expect(summary.unknownCostProductCount, 0);
      expect(summary.isComplete, isTrue);
    });

    test('reacts to average cost, quantity and balance tombstone changes',
        () async {
      await _insertProduct(database, 'product-a', 'business-a');
      final summaries = dao
          .watchBranchInventoryValuationInputs(
            businessId: 'business-a',
            branchId: 'branch-a',
          )
          .map(InventoryValuationSummary.fromRows);
      final iterator = StreamIterator(summaries);
      addTearDown(iterator.cancel);

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.knownValueCents, BigInt.zero);

      await _insertBalance(
        database,
        id: 'balance-a',
        businessId: 'business-a',
        branchId: 'branch-a',
        productId: 'product-a',
        quantity: 10,
        averageCost: 2,
      );
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.knownValueCents, BigInt.from(2000));

      await (database.update(database.localProductStockBalances)
            ..where((balance) => balance.id.equals('balance-a')))
          .write(const LocalProductStockBalancesCompanion(
        averageCost: Value(4.5),
      ));
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.knownValueCents, BigInt.from(4500));

      await (database.update(database.localProductStockBalances)
            ..where((balance) => balance.id.equals('balance-a')))
          .write(const LocalProductStockBalancesCompanion(
        quantityOnHand: Value(6),
      ));
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.knownValueCents, BigInt.from(2700));

      await (database.update(database.localProductStockBalances)
            ..where((balance) => balance.id.equals('balance-a')))
          .write(LocalProductStockBalancesCompanion(
        deletedAt: Value(DateTime.utc(2026, 9, 7)),
      ));
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.knownValueCents, BigInt.zero);
      expect(iterator.current.isComplete, isTrue);
    });

    test('summary is independent from list search and stock filters', () async {
      await _insertProduct(database, 'rice', 'business-a', name: 'Arroz');
      await _insertProduct(database, 'coffee', 'business-a', name: 'Café');
      await _insertBalance(
        database,
        id: 'rice-balance',
        businessId: 'business-a',
        branchId: 'branch-a',
        productId: 'rice',
        quantity: 10,
        averageCost: 5,
      );
      await _insertBalance(
        database,
        id: 'coffee-balance',
        businessId: 'business-a',
        branchId: 'branch-a',
        productId: 'coffee',
        quantity: 0,
        averageCost: 20,
      );

      final summaryRows = await dao
          .watchBranchInventoryValuationInputs(
            businessId: 'business-a',
            branchId: 'branch-a',
          )
          .first;
      final searchRows = await dao.getProductsWithLocalStock(
        businessId: 'business-a',
        branchId: 'branch-a',
        searchTerm: 'arroz',
        limit: null,
      );
      final exhaustedRows = await dao.getProductsWithLocalStock(
        businessId: 'business-a',
        branchId: 'branch-a',
        stockFilter: InventoryProductStockFilter.outOfStock,
        limit: null,
      );

      expect(searchRows, hasLength(1));
      expect(exhaustedRows, hasLength(1));
      expect(
        InventoryValuationSummary.fromRows(summaryRows).knownValueCents,
        BigInt.from(5000),
      );
    });

    test('application providers expose typed row and scoped summary values',
        () async {
      await _insertProduct(database, 'product-a', 'business-a');
      await _insertBalance(
        database,
        id: 'balance-a',
        businessId: 'business-a',
        branchId: 'branch-a',
        productId: 'product-a',
        quantity: 15,
        averageCost: 2.67,
      );
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);

      final productsProvider = localProductsWithStockProvider(
        const ProductsWithLocalStockKey(
          businessId: 'business-a',
          branchId: 'branch-a',
          limit: null,
        ),
      );
      final summaryProvider = inventoryValuationSummaryProvider(
        const InventoryValuationSummaryKey(
          businessId: 'business-a',
          branchId: 'branch-a',
        ),
      );
      final productsSubscription = container.listen(
        productsProvider,
        (_, __) {},
        fireImmediately: true,
      );
      final summarySubscription = container.listen(
        summaryProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(productsSubscription.close);
      addTearDown(summarySubscription.close);
      final products = await container.read(productsProvider.future);
      final summary = await container.read(summaryProvider.future);

      final rowValuation =
          products.single['inventory_valuation'] as InventoryProductValuation;
      expect(rowValuation.valueCents, BigInt.from(4005));
      expect(summary.knownValueCents, BigInt.from(4005));
      expect(summary.isComplete, isTrue);
    });
  });
}

Future<void> _insertBusiness(AppDatabase database, String id) {
  return database.into(database.businesses).insert(
        BusinessesCompanion.insert(id: id, name: 'Business $id'),
      );
}

Future<void> _insertProduct(
  AppDatabase database,
  String id,
  String businessId, {
  String? name,
}) {
  return database.into(database.products).insert(
        ProductsCompanion.insert(
          id: id,
          businessId: Value(businessId),
          name: name ?? 'Product $id',
          salePrice: 100,
        ),
      );
}

Future<void> _insertBalance(
  AppDatabase database, {
  required String id,
  required String businessId,
  required String branchId,
  required String productId,
  required int quantity,
  required double? averageCost,
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
