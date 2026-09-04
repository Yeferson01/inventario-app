import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/inventory/application/product_stock_balance_providers.dart';

void main() {
  test('ProductsWithLocalStockKey includes nullable limit in its identity', () {
    const unlimited = ProductsWithLocalStockKey(
      businessId: 'business-1',
      branchId: 'branch-1',
      limit: null,
    );
    const sameUnlimited = ProductsWithLocalStockKey(
      businessId: 'business-1',
      branchId: 'branch-1',
      limit: null,
    );
    const limited = ProductsWithLocalStockKey(
      businessId: 'business-1',
      branchId: 'branch-1',
    );

    expect(unlimited, sameUnlimited);
    expect(unlimited.hashCode, sameUnlimited.hashCode);
    expect(unlimited, isNot(limited));
    expect(limited.limit, 100);
  });

  test('ProductsWithLocalStockKey includes stock filter in its identity', () {
    const all = ProductsWithLocalStockKey(
      businessId: 'business-1',
      branchId: 'branch-1',
    );
    const outOfStock = ProductsWithLocalStockKey(
      businessId: 'business-1',
      branchId: 'branch-1',
      stockFilter: InventoryProductStockFilter.outOfStock,
    );

    expect(all, isNot(outOfStock));
    expect(outOfStock.stockFilter, InventoryProductStockFilter.outOfStock);
  });
}
