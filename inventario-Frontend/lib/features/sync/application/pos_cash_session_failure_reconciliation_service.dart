import 'dart:convert';

import '../data/datasources/pos_sync_remote_datasource.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/models/local_recovery_models.dart';

class PosCashSessionFailureReconciliationService {
  PosCashSessionFailureReconciliationService({
    required ReconciliationIssueLocalDao issueDao,
  }) : _issueDao = issueDao;

  final ReconciliationIssueLocalDao _issueDao;

  Future<int> recordFailures({
    required String profileId,
    required String businessId,
    required String branchId,
    required List<PosCashSessionApplyFailure> failures,
  }) async {
    var recorded = 0;
    for (final failure in failures) {
      if (failure.reason != 'closed') {
        continue;
      }
      await _issueDao.openOrUpdateIssue(
        ReconciliationIssueDraft(
          profileId: profileId,
          businessId: businessId,
          branchId: branchId,
          domain: 'cash_pos',
          entityType: 'sales',
          entityId: failure.saleId,
          issueType: 'sale_cash_session_rejected',
          severity: 'blocking',
          message:
              'Hosted rechazó la venta porque su sesión de caja ya no es válida; la venta local se conserva para reconciliación.',
          metadataJson: jsonEncode({
            'sale_id': failure.saleId,
            'cash_session_id': failure.cashSessionId,
            'cash_register_id': failure.cashRegisterId,
            'branch_id': failure.branchId ?? branchId,
            'server_sync_batch_id': failure.serverBatchId,
            'server_sync_mutation_id': failure.serverMutationId,
            'sync_conflict_id': failure.syncConflictId,
            'remote_rule': 'sale_cash_session_invalid',
            'remote_reason': failure.reason,
            'remote_error': failure.message,
          }),
        ),
      );
      recorded++;
    }
    return recorded;
  }
}
