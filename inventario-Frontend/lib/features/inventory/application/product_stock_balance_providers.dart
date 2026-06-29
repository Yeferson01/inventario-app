import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/product_stock_balance_local_dao.dart';
import '../data/datasources/product_stock_balance_remote_datasource.dart';
import 'product_stock_balance_pull_service.dart';

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
