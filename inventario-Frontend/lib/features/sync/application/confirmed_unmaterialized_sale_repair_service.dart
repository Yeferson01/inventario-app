import '../../sales/data/datasources/pos_local_sale_dao.dart';
import '../data/datasources/pos_sync_remote_datasource.dart';

typedef DurableDiscardEvidenceLoader
    = Future<List<DurableUnmaterializedSaleDiscardEvidence>> Function({
  required String profileId,
  required String businessId,
  required String branchId,
});

typedef OpenDiscardConflictResolver = Future<String?> Function({
  required String businessId,
  required String branchId,
  required String appDeviceId,
  required String saleId,
});

typedef ConfirmedDiscardRemoteFinalizer = Future<SaleDidNotOccurRemoteResult>
    Function({
  required String businessId,
  required String branchId,
  required String appDeviceId,
  required String saleId,
  required String syncConflictId,
  required String idempotencyKey,
  required String reason,
});

class ConfirmedUnmaterializedSaleRepairResult {
  const ConfirmedUnmaterializedSaleRepairResult({
    required this.candidatesChecked,
    required this.conflictsFinalized,
  });

  final int candidatesChecked;
  final int conflictsFinalized;
}

/// Completes only the missing remote half of a previously committed local
/// did-not-occur decision. It never mutates local sales, stock or outbox.
class ConfirmedUnmaterializedSaleRepairService {
  const ConfirmedUnmaterializedSaleRepairService({
    required DurableDiscardEvidenceLoader evidenceLoader,
    required OpenDiscardConflictResolver conflictResolver,
    required ConfirmedDiscardRemoteFinalizer remoteFinalizer,
  })  : _evidenceLoader = evidenceLoader,
        _conflictResolver = conflictResolver,
        _remoteFinalizer = remoteFinalizer;

  final DurableDiscardEvidenceLoader _evidenceLoader;
  final OpenDiscardConflictResolver _conflictResolver;
  final ConfirmedDiscardRemoteFinalizer _remoteFinalizer;

  Future<ConfirmedUnmaterializedSaleRepairResult> repair({
    required String profileId,
    required String businessId,
    required String branchId,
    required String appDeviceId,
  }) async {
    if ([profileId, businessId, branchId, appDeviceId]
        .any((value) => value.trim().isEmpty)) {
      throw ArgumentError(
        'Profile, business, branch and appDevice are required for repair.',
      );
    }
    final evidence = await _evidenceLoader(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
    var finalized = 0;
    for (final item in evidence) {
      final conflictId = item.syncConflictId ??
          await _conflictResolver(
            businessId: businessId,
            branchId: branchId,
            appDeviceId: appDeviceId,
            saleId: item.saleId,
          );
      if (conflictId == null || conflictId.trim().isEmpty) continue;
      final normalizedConflictId = conflictId.trim();
      final result = await _remoteFinalizer(
        businessId: businessId,
        branchId: branchId,
        appDeviceId: appDeviceId,
        saleId: item.saleId,
        syncConflictId: normalizedConflictId,
        idempotencyKey:
            'sale-did-not-occur:${item.saleId}:$normalizedConflictId',
        reason: item.reason,
      );
      if (result.businessId != businessId ||
          result.branchId != branchId ||
          result.saleId != item.saleId ||
          result.syncConflictId != normalizedConflictId ||
          result.status != 'resolved' ||
          result.resolutionStrategy != 'sale_did_not_occur') {
        throw StateError(
          'Remote did-not-occur repair returned a mismatched result.',
        );
      }
      finalized++;
    }
    return ConfirmedUnmaterializedSaleRepairResult(
      candidatesChecked: evidence.length,
      conflictsFinalized: finalized,
    );
  }
}
