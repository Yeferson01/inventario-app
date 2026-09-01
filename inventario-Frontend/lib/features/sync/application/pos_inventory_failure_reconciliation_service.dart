import 'dart:convert';

import '../../sales/data/datasources/pos_local_sale_dao.dart';
import '../data/datasources/pos_sync_remote_datasource.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/models/local_recovery_models.dart';

class PosInventoryFailureReconciliationService {
  PosInventoryFailureReconciliationService({
    required PosLocalSaleDao saleDao,
    required ReconciliationIssueLocalDao issueDao,
  })  : _saleDao = saleDao,
        _issueDao = issueDao;

  final PosLocalSaleDao _saleDao;
  final ReconciliationIssueLocalDao _issueDao;

  Future<int> recordFailures({
    required String profileId,
    required String businessId,
    required String branchId,
    required List<PosInventoryApplyFailure> failures,
  }) async {
    var recorded = 0;
    for (final failure in failures) {
      final movements = await _saleDao.getSaleInventoryMovementsForSyncContext(
        saleId: failure.saleId,
      );
      for (final movement in movements) {
        final movementId = movement['id']?.toString();
        final productId = movement['product_id']?.toString();
        if (movementId == null || productId == null) continue;
        await _issueDao.openOrUpdateIssue(
          ReconciliationIssueDraft(
            profileId: profileId,
            businessId: businessId,
            branchId: branchId,
            domain: 'inventory_balance',
            entityType: 'inventory_movements',
            entityId: movementId,
            issueType: 'inventory_movement_rejected',
            severity: 'blocking',
            message:
                'Hosted rechazó el efecto de inventario de la venta; la venta se conserva y requiere reconciliación.',
            metadataJson: jsonEncode({
              'sale_id': failure.saleId,
              'movement_id': movementId,
              'product_id': productId,
              'branch_id': branchId,
              'server_sync_batch_id': failure.serverBatchId,
              'remote_error': failure.message,
            }),
          ),
        );
        recorded++;
      }
    }
    return recorded;
  }
}
