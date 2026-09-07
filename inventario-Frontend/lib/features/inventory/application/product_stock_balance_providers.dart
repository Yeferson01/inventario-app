import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/product_stock_balance_local_dao.dart';
import '../data/datasources/product_stock_balance_remote_datasource.dart';
import 'inventory_valuation_models.dart';
import 'product_stock_balance_pull_service.dart';

export '../data/datasources/product_stock_balance_local_dao.dart'
    show InventoryProductStockFilter;

class ProductStockBalanceKey {
  const ProductStockBalanceKey({
    required this.businessId,
    required this.branchId,
    required this.productId,
  });

  final String businessId;
  final String branchId;
  final String productId;

  @override
  bool operator ==(Object other) {
    return other is ProductStockBalanceKey &&
        other.businessId == businessId &&
        other.branchId == branchId &&
        other.productId == productId;
  }

  @override
  int get hashCode => Object.hash(
        businessId,
        branchId,
        productId,
      );
}

class ProductsWithLocalStockKey {
  const ProductsWithLocalStockKey({
    required this.businessId,
    required this.branchId,
    this.searchTerm = '',
    this.stockFilter = InventoryProductStockFilter.all,
    this.limit = 100,
  });

  final String businessId;
  final String branchId;
  final String searchTerm;
  final InventoryProductStockFilter stockFilter;
  final int? limit;

  @override
  bool operator ==(Object other) {
    return other is ProductsWithLocalStockKey &&
        other.businessId == businessId &&
        other.branchId == branchId &&
        other.searchTerm == searchTerm &&
        other.stockFilter == stockFilter &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(
        businessId,
        branchId,
        searchTerm,
        stockFilter,
        limit,
      );
}

class InventoryAlertSummaryKey {
  const InventoryAlertSummaryKey({
    required this.businessId,
    required this.branchId,
  });

  final String businessId;
  final String branchId;

  @override
  bool operator ==(Object other) {
    return other is InventoryAlertSummaryKey &&
        other.businessId == businessId &&
        other.branchId == branchId;
  }

  @override
  int get hashCode => Object.hash(businessId, branchId);
}

class InventoryAlertSummary {
  const InventoryAlertSummary({
    required this.outOfStockCount,
    required this.lowStockCount,
  });

  final int outOfStockCount;
  final int lowStockCount;
}

class InventoryValuationSummaryKey {
  const InventoryValuationSummaryKey({
    required this.businessId,
    required this.branchId,
  });

  final String businessId;
  final String branchId;

  @override
  bool operator ==(Object other) {
    return other is InventoryValuationSummaryKey &&
        other.businessId == businessId &&
        other.branchId == branchId;
  }

  @override
  int get hashCode => Object.hash(businessId, branchId);
}

final productStockBalanceLocalDaoProvider =
    Provider<ProductStockBalanceLocalDao>((ref) {
  final db = ref.watch(appDatabaseProvider);

  return ProductStockBalanceLocalDao(db);
});

final productStockBalanceRemoteDataSourceProvider =
    Provider<ProductStockBalanceRemoteDataSource>((ref) {
  final client = ref.watch(supabaseClientProvider);

  return ProductStockBalanceRemoteDataSource(client);
});

final productStockBalancePullServiceProvider =
    Provider<ProductStockBalancePullService>((ref) {
  return ProductStockBalancePullService(
    remoteDataSource: ref.watch(productStockBalanceRemoteDataSourceProvider),
    localDao: ref.watch(productStockBalanceLocalDaoProvider),
  );
});

final localProductStockBalanceProvider =
    StreamProvider.family<Map<String, dynamic>?, ProductStockBalanceKey>(
        (ref, key) {
  final dao = ref.watch(productStockBalanceLocalDaoProvider);

  return dao.watchProductBalance(
    businessId: key.businessId,
    branchId: key.branchId,
    productId: key.productId,
  );
});

final localProductsWithStockProvider = StreamProvider.family<
    List<Map<String, dynamic>>, ProductsWithLocalStockKey>((ref, key) {
  final dao = ref.watch(productStockBalanceLocalDaoProvider);

  return dao
      .watchProductsWithLocalStock(
        businessId: key.businessId,
        branchId: key.branchId,
        searchTerm: key.searchTerm,
        stockFilter: key.stockFilter,
        limit: key.limit,
      )
      .map(
        (rows) => rows
            .map(
              (row) => <String, dynamic>{
                ...row,
                'inventory_valuation': InventoryProductValuation.fromStock(
                  quantityOnHand: _intValue(row['quantity_on_hand']),
                  averageCost: row['stock_average_cost'],
                ),
              },
            )
            .toList(growable: false),
      );
});

final inventoryAlertSummaryProvider =
    StreamProvider.family<InventoryAlertSummary, InventoryAlertSummaryKey>(
        (ref, key) {
  final dao = ref.watch(productStockBalanceLocalDaoProvider);

  return dao
      .watchInventoryAlertCounts(
        businessId: key.businessId,
        branchId: key.branchId,
      )
      .map(
        (counts) => InventoryAlertSummary(
          outOfStockCount: counts['out_of_stock_count'] ?? 0,
          lowStockCount: counts['low_stock_count'] ?? 0,
        ),
      );
});

final inventoryValuationSummaryProvider = StreamProvider.family<
    InventoryValuationSummary, InventoryValuationSummaryKey>((ref, key) {
  final dao = ref.watch(productStockBalanceLocalDaoProvider);
  return dao
      .watchBranchInventoryValuationInputs(
        businessId: key.businessId,
        branchId: key.branchId,
      )
      .map(InventoryValuationSummary.fromRows);
});

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
