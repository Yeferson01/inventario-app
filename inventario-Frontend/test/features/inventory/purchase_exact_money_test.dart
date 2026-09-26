import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_models.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_local_service.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_money.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/purchase_local_dao.dart';

void main() {
  test('decimal text becomes exact cents without rounding', () {
    expect(parsePurchaseMoneyCents('2500'), BigInt.from(250000));
    expect(parsePurchaseMoneyCents('2500.5'), BigInt.from(250050));
    expect(parsePurchaseMoneyCents('2500.50'), BigInt.from(250050));
    expect(parsePurchaseMoneyCents('2500,50'), BigInt.from(250050));
    expect(parsePurchaseMoneyCents('0'), BigInt.zero);
    expect(parsePurchaseMoneyCents('2500.125'), isNull);
    expect(parsePurchaseMoneyCents('-1'), isNull);
    expect(parsePurchaseMoneyCents('abc'), isNull);
    expect(parsePurchaseMoneyCents('10000000000'), isNull);
    expect(formatPurchaseMoneyCents(BigInt.from(250050)), '2500.50');
    expect(purchaseLineTotalCents(BigInt.from(250050), 2), BigInt.from(500100));
    expect(() => purchaseLineTotalCents(BigInt.from(999999999999), 2),
        throwsRangeError);
  });

  test('purchase finalizes exact total only after items and stock commit',
      () async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(id: 'business', name: 'Business'),
        );
    await database.into(database.branches).insert(
          BranchesCompanion.insert(
              id: 'branch', businessId: 'business', name: 'Branch'),
        );
    await database.into(database.profiles).insert(
          ProfilesCompanion.insert(id: 'profile'),
        );
    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: 'product',
            businessId: const Value('business'),
            name: 'Product',
            salePrice: 6000,
          ),
        );
    final service = PurchaseLocalService(dao: PurchaseLocalDao(database));
    final result = await service.createLocalPurchase(CreatePurchaseLocalInput(
      businessId: 'business',
      branchId: 'branch',
      profileId: 'profile',
      items: [
        PurchaseLocalItemInput(
          productId: 'product',
          quantity: 2,
          unitCostCents: BigInt.from(250050),
        )
      ],
    ));
    expect(result.totalCents, BigInt.from(500100));
    final basis = await service.getPaymentBasis(
      purchaseId: result.purchaseId,
      businessId: 'business',
      branchId: 'branch',
    );
    expect(basis?.paymentEligible, isTrue);
    expect(basis?.totalCents, BigInt.from(500100));
    expect(basis?.contractVersion, 'exact_v1');
    final item = await database.customSelect(
      'select unit_cost_cents, subtotal_cents from purchase_items where purchase_id = ?',
      variables: [Variable<String>(result.purchaseId)],
    ).getSingle();
    expect(item.read<int>('unit_cost_cents'), 250050);
    expect(item.read<int>('subtotal_cents'), 500100);
    final movement = await database.customSelect(
      'select unit_cost from local_inventory_movements where source_id = ?',
      variables: [Variable<String>(result.purchaseId)],
    ).getSingle();
    expect(movement.read<double>('unit_cost'), 2500.50);
    final balance = await database
        .customSelect(
          "select quantity_on_hand, average_cost from local_product_stock_balances where product_id = 'product'",
        )
        .getSingle();
    expect(balance.read<int>('quantity_on_hand'), 2);
    expect(balance.read<double>('average_cost'), 2500.50);
  });

  test('legacy REAL purchase cannot become payment-eligible by approximation',
      () async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(id: 'business', name: 'Business'),
        );
    await database.into(database.branches).insert(
          BranchesCompanion.insert(
              id: 'branch', businessId: 'business', name: 'Branch'),
        );
    await database.customStatement('''
      insert into purchases (id, business_id, branch_id, total, status)
      values ('legacy', 'business', 'branch', 19.99, 'completed')
    ''');
    final basis = await PurchaseLocalService(
      dao: PurchaseLocalDao(database),
    ).getPaymentBasis(
        purchaseId: 'legacy', businessId: 'business', branchId: 'branch');
    expect(basis?.totalCents, isNull);
    expect(basis?.financiallyFinalized, isFalse);
    expect(basis?.paymentEligible, isFalse);
  });
}
