import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/product_stock_balance_local_dao.dart';

void main() {
  const businessId = 'business-1';
  const branchId = 'branch-1';

  late AppDatabase database;
  late ProductStockBalanceLocalDao dao;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    dao = ProductStockBalanceLocalDao(database);

    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(
            id: businessId,
            name: 'Negocio de prueba',
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'lists positive, zero and missing balances while excluding soft deletes',
    () async {
      await _insertProduct(
        database,
        id: 'positive',
        businessId: businessId,
        name: 'A positivo',
        barcode: '770000000001',
        legacyStock: 999,
        minimumStock: 5,
      );
      await _insertProduct(
        database,
        id: 'zero',
        businessId: businessId,
        name: 'B cero',
      );
      await _insertProduct(
        database,
        id: 'missing',
        businessId: businessId,
        name: 'C sin balance',
      );
      await _insertProduct(
        database,
        id: 'deleted',
        businessId: businessId,
        name: 'D eliminado',
        deletedAt: DateTime.utc(2026, 1, 1),
      );
      await _insertProduct(
        database,
        id: 'inactive',
        businessId: businessId,
        name: 'E inactivo',
        status: 'inactive',
      );
      await _insertProduct(
        database,
        id: 'negative',
        businessId: businessId,
        name: 'D negativo',
      );

      await _insertBalance(
        database,
        id: 'balance-positive',
        businessId: businessId,
        branchId: branchId,
        productId: 'positive',
        quantityOnHand: 15,
      );
      await _insertBalance(
        database,
        id: 'balance-zero',
        businessId: businessId,
        branchId: branchId,
        productId: 'zero',
        quantityOnHand: 0,
      );
      await _insertBalance(
        database,
        id: 'balance-deleted',
        businessId: businessId,
        branchId: branchId,
        productId: 'deleted',
        quantityOnHand: 8,
      );
      await _insertBalance(
        database,
        id: 'balance-tombstoned',
        businessId: businessId,
        branchId: branchId,
        productId: 'missing',
        quantityOnHand: 23,
        deletedAt: DateTime.utc(2026, 1, 2),
      );
      await _insertBalance(
        database,
        id: 'balance-negative',
        businessId: businessId,
        branchId: branchId,
        productId: 'negative',
        quantityOnHand: -3,
      );

      final products = await dao.getProductsWithLocalStock(
        businessId: businessId,
        branchId: branchId,
        limit: null,
      );

      expect(
        products.map((product) => product['product_id']),
        ['positive', 'zero', 'missing', 'negative'],
      );
      expect(products[0]['quantity_on_hand'], 15);
      expect(products[0]['legacy_stock_quantity'], 999);
      expect(products[0]['minimum_stock'], 5);
      expect(products[1]['quantity_on_hand'], 0);
      expect(products[2]['quantity_on_hand'], 0);
      expect(products[2]['quantity_reserved'], 0);
      expect(products[2]['quantity_available'], 0);
      expect(products[3]['quantity_on_hand'], -3);
    },
  );

  test('ten active products with nine balances return ten rows', () async {
    await _insertProducts(
      database,
      businessId: businessId,
      count: 10,
      idPrefix: 'recovered',
    );
    for (var index = 0; index < 9; index++) {
      await _insertBalance(
        database,
        id: 'balance-$index',
        businessId: businessId,
        branchId: branchId,
        productId: 'recovered-$index',
        quantityOnHand: index + 1,
      );
    }

    final products = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      limit: null,
    );

    expect(products, hasLength(10));
    expect(products.last['product_id'], 'recovered-9');
    expect(products.last['quantity_on_hand'], 0);
  });

  test('isolates product stock by business and branch', () async {
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(
            id: 'business-2',
            name: 'Otro negocio',
          ),
        );
    await _insertProduct(
      database,
      id: 'product-a',
      businessId: businessId,
      name: 'Producto A',
      minimumStock: 5,
    );
    await _insertProduct(
      database,
      id: 'product-b',
      businessId: 'business-2',
      name: 'Producto B',
      minimumStock: 9,
    );
    await _insertBalance(
      database,
      id: 'balance-a-x',
      businessId: businessId,
      branchId: branchId,
      productId: 'product-a',
      quantityOnHand: 4,
    );
    await _insertBalance(
      database,
      id: 'balance-a-y',
      businessId: businessId,
      branchId: 'branch-2',
      productId: 'product-a',
      quantityOnHand: 99,
    );
    await _insertBalance(
      database,
      id: 'balance-b-x',
      businessId: 'business-2',
      branchId: branchId,
      productId: 'product-b',
      quantityOnHand: 77,
    );

    final principalProducts = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      limit: null,
    );
    final vendeMasProducts = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: 'branch-2',
      limit: null,
    );

    expect(principalProducts, hasLength(1));
    expect(principalProducts.single['product_id'], 'product-a');
    expect(principalProducts.single['quantity_on_hand'], 4);
    expect(principalProducts.single['minimum_stock'], 5);
    expect(vendeMasProducts, hasLength(1));
    expect(vendeMasProducts.single['product_id'], 'product-a');
    expect(vendeMasProducts.single['quantity_on_hand'], 99);
    expect(vendeMasProducts.single['minimum_stock'], 5);
    expect(principalProducts.single['quantity_on_hand'], isNot(103));
    expect(vendeMasProducts.single['quantity_on_hand'], isNot(103));
  });

  test(
      'out-of-stock filter uses physical stock and includes missing balances independently of minimum stock',
      () async {
    await _insertProduct(
      database,
      id: 'exhausted',
      businessId: businessId,
      name: 'A agotado',
      minimumStock: 0,
    );
    await _insertProduct(
      database,
      id: 'below-minimum',
      businessId: businessId,
      name: 'B bajo mínimo',
      minimumStock: 5,
    );
    await _insertProduct(
      database,
      id: 'reserved',
      businessId: businessId,
      name: 'C reservado',
    );
    await _insertProduct(
      database,
      id: 'missing',
      businessId: businessId,
      name: 'D sin balance',
    );
    await _insertBalance(
      database,
      id: 'balance-exhausted',
      businessId: businessId,
      branchId: branchId,
      productId: 'exhausted',
      quantityOnHand: 0,
    );
    await _insertBalance(
      database,
      id: 'balance-below-minimum',
      businessId: businessId,
      branchId: branchId,
      productId: 'below-minimum',
      quantityOnHand: 2,
    );
    await _insertBalance(
      database,
      id: 'balance-reserved',
      businessId: businessId,
      branchId: branchId,
      productId: 'reserved',
      quantityOnHand: 4,
      quantityReserved: 4,
      quantityAvailable: 0,
    );

    final products = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      stockFilter: InventoryProductStockFilter.outOfStock,
      limit: null,
    );

    expect(
      products.map((product) => product['product_id']),
      ['exhausted', 'missing'],
    );
    expect(products.first['minimum_stock'], 0);
    expect(products.last['quantity_on_hand'], 0);
  });

  test('out-of-stock filter is scoped to the selected branch', () async {
    await _insertProduct(
      database,
      id: 'branch-product',
      businessId: businessId,
      name: 'Producto por sucursal',
    );
    await _insertBalance(
      database,
      id: 'branch-product-a',
      businessId: businessId,
      branchId: branchId,
      productId: 'branch-product',
      quantityOnHand: 0,
    );
    await _insertBalance(
      database,
      id: 'branch-product-b',
      businessId: businessId,
      branchId: 'branch-2',
      productId: 'branch-product',
      quantityOnHand: 8,
    );

    final branchA = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      stockFilter: InventoryProductStockFilter.outOfStock,
      limit: null,
    );
    final branchB = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: 'branch-2',
      stockFilter: InventoryProductStockFilter.outOfStock,
      limit: null,
    );

    expect(branchA.single['product_id'], 'branch-product');
    expect(branchB, isEmpty);
  });

  test('out-of-stock filter combines with name and barcode search', () async {
    await _insertProduct(
      database,
      id: 'rice-exhausted',
      businessId: businessId,
      name: 'Arroz agotado',
    );
    await _insertProduct(
      database,
      id: 'rice-positive',
      businessId: businessId,
      name: 'Arroz disponible',
    );
    await _insertProduct(
      database,
      id: 'coffee-exhausted',
      businessId: businessId,
      name: 'Café agotado',
    );
    await _insertBalance(
      database,
      id: 'rice-exhausted-balance',
      businessId: businessId,
      branchId: branchId,
      productId: 'rice-exhausted',
      quantityOnHand: 0,
    );
    await _insertBalance(
      database,
      id: 'rice-positive-balance',
      businessId: businessId,
      branchId: branchId,
      productId: 'rice-positive',
      quantityOnHand: 3,
    );
    await _insertBalance(
      database,
      id: 'coffee-exhausted-balance',
      businessId: businessId,
      branchId: branchId,
      productId: 'coffee-exhausted',
      quantityOnHand: 0,
    );
    await _insertBarcode(
      database,
      id: 'rice-exhausted-code',
      businessId: businessId,
      productId: 'rice-exhausted',
      barcode: 'RICE-000',
      normalized: 'RICE000',
    );

    final byName = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      searchTerm: 'Arroz',
      stockFilter: InventoryProductStockFilter.outOfStock,
      limit: null,
    );
    final byBarcode = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      searchTerm: 'rice-000',
      stockFilter: InventoryProductStockFilter.outOfStock,
      limit: null,
    );

    expect(byName.map((product) => product['product_id']), ['rice-exhausted']);
    expect(byBarcode.single['product_id'], 'rice-exhausted');
  });

  test('out-of-stock stream reacts when operative stock exits and enters zero',
      () async {
    await _insertProduct(
      database,
      id: 'reactive-filter',
      businessId: businessId,
      name: 'Producto reactivo filtrado',
    );
    await _insertBalance(
      database,
      id: 'balance-reactive-filter',
      businessId: businessId,
      branchId: branchId,
      productId: 'reactive-filter',
      quantityOnHand: 5,
    );
    final stream = dao.watchProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      stockFilter: InventoryProductStockFilter.outOfStock,
      limit: null,
    );

    expect(await stream.first, isEmpty);
    final exhausted = stream.firstWhere((products) => products.isNotEmpty);
    await dao.finalizeOperativeBalance(
      businessId: businessId,
      branchId: branchId,
      productId: 'reactive-filter',
      quantityOnHand: 0,
      quantityReserved: 0,
      quantityAvailable: 0,
      averageCost: null,
      lastMovementAt: DateTime.utc(2026, 9, 4),
      deletedAt: null,
    );
    expect((await exhausted).single['product_id'], 'reactive-filter');

    final replenished = stream.firstWhere((products) => products.isEmpty);
    await dao.finalizeOperativeBalance(
      businessId: businessId,
      branchId: branchId,
      productId: 'reactive-filter',
      quantityOnHand: 6,
      quantityReserved: 0,
      quantityAvailable: 6,
      averageCost: null,
      lastMovementAt: DateTime.utc(2026, 9, 4, 1),
      deletedAt: null,
    );
    expect(await replenished, isEmpty);
  });

  test(
      'low-stock filter is inclusive, positive, and independent from exhausted stock',
      () async {
    await _insertProduct(
      database,
      id: 'normal',
      businessId: businessId,
      name: 'A normal',
      minimumStock: 5,
    );
    await _insertProduct(
      database,
      id: 'threshold',
      businessId: businessId,
      name: 'B en mínimo',
      minimumStock: 5,
    );
    await _insertProduct(
      database,
      id: 'below',
      businessId: businessId,
      name: 'C bajo mínimo',
      minimumStock: 5,
    );
    await _insertProduct(
      database,
      id: 'exhausted',
      businessId: businessId,
      name: 'D agotado',
      minimumStock: 5,
    );
    await _insertProduct(
      database,
      id: 'missing',
      businessId: businessId,
      name: 'E sin balance',
      minimumStock: 5,
    );
    await _insertProduct(
      database,
      id: 'zero-threshold',
      businessId: businessId,
      name: 'F mínimo cero',
      minimumStock: 0,
    );
    await _insertBalance(
      database,
      id: 'balance-normal',
      businessId: businessId,
      branchId: branchId,
      productId: 'normal',
      quantityOnHand: 6,
    );
    await _insertBalance(
      database,
      id: 'balance-threshold',
      businessId: businessId,
      branchId: branchId,
      productId: 'threshold',
      quantityOnHand: 5,
    );
    await _insertBalance(
      database,
      id: 'balance-below',
      businessId: businessId,
      branchId: branchId,
      productId: 'below',
      quantityOnHand: 1,
    );
    await _insertBalance(
      database,
      id: 'balance-exhausted-low-contract',
      businessId: businessId,
      branchId: branchId,
      productId: 'exhausted',
      quantityOnHand: 0,
    );
    await _insertBalance(
      database,
      id: 'balance-zero-threshold',
      businessId: businessId,
      branchId: branchId,
      productId: 'zero-threshold',
      quantityOnHand: 1,
    );

    final lowStock = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      stockFilter: InventoryProductStockFilter.lowStock,
      limit: null,
    );
    final outOfStock = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      stockFilter: InventoryProductStockFilter.outOfStock,
      limit: null,
    );

    expect(
      lowStock.map((product) => product['product_id']),
      ['threshold', 'below'],
    );
    expect(
      outOfStock.map((product) => product['product_id']),
      ['exhausted', 'missing'],
    );
    expect(
      lowStock.map((product) => product['product_id']),
      isNot(contains('zero-threshold')),
    );
  });

  test('low-stock filter is branch scoped and isolated by business', () async {
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(
            id: 'business-2',
            name: 'Otro negocio',
          ),
        );
    await _insertProduct(
      database,
      id: 'scoped-product',
      businessId: businessId,
      name: 'Producto scoped',
      minimumStock: 5,
    );
    await _insertProduct(
      database,
      id: 'other-business-product',
      businessId: 'business-2',
      name: 'Producto ajeno',
      minimumStock: 5,
    );
    await _insertBalance(
      database,
      id: 'scoped-product-a',
      businessId: businessId,
      branchId: branchId,
      productId: 'scoped-product',
      quantityOnHand: 10,
    );
    await _insertBalance(
      database,
      id: 'scoped-product-b',
      businessId: businessId,
      branchId: 'branch-2',
      productId: 'scoped-product',
      quantityOnHand: 3,
    );
    await _insertBalance(
      database,
      id: 'other-business-product-b',
      businessId: 'business-2',
      branchId: 'branch-2',
      productId: 'other-business-product',
      quantityOnHand: 1,
    );

    final principal = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      stockFilter: InventoryProductStockFilter.lowStock,
      limit: null,
    );
    final secondBranch = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: 'branch-2',
      stockFilter: InventoryProductStockFilter.lowStock,
      limit: null,
    );
    final otherBusiness = await dao.getProductsWithLocalStock(
      businessId: 'business-2',
      branchId: 'branch-2',
      stockFilter: InventoryProductStockFilter.lowStock,
      limit: null,
    );

    expect(principal, isEmpty);
    expect(secondBranch.single['product_id'], 'scoped-product');
    expect(otherBusiness.single['product_id'], 'other-business-product');
  });

  test('low-stock filter combines with name and barcode search', () async {
    await _insertProduct(
      database,
      id: 'rice-low',
      businessId: businessId,
      name: 'Arroz bajo',
      minimumStock: 5,
    );
    await _insertProduct(
      database,
      id: 'rice-normal',
      businessId: businessId,
      name: 'Arroz normal',
      minimumStock: 5,
    );
    await _insertProduct(
      database,
      id: 'coffee-low',
      businessId: businessId,
      name: 'Café bajo',
      minimumStock: 5,
    );
    await _insertBalance(
      database,
      id: 'rice-low-balance',
      businessId: businessId,
      branchId: branchId,
      productId: 'rice-low',
      quantityOnHand: 3,
    );
    await _insertBalance(
      database,
      id: 'rice-normal-balance',
      businessId: businessId,
      branchId: branchId,
      productId: 'rice-normal',
      quantityOnHand: 8,
    );
    await _insertBalance(
      database,
      id: 'coffee-low-balance',
      businessId: businessId,
      branchId: branchId,
      productId: 'coffee-low',
      quantityOnHand: 2,
    );
    await _insertBarcode(
      database,
      id: 'rice-low-code',
      businessId: businessId,
      productId: 'rice-low',
      barcode: 'LOW-003',
      normalized: 'LOW003',
    );

    final byName = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      searchTerm: 'Arroz',
      stockFilter: InventoryProductStockFilter.lowStock,
      limit: null,
    );
    final byBarcode = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      searchTerm: 'low-003',
      stockFilter: InventoryProductStockFilter.lowStock,
      limit: null,
    );

    expect(byName.single['product_id'], 'rice-low');
    expect(byBarcode.single['product_id'], 'rice-low');
  });

  test('low-stock stream reacts to stock crossing the inclusive threshold',
      () async {
    await _insertProduct(
      database,
      id: 'stock-reactive-low',
      businessId: businessId,
      name: 'Stock reactivo',
      minimumStock: 5,
    );
    await _insertBalance(
      database,
      id: 'stock-reactive-low-balance',
      businessId: businessId,
      branchId: branchId,
      productId: 'stock-reactive-low',
      quantityOnHand: 6,
    );
    final stream = dao.watchProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      stockFilter: InventoryProductStockFilter.lowStock,
      limit: null,
    );

    expect(await stream.first, isEmpty);
    final becameLow = stream.firstWhere((products) => products.isNotEmpty);
    await dao.finalizeOperativeBalance(
      businessId: businessId,
      branchId: branchId,
      productId: 'stock-reactive-low',
      quantityOnHand: 5,
      quantityReserved: 0,
      quantityAvailable: 5,
      averageCost: null,
      lastMovementAt: DateTime.utc(2026, 9, 4),
      deletedAt: null,
    );
    expect((await becameLow).single['product_id'], 'stock-reactive-low');

    final becameNormal = stream.firstWhere((products) => products.isEmpty);
    await dao.finalizeOperativeBalance(
      businessId: businessId,
      branchId: branchId,
      productId: 'stock-reactive-low',
      quantityOnHand: 8,
      quantityReserved: 0,
      quantityAvailable: 8,
      averageCost: null,
      lastMovementAt: DateTime.utc(2026, 9, 4, 1),
      deletedAt: null,
    );
    expect(await becameNormal, isEmpty);
  });

  test('low-stock stream reacts to minimum-stock changes in Products',
      () async {
    await _insertProduct(
      database,
      id: 'minimum-reactive-low',
      businessId: businessId,
      name: 'Mínimo reactivo',
      minimumStock: 3,
    );
    await _insertBalance(
      database,
      id: 'minimum-reactive-low-balance',
      businessId: businessId,
      branchId: branchId,
      productId: 'minimum-reactive-low',
      quantityOnHand: 4,
    );
    final stream = dao.watchProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      stockFilter: InventoryProductStockFilter.lowStock,
      limit: null,
    );

    expect(await stream.first, isEmpty);
    final becameLow = stream.firstWhere((products) => products.isNotEmpty);
    await (database.update(database.products)
          ..where((product) => product.id.equals('minimum-reactive-low')))
        .write(const ProductsCompanion(minimumStock: Value(5)));
    expect((await becameLow).single['product_id'], 'minimum-reactive-low');

    final becameNormal = stream.firstWhere((products) => products.isEmpty);
    await (database.update(database.products)
          ..where((product) => product.id.equals('minimum-reactive-low')))
        .write(const ProductsCompanion(minimumStock: Value(2)));
    expect(await becameNormal, isEmpty);
  });

  test('watch emits again when the scoped Drift balance changes', () async {
    await _insertProduct(
      database,
      id: 'reactive',
      businessId: businessId,
      name: 'Producto reactivo',
    );
    final quantities = dao
        .watchProductsWithLocalStock(
          businessId: businessId,
          branchId: branchId,
          limit: null,
        )
        .map((rows) => rows.single['quantity_on_hand']);
    final expectation = expectLater(
      quantities.take(2),
      emitsInOrder([0, 7]),
    );
    await Future<void>.delayed(Duration.zero);

    await _insertBalance(
      database,
      id: 'balance-reactive',
      businessId: businessId,
      branchId: branchId,
      productId: 'reactive',
      quantityOnHand: 7,
    );

    await expectation;
  });

  test('keeps an explicit result limit', () async {
    await _insertProducts(
      database,
      businessId: businessId,
      count: 3,
      idPrefix: 'limited',
    );

    final products = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      limit: 2,
    );

    expect(products, hasLength(2));
  });

  test('limit null returns more than one hundred visible products', () async {
    await _insertProducts(
      database,
      businessId: businessId,
      count: 101,
      idPrefix: 'unlimited',
    );

    final products = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      limit: null,
    );
    final streamedProducts = await dao
        .watchProductsWithLocalStock(
          businessId: businessId,
          branchId: branchId,
          limit: null,
        )
        .first;

    expect(products, hasLength(101));
    expect(streamedProducts, hasLength(101));
  });

  test('search supports empty terms and case-insensitive partial names',
      () async {
    await _insertProduct(
      database,
      id: 'rice',
      businessId: businessId,
      name: 'Arroz Integral',
    );
    await _insertProduct(
      database,
      id: 'coffee',
      businessId: businessId,
      name: 'Cafe Molido',
    );
    await _insertBalance(
      database,
      id: 'rice-principal',
      businessId: businessId,
      branchId: branchId,
      productId: 'rice',
      quantityOnHand: 6,
    );
    await _insertBalance(
      database,
      id: 'rice-vendemas',
      businessId: businessId,
      branchId: 'branch-2',
      productId: 'rice',
      quantityOnHand: 13,
    );

    final unfiltered = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      searchTerm: '   ',
      limit: null,
    );
    final filtered = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      searchTerm: ' RRoZ ',
      limit: null,
    );
    final filteredOtherBranch = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: 'branch-2',
      searchTerm: ' RRoZ ',
      limit: null,
    );

    expect(unfiltered, hasLength(2));
    expect(filtered.single['product_id'], 'rice');
    expect(filtered.single['quantity_on_hand'], 6);
    expect(filteredOtherBranch.single['product_id'], 'rice');
    expect(filteredOtherBranch.single['quantity_on_hand'], 13);
  });

  test('business barcodes search once per product and prioritize exact codes',
      () async {
    await _insertProduct(
      database,
      id: 'exact',
      businessId: businessId,
      name: 'Z producto exacto',
    );
    await _insertProduct(
      database,
      id: 'partial',
      businessId: businessId,
      name: 'A producto parcial',
    );
    await _insertBarcode(
      database,
      id: 'exact-primary',
      businessId: businessId,
      productId: 'exact',
      barcode: 'SKU-001',
      normalized: 'SKU001',
      barcodeType: 'local_sku',
    );
    await _insertBarcode(
      database,
      id: 'exact-secondary',
      businessId: businessId,
      productId: 'exact',
      barcode: 'ALT-001',
      normalized: 'ALT001',
      barcodeType: 'internal',
    );
    await _insertBarcode(
      database,
      id: 'partial-code',
      businessId: businessId,
      productId: 'partial',
      barcode: 'XX-SKU-001-YY',
      normalized: 'XXSKU001YY',
      barcodeType: 'internal',
    );

    final exactFirst = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      searchTerm: ' sku-001 ',
      limit: null,
    );
    final multipleCodeMatch = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      searchTerm: '001',
      limit: null,
    );

    expect(
      exactFirst.map((product) => product['product_id']),
      ['exact', 'partial'],
    );
    expect(
      multipleCodeMatch.map((product) => product['product_id']).toSet(),
      {'exact', 'partial'},
    );
    expect(multipleCodeMatch, hasLength(2));
  });

  test('barcode search excludes other businesses and inactive local rows',
      () async {
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(
            id: 'business-2',
            name: 'Otro negocio',
          ),
        );
    await _insertProduct(
      database,
      id: 'other-business-product',
      businessId: 'business-2',
      name: 'Producto ajeno',
    );
    await _insertProduct(
      database,
      id: 'visible-product',
      businessId: businessId,
      name: 'Producto visible',
    );
    await _insertProduct(
      database,
      id: 'inactive-code-product',
      businessId: businessId,
      name: 'Producto código inactivo',
    );
    await _insertProduct(
      database,
      id: 'deleted-code-product',
      businessId: businessId,
      name: 'Producto código eliminado',
    );
    await _insertBarcode(
      database,
      id: 'other-business-code',
      businessId: 'business-2',
      productId: 'other-business-product',
      barcode: 'PRIVATE-77',
      normalized: 'PRIVATE77',
    );
    await _insertBarcode(
      database,
      id: 'visible-code',
      businessId: businessId,
      productId: 'visible-product',
      barcode: 'PRIVATE-77',
      normalized: 'PRIVATE77',
    );
    await _insertBarcode(
      database,
      id: 'inactive-code',
      businessId: businessId,
      productId: 'inactive-code-product',
      barcode: 'PRIVATE-77',
      normalized: 'PRIVATE77',
      status: 'inactive',
    );
    await _insertBarcode(
      database,
      id: 'deleted-code',
      businessId: businessId,
      productId: 'deleted-code-product',
      barcode: 'PRIVATE-77',
      normalized: 'PRIVATE77',
      deletedAt: DateTime.utc(2026, 8, 1),
    );
    await database.into(database.localMasterProductsCatalog).insert(
          LocalMasterProductsCatalogCompanion.insert(
            id: 'master-only',
            name: const Value('Producto master sin alta local'),
          ),
        );
    await database.into(database.localProductBarcodes).insert(
          LocalProductBarcodesCompanion.insert(
            id: 'global-code',
            scope: 'global',
            masterProductId: const Value('master-only'),
            barcode: 'PRIVATE-77',
            barcodeNormalized: 'PRIVATE77',
          ),
        );
    await _insertBalance(
      database,
      id: 'visible-current-balance',
      businessId: businessId,
      branchId: branchId,
      productId: 'visible-product',
      quantityOnHand: 4,
    );
    await _insertBalance(
      database,
      id: 'visible-other-branch-balance',
      businessId: businessId,
      branchId: 'branch-2',
      productId: 'visible-product',
      quantityOnHand: 99,
    );

    final products = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      searchTerm: 'private-77',
      limit: null,
    );

    expect(products, hasLength(1));
    expect(products.single['product_id'], 'visible-product');
    expect(products.single['quantity_on_hand'], 4);
  });

  test('active search reacts when a local business barcode is created',
      () async {
    final match = dao
        .watchProductsWithLocalStock(
          businessId: businessId,
          branchId: branchId,
          searchTerm: 'new-123',
          limit: null,
        )
        .firstWhere((rows) => rows.isNotEmpty);
    await Future<void>.delayed(Duration.zero);

    await _insertProduct(
      database,
      id: 'new-product',
      businessId: businessId,
      name: 'Producto creado',
    );
    await _insertBarcode(
      database,
      id: 'new-code',
      businessId: businessId,
      productId: 'new-product',
      barcode: 'NEW-123',
      normalized: 'NEW123',
      barcodeType: 'internal',
    );

    final products = await match;
    expect(products.single['product_id'], 'new-product');
    expect(products.single['quantity_on_hand'], 0);
  });

  test('remote base upsert reconciles by scope and preserves local row ID',
      () async {
    await _insertProduct(
      database,
      id: 'product-p',
      businessId: businessId,
      name: 'Producto P',
    );
    await _insertBalance(
      database,
      id: 'random-local-uuid',
      businessId: businessId,
      branchId: branchId,
      productId: 'product-p',
      quantityOnHand: 8,
    );

    await dao.upsertRemoteBaseByScope(
      businessId: businessId,
      branchId: branchId,
      productId: 'product-p',
      remoteBalanceId: 'remote-123',
      remoteQuantityOnHand: 5,
      remoteQuantityReserved: 1,
      remoteQuantityAvailable: 4,
      remoteAverageCost: 1200,
      remoteSnapshotId: 'snapshot-1',
    );

    final rows = await database.customSelect(
      '''
      select * from local_product_stock_balances
      where business_id = ? and branch_id = ? and product_id = ?
      ''',
      variables: [
        const Variable<String>(businessId),
        const Variable<String>(branchId),
        const Variable<String>('product-p'),
      ],
    ).get();

    expect(rows, hasLength(1));
    expect(rows.single.read<String>('id'), 'random-local-uuid');
    expect(rows.single.read<int>('quantity_on_hand'), 8);
    expect(rows.single.read<String>('remote_balance_id'), 'remote-123');
    expect(rows.single.read<int>('remote_quantity_on_hand'), 5);
    expect(rows.single.read<int>('remote_quantity_reserved'), 1);
    expect(rows.single.read<int>('remote_quantity_available'), 4);
  });
}

