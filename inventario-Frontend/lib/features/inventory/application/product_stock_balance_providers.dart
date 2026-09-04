import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/product_stock_balance_local_dao.dart';
import '../data/datasources/product_stock_balance_remote_datasource.dart';
import 'product_stock_balance_pull_service.dart';

enum InventoryProductStockFilter {
  all,
  outOfStock,
}

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

  return dao.watchProductsWithLocalStock(
    businessId: key.businessId,
    branchId: key.branchId,
    searchTerm: key.searchTerm,
    outOfStockOnly: key.stockFilter == InventoryProductStockFilter.outOfStock,
    limit: key.limit,
  );
});
