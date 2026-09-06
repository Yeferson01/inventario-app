import '../data/datasources/purchases_sync_remote_datasource.dart';
import '../data/datasources/recovery_blocked_purchase_retry_local_dao.dart';
import 'operational_bootstrap_orchestration_models.dart';

abstract class RecoveryBlockedPurchaseRetryGateway {
  Future<RecoveryBlockedPurchaseCandidate?> findCandidate(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String movementId});
  Future<PurchasePermissionRetryEvidence> inspect(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId});
  Future<bool> prepareLocalRetry(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId});
  Future<String?> enqueue(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId});
  Future<bool> upload(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String localBatchId});
  Future<PurchasePermissionRetryEvidence> finalize(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId});
  Future<void> reconcileInventory(
      {required RecoveryBlockedPurchaseRetryScope scope});
  Future<bool> isPurchaseLocallyConverged(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId});
  Future<bool> isTargetIssueOpen(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String movementId});
}

class RecoveryBlockedPurchaseRetryScope {
  const RecoveryBlockedPurchaseRetryScope(
      {required this.profileId,
      required this.businessId,
      required this.branchId,
      required this.appDeviceId,
      required this.installationId,
      required this.effectivePermissions});
  final String profileId;
  final String businessId;
  final String branchId;
  final String appDeviceId;
  final String installationId;
  final Set<String> effectivePermissions;
}

class RecoveryBlockedPurchaseRetryAssessment {
  const RecoveryBlockedPurchaseRetryAssessment(
      {required this.candidate,
      required this.evidence,
      required this.hardIssues});
  final RecoveryBlockedPurchaseCandidate? candidate;
  final PurchasePermissionRetryEvidence? evidence;
  final List<OperationalBootstrapBlockingIssue> hardIssues;
  bool get canRetry => candidate != null && evidence?.safeToRetry == true;
}

class RecoveryBlockedPurchaseRetryResult {
  const RecoveryBlockedPurchaseRetryResult(
      {required this.purchaseId,
      required this.remoteAlreadyMaterialized,
      required this.localBatchId,
      required this.remainingHardIssues});
  final String purchaseId;
  final bool remoteAlreadyMaterialized;
  final String? localBatchId;
  final int remainingHardIssues;
}

class RecoveryBlockedPurchaseRetryException implements Exception {
  const RecoveryBlockedPurchaseRetryException(this.message);
  final String message;
  @override
  String toString() => 'RecoveryBlockedPurchaseRetryException: $message';
}

class RecoveryBlockedPurchaseRetryService {
  RecoveryBlockedPurchaseRetryService(
      {required String? Function() authenticatedProfileId,
      required RecoveryBlockedPurchaseRetryGateway gateway})
      : _authenticatedProfileId = authenticatedProfileId,
        _gateway = gateway;
  final String? Function() _authenticatedProfileId;
  final RecoveryBlockedPurchaseRetryGateway _gateway;
  final Map<String, Future<RecoveryBlockedPurchaseRetryResult>> _inFlight = {};

