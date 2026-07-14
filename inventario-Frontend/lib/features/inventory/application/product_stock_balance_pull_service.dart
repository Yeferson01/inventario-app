import '../data/datasources/product_stock_balance_local_dao.dart';
import '../data/datasources/product_stock_balance_remote_datasource.dart';
import '../data/models/product_stock_balance_models.dart';

class ProductStockBalancePullService {
  ProductStockBalancePullService({
    required ProductStockBalanceRemoteDataSource remoteDataSource,
    required ProductStockBalanceLocalDao localDao,
  })  : _remoteDataSource = remoteDataSource,
        _localDao = localDao;

  final ProductStockBalanceRemoteDataSource _remoteDataSource;
  final ProductStockBalanceLocalDao _localDao;

  Future<ProductStockBalancePullResult> pullBranchBalances({
    required String businessId,
    required String branchId,
    int limit = 1000,
  }) async {
    final pulledAt = DateTime.now().toUtc();

    final balances = await _remoteDataSource.pullBranchBalances(
      businessId: businessId,
      branchId: branchId,
      limit: limit,
    );

    var upserted = 0;

    for (final balance in balances) {
      await _localDao.upsertRemoteBalance(balance);
      upserted++;
    }

    return ProductStockBalancePullResult(
      businessId: businessId,
      branchId: branchId,
      remoteCount: balances.length,
      localUpserted: upserted,
      pulledAt: pulledAt,
    );
  }

  Future<Map<String, dynamic>?> getLocalProductBalance({
    required String businessId,
    required String branchId,
    required String productId,
  }) {
    return _localDao.getProductBalance(
      businessId: businessId,
      branchId: branchId,
      productId: productId,
    );
  }
}
