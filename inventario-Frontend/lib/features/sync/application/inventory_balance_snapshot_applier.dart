import '../../inventory/data/datasources/product_stock_balance_local_dao.dart';
import '../data/models/inventory_balance_reconciliation_models.dart';
import '../data/models/operational_bootstrap_models.dart';
import 'operational_bootstrap_page_applier.dart';

class InventoryBalanceSnapshotApplier
    implements OperationalBootstrapPageApplier {
  InventoryBalanceSnapshotApplier({
    required ProductStockBalanceLocalDao balanceDao,
  }) : _balanceDao = balanceDao;

  final ProductStockBalanceLocalDao _balanceDao;

  @override
  Future<OperationalBootstrapPageApplyResult> applyPage({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  }) async {
    if (snapshot.bundle != 'product_operational' ||
        page.dataset != 'product_stock_balances') {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message: 'Inventory balance applier received an unsupported dataset.',
      );
    }
    final seen = <String>[];
    for (final row in page.rows) {
      final balance = InventoryBalanceSnapshotRow.fromBootstrapRow(row);
      if (balance.businessId != snapshot.businessId ||
          balance.branchId != snapshot.branchId) {
        throw const OperationalBootstrapException(
          kind: OperationalBootstrapFailureKind.scopeMismatch,
          message: 'Inventory balance row belongs to another scope.',
        );
      }
      await _balanceDao.stageRemoteBaseByScope(
        businessId: balance.businessId,
        branchId: balance.branchId,
        productId: balance.productId,
        remoteBalanceId: balance.remoteBalanceId,
        remoteQuantityOnHand: balance.quantityOnHand,
        remoteQuantityReserved: balance.quantityReserved,
        remoteQuantityAvailable: balance.quantityAvailable,
        remoteAverageCost: balance.averageCost,
        remoteUpdatedAt: balance.remoteUpdatedAt,
        remoteSnapshotId: snapshot.snapshotId,
        remoteTombstone: balance.isTombstone,
        remoteDeletedAt: balance.remoteDeletedAt,
      );
      seen.add(balance.semanticIdentity);
    }
    return OperationalBootstrapPageApplyResult(
      seenEntityIds: seen,
      completeConvergenceStatus: 'pending',
    );
  }
}