  Future<RecoveryBlockedPurchaseRetryAssessment> assess(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required List<OperationalBootstrapBlockingIssue> blockingIssues}) async {
    _validateScope(scope);
    if (!scope.effectivePermissions.contains('inventory.purchase')) {
      return RecoveryBlockedPurchaseRetryAssessment(
          candidate: null,
          evidence: null,
          hardIssues: List.unmodifiable(blockingIssues));
    }
    RecoveryBlockedPurchaseCandidate? candidate;
    PurchasePermissionRetryEvidence? evidence;
    final causalIssues = <OperationalBootstrapBlockingIssue>{};
    for (final issue in blockingIssues) {
      if (issue.issueType != 'inventory_movement_rejected' ||
          issue.domain != 'inventory_balance' ||
          issue.entityType != 'inventory_movements' ||
          issue.entityId == null) {
        continue;
      }
      final local = await _gateway.findCandidate(
          scope: scope, movementId: issue.entityId!);
      if (local == null) {
        continue;
      }
      final remote =
          await _gateway.inspect(scope: scope, purchaseId: local.purchaseId);
      if (!remote.safeToRetry) {
        continue;
      }
      if (candidate != null && candidate.purchaseId != local.purchaseId) {
        return RecoveryBlockedPurchaseRetryAssessment(
            candidate: null,
            evidence: null,
            hardIssues: List.unmodifiable(blockingIssues));
      }
      candidate = local;
      evidence = remote;
      causalIssues.addAll(
        blockingIssues.where(
          (candidateIssue) =>
              candidateIssue.issueType == 'inventory_movement_rejected' &&
              candidateIssue.domain == 'inventory_balance' &&
              candidateIssue.entityType == 'inventory_movements' &&
              local.movementIds.contains(candidateIssue.entityId),
        ),
      );
    }
    return RecoveryBlockedPurchaseRetryAssessment(
        candidate: candidate,
        evidence: evidence,
        hardIssues: List.unmodifiable(
            blockingIssues.where((issue) => !causalIssues.contains(issue))));
  }

  Future<RecoveryBlockedPurchaseRetryResult> retry(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required List<OperationalBootstrapBlockingIssue> blockingIssues}) {
    final key = '${scope.profileId}:${scope.businessId}:${scope.branchId}';
    return _inFlight.putIfAbsent(
        key,
        () => _retry(scope: scope, blockingIssues: blockingIssues).whenComplete(
              () {
                _inFlight.remove(key);
              },
            ));
  }

  Future<RecoveryBlockedPurchaseRetryResult> _retry(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required List<OperationalBootstrapBlockingIssue> blockingIssues}) async {
    final assessment =
        await assess(scope: scope, blockingIssues: blockingIssues);
    final candidate = assessment.candidate;
    final initialEvidence = assessment.evidence;
    if (candidate == null || initialEvidence?.safeToRetry != true) {
      throw const RecoveryBlockedPurchaseRetryException(
          'No existe una Purchase permission_denied reparable en este contexto.');
    }
    String? localBatchId;
    if (!initialEvidence!.remoteMaterialized || !candidate.locallyConverged) {
      if (!await _gateway.prepareLocalRetry(
          scope: scope, purchaseId: candidate.purchaseId)) {
        throw const RecoveryBlockedPurchaseRetryException(
            'La evidencia local cambió antes de preparar el retry.');
      }
      localBatchId = await _gateway.enqueue(
          scope: scope, purchaseId: candidate.purchaseId);
      if (localBatchId == null || localBatchId.isEmpty) {
        throw const RecoveryBlockedPurchaseRetryException(
            'La Purchase no pudo reenviarse con su identidad local.');
      }
      if (!await _gateway.upload(scope: scope, localBatchId: localBatchId)) {
        throw const RecoveryBlockedPurchaseRetryException(
            'El upload focal no terminó autoritativamente.');
      }
    }
    final finalization =
        await _gateway.finalize(scope: scope, purchaseId: candidate.purchaseId);
    if (!finalization.finalizable || !finalization.remoteMaterialized) {
      throw const RecoveryBlockedPurchaseRetryException(
          'La materialización remota no pudo demostrarse.');
    }
    await _gateway.reconcileInventory(scope: scope);
    final localConverged = await _gateway.isPurchaseLocallyConverged(
        scope: scope, purchaseId: candidate.purchaseId);
    var targetIssueOpen = false;
    for (final movementId in candidate.movementIds) {
      targetIssueOpen = targetIssueOpen ||
          await _gateway.isTargetIssueOpen(
              scope: scope, movementId: movementId);
    }
    if (!localConverged || targetIssueOpen) {
      throw const RecoveryBlockedPurchaseRetryException(
          'El retry remoto terminó, pero la convergencia local causal no concluyó.');
    }
    return RecoveryBlockedPurchaseRetryResult(
        purchaseId: candidate.purchaseId,
        remoteAlreadyMaterialized: initialEvidence.remoteMaterialized,
        localBatchId: localBatchId,
        remainingHardIssues: assessment.hardIssues.length);
  }

  void _validateScope(RecoveryBlockedPurchaseRetryScope scope) {
    if (_authenticatedProfileId() != scope.profileId ||
        scope.profileId.trim().isEmpty ||
        scope.businessId.trim().isEmpty ||
        scope.branchId.trim().isEmpty ||
        scope.appDeviceId.trim().isEmpty ||
        scope.installationId.trim().isEmpty) {
      throw const RecoveryBlockedPurchaseRetryException(
          'El contexto autenticado del retry no coincide.');
    }
  }
}
