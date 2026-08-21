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
    );
    await _insertProduct(
      database,
      id: 'product-b',
      businessId: 'business-2',
      name: 'Producto B',
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

    final products = await dao.getProductsWithLocalStock(
      businessId: businessId,
      branchId: branchId,
      limit: null,
    );

    expect(products, hasLength(1));
    expect(products.single['product_id'], 'product-a');
    expect(products.single['quantity_on_hand'], 4);
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
  DateTime? deletedAt,
}) {
  return database.into(database.localProductStockBalances).insert(
        LocalProductStockBalancesCompanion.insert(
          id: id,
          businessId: businessId,
          branchId: branchId,
          productId: productId,
          quantityOnHand: Value(quantityOnHand),
          quantityAvailable: Value(quantityOnHand),
          deletedAt: Value(deletedAt),
        ),
      );
}
