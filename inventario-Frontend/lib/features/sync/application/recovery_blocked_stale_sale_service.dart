import '../../sales/data/datasources/pos_local_sale_dao.dart';
import 'operational_bootstrap_orchestration_models.dart';
import 'productive_stale_sale_reconciliation_service.dart';

typedef RecoveryStaleSaleLoader = Future<List<StaleSaleResolutionCandidate>>
    Function({
  required String profileId,
  required String businessId,
  required String branchId,
});

typedef RecoverySaleMovementLoader = Future<List<Map<String, dynamic>>>
    Function({required String saleId});

class RecoveryBlockedStaleSaleAssessment {
  const RecoveryBlockedStaleSaleAssessment({
    required this.sales,
    required this.saleIssues,
    required this.relatedInventoryIssues,
    required this.hardIssues,
  });

  final List<StaleSaleResolutionCandidate> sales;
  final List<OperationalBootstrapBlockingIssue> saleIssues;
  final List<OperationalBootstrapBlockingIssue> relatedInventoryIssues;
  final List<OperationalBootstrapBlockingIssue> hardIssues;

  bool get canReviewSales => sales.isNotEmpty && saleIssues.isNotEmpty;
  bool get isExclusivelyActionable => canReviewSales && hardIssues.isEmpty;
}

class RecoveryBlockedStaleSaleAssessmentService {
  RecoveryBlockedStaleSaleAssessmentService({
    required RecoveryStaleSaleLoader loadPendingSales,
    required RecoverySaleMovementLoader loadSaleMovements,
  })  : _loadPendingSales = loadPendingSales,
        _loadSaleMovements = loadSaleMovements;

  final RecoveryStaleSaleLoader _loadPendingSales;
  final RecoverySaleMovementLoader _loadSaleMovements;

  Future<RecoveryBlockedStaleSaleAssessment> assess({
    required String profileId,
    required String businessId,
    required String branchId,
    required List<OperationalBootstrapBlockingIssue> blockingIssues,
  }) async {
    final pending = await _loadPendingSales(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
    final candidatesBySaleId = {
      for (final candidate in pending)
        if (candidate.businessId == businessId &&
            candidate.branchId == branchId &&
            candidate.syncConflictId?.trim().isNotEmpty == true)
          candidate.saleId: candidate,
    };

    final saleIssues = <OperationalBootstrapBlockingIssue>[];
    final actionableSaleIds = <String>{};
    for (final issue in blockingIssues) {
      final saleId = issue.entityId;
      final explicitRule = issue.metadata['remote_rule']?.toString();
      final candidate = saleId == null ? null : candidatesBySaleId[saleId];
      final ruleIsProven = explicitRule == 'sale_cash_session_invalid' ||
          (explicitRule == null &&
              candidate?.syncConflictId?.trim().isNotEmpty == true);
      if (issue.domain == 'cash_pos' &&
          issue.entityType == 'sales' &&
          issue.issueType == 'sale_cash_session_rejected' &&
          issue.metadata['remote_reason']?.toString() == 'closed' &&
          ruleIsProven &&
          saleId != null &&
          candidate != null) {
        // Legacy local issues did not persist remote_rule. Their conflict id
        // still came from the datasource query filtered by this exact rule.
        saleIssues.add(issue);
        actionableSaleIds.add(saleId);
      }
    }

    final relatedMovementIds = <String>{};
    for (final saleId in actionableSaleIds) {
      final movements = await _loadSaleMovements(saleId: saleId);
      for (final movement in movements) {
        if (movement['business_id']?.toString() == businessId &&
            movement['branch_id']?.toString() == branchId &&
            movement['source_type']?.toString() == 'sale' &&
            movement['source_id']?.toString() == saleId) {
          final movementId = movement['id']?.toString().trim();
          if (movementId != null && movementId.isNotEmpty) {
            relatedMovementIds.add(movementId);
          }
        }
      }
    }

    final relatedInventory = <OperationalBootstrapBlockingIssue>[];
    final hard = <OperationalBootstrapBlockingIssue>[];
    for (final issue in blockingIssues) {
      if (saleIssues.contains(issue)) continue;
      if (issue.domain == 'inventory_balance' &&
          issue.entityType == 'inventory_movements' &&
          issue.entityId != null &&
          relatedMovementIds.contains(issue.entityId)) {
        relatedInventory.add(issue);
      } else {
        hard.add(issue);
      }
    }

    return RecoveryBlockedStaleSaleAssessment(
      sales: List.unmodifiable(
        actionableSaleIds.map((saleId) => candidatesBySaleId[saleId]!),
      ),
      saleIssues: List.unmodifiable(saleIssues),
      relatedInventoryIssues: List.unmodifiable(relatedInventory),
      hardIssues: List.unmodifiable(hard),
    );
  }
}
