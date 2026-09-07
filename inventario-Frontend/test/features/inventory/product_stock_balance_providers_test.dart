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
    const lowStock = ProductsWithLocalStockKey(
      businessId: 'business-1',
      branchId: 'branch-1',
      stockFilter: InventoryProductStockFilter.lowStock,
    );

    expect(all, isNot(outOfStock));
    expect(all, isNot(lowStock));
    expect(outOfStock, isNot(lowStock));
    expect(outOfStock.stockFilter, InventoryProductStockFilter.outOfStock);
    expect(lowStock.stockFilter, InventoryProductStockFilter.lowStock);
  });

  test('inventory alert summary key is scoped by business and branch', () {
    const branchA = InventoryAlertSummaryKey(
      businessId: 'business-1',
      branchId: 'branch-a',
    );
    const sameBranchA = InventoryAlertSummaryKey(
      businessId: 'business-1',
      branchId: 'branch-a',
    );
    const branchB = InventoryAlertSummaryKey(
      businessId: 'business-1',
      branchId: 'branch-b',
    );
    expect(branchA, sameBranchA);
    expect(branchA.hashCode, sameBranchA.hashCode);
    expect(branchA, isNot(branchB));
  });

  test('inventory valuation summary key is scoped by business and branch', () {
    const branchA = InventoryValuationSummaryKey(
      businessId: 'business-1',
      branchId: 'branch-a',
    );
    const sameBranchA = InventoryValuationSummaryKey(
      businessId: 'business-1',
      branchId: 'branch-a',
    );
    const branchB = InventoryValuationSummaryKey(
      businessId: 'business-1',
      branchId: 'branch-b',
    );
    const otherBusiness = InventoryValuationSummaryKey(
      businessId: 'business-2',
      branchId: 'branch-a',
    );

    expect(branchA, sameBranchA);
    expect(branchA.hashCode, sameBranchA.hashCode);
    expect(branchA, isNot(branchB));
    expect(branchA, isNot(otherBusiness));
  });
}