Future<void> _insertProduct(
  AppDatabase database, {
  required String id,
  required String businessId,
  required String name,
  String? barcode,
  int legacyStock = 0,
  int minimumStock = 0,
  String status = 'active',
  DateTime? deletedAt,
}) {
  return database.into(database.products).insert(
        ProductsCompanion.insert(
          id: id,
          businessId: Value(businessId),
          barcode: Value(barcode),
          name: name,
          salePrice: 1000,
          stockQuantity: Value(legacyStock),
          minimumStock: Value(minimumStock),
          status: Value(status),
          deletedAt: Value(deletedAt),
        ),
      );
}

Future<void> _insertProducts(
  AppDatabase database, {
  required String businessId,
  required int count,
  required String idPrefix,
}) async {
  await database.batch((batch) {
    batch.insertAll(
      database.products,
      List.generate(
        count,
        (index) => ProductsCompanion.insert(
          id: '$idPrefix-$index',
          businessId: Value(businessId),
          name: 'Producto ${index.toString().padLeft(3, '0')}',
          salePrice: 1000,
        ),
      ),
    );
  });
}

Future<void> _insertBalance(
  AppDatabase database, {
  required String id,
  required String businessId,
  required String branchId,
  required String productId,
  required int quantityOnHand,
  int quantityReserved = 0,
  int? quantityAvailable,
  DateTime? deletedAt,
}) {
  return database.into(database.localProductStockBalances).insert(
        LocalProductStockBalancesCompanion.insert(
          id: id,
          businessId: businessId,
          branchId: branchId,
          productId: productId,
          quantityOnHand: Value(quantityOnHand),
          quantityReserved: Value(quantityReserved),
          quantityAvailable:
              Value(quantityAvailable ?? quantityOnHand - quantityReserved),
          deletedAt: Value(deletedAt),
        ),
      );
}

Future<void> _insertBarcode(
  AppDatabase database, {
  required String id,
  required String businessId,
  required String productId,
  required String barcode,
  required String normalized,
  String barcodeType = 'internal',
  String status = 'active',
  DateTime? deletedAt,
}) {
  return database.into(database.localProductBarcodes).insert(
        LocalProductBarcodesCompanion.insert(
          id: id,
          scope: 'business',
          businessId: Value(businessId),
          productId: Value(productId),
          barcode: barcode,
          barcodeNormalized: normalized,
          barcodeType: Value(barcodeType),
          status: Value(status),
          deletedAt: Value(deletedAt),
        ),
      );
}
