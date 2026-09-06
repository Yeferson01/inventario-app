import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_orchestration_models.dart';
import 'package:inventario_frontend/features/sync/application/recovery_blocked_purchase_retry_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/purchases_sync_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/recovery_blocked_purchase_retry_local_dao.dart';

void main() {
  const scope = RecoveryBlockedPurchaseRetryScope(
    profileId: 'profile',
    businessId: 'business',
    branchId: 'branch',
    appDeviceId: 'device',
    installationId: 'installation',
    effectivePermissions: {'inventory.purchase'},
  );
  const causalIssue = OperationalBootstrapBlockingIssue(
    issueType: 'inventory_movement_rejected',
    domain: 'inventory_balance',
    entityType: 'inventory_movements',
    entityId: 'movement',
    message: 'rejected',
  );
  const unrelatedIssue = OperationalBootstrapBlockingIssue(
    issueType: 'unrelated',
    domain: 'cash_pos',
    message: 'unrelated blocker',
  );

  test('recoveryBlocked Purchase permission_denied exposes retry', () async {
    final gateway = _FakeGateway();
    final service = _service(gateway);
    final assessment = await service.assess(
      scope: scope,
      blockingIssues: const [causalIssue],
    );
    expect(assessment.canRetry, isTrue);
    expect(assessment.candidate?.purchaseId, 'purchase');
  });

  test('unknown blocker does not expose Purchase retry', () async {
    final gateway = _FakeGateway();
    final assessment = await _service(gateway).assess(
      scope: scope,
      blockingIssues: const [unrelatedIssue],
    );
    expect(assessment.canRetry, isFalse);
    expect(gateway.inspectCalls, 0);
  });

  test('retry preserves target identity through every operation', () async {
    final gateway = _FakeGateway();
    final result = await _service(gateway).retry(
      scope: scope,
      blockingIssues: const [causalIssue],
    );
    expect(result.purchaseId, 'purchase');
    expect(result.localBatchId, 'retry-batch');
    expect(gateway.seenPurchaseIds, everyElement('purchase'));
    expect(gateway.seenBatchIds, ['retry-batch']);
  });

  test('single-flight prevents a second upload', () async {
    final gateway = _FakeGateway();
    gateway.uploadCompleter = Completer<bool>();
    final service = _service(gateway);
    final first =
        service.retry(scope: scope, blockingIssues: const [causalIssue]);
    final second =
        service.retry(scope: scope, blockingIssues: const [causalIssue]);
    await Future<void>.delayed(Duration.zero);
    gateway.uploadCompleter!.complete(true);
    await Future.wait([first, second]);
    expect(gateway.uploadCalls, 1);
  });

  test('authoritative success converges locally before completing', () async {
    final gateway = _FakeGateway();
    await _service(gateway).retry(
      scope: scope,
      blockingIssues: const [causalIssue],
    );
    expect(
        gateway.calls,
        containsAllInOrder([
          'inspect',
          'prepare',
          'enqueue',
          'upload',
          'finalize',
          'reconcile',
          'local_converged',
          'issue_open',
        ]));
  });

  test('failed upload leaves the operation retryable', () async {
    final gateway = _FakeGateway()..uploadSucceeds = false;
    final service = _service(gateway);
    await expectLater(
      service.retry(scope: scope, blockingIssues: const [causalIssue]),
      throwsA(isA<RecoveryBlockedPurchaseRetryException>()),
    );
    gateway.uploadSucceeds = true;
    final assessment = await service.assess(
      scope: scope,
      blockingIssues: const [causalIssue],
    );
    expect(assessment.canRetry, isTrue);
  });

  test('already materialized remote Purchase converges without new identity',
      () async {
    final gateway = _FakeGateway()
      ..remoteAlreadyMaterialized = true
      ..locallyConverged = true;
    final result = await _service(gateway).retry(
      scope: scope,
      blockingIssues: const [causalIssue],
    );
    expect(result.remoteAlreadyMaterialized, isTrue);
    expect(gateway.seenPurchaseIds.toSet(), {'purchase'});
    expect(gateway.uploadCalls, 0);
  });

  test('unrelated blocker remains after causal Purchase repair', () async {
    final result = await _service(_FakeGateway()).retry(
      scope: scope,
      blockingIssues: const [causalIssue, unrelatedIssue],
    );
    expect(result.remainingHardIssues, 1);
  });
}

RecoveryBlockedPurchaseRetryService _service(_FakeGateway gateway) {
  return RecoveryBlockedPurchaseRetryService(
    authenticatedProfileId: () => 'profile',
    gateway: gateway,
  );
}

class _FakeGateway implements RecoveryBlockedPurchaseRetryGateway {
  bool remoteAlreadyMaterialized = false;
  bool uploadSucceeds = true;
  bool locallyConverged = false;
  Completer<bool>? uploadCompleter;
  int inspectCalls = 0;
  int uploadCalls = 0;
  final calls = <String>[];
  final seenPurchaseIds = <String>[];
  final seenBatchIds = <String>[];

  PurchasePermissionRetryEvidence get _preflight =>
      PurchasePermissionRetryEvidence(
        safeToRetry: true,
        remoteAbsent: !remoteAlreadyMaterialized,
        remoteMaterialized: remoteAlreadyMaterialized,
        finalizable: remoteAlreadyMaterialized,
        targetConflictCount: 2,
        appliedMutationCount: remoteAlreadyMaterialized ? 2 : 0,
      );

  PurchasePermissionRetryEvidence get _final =>
      const PurchasePermissionRetryEvidence(
        safeToRetry: true,
        remoteAbsent: false,
        remoteMaterialized: true,
        finalizable: true,
        targetConflictCount: 2,
        appliedMutationCount: 2,
      );

  @override
  Future<RecoveryBlockedPurchaseCandidate?> findCandidate(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String movementId}) async {
    return RecoveryBlockedPurchaseCandidate(
      purchaseId: 'purchase',
      movementIds: ['movement'],
      itemIds: ['item'],
      localBatchIds: ['old-batch'],
      locallyConverged: locallyConverged,
    );
  }

  @override
  Future<PurchasePermissionRetryEvidence> inspect(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId}) async {
    inspectCalls++;
    calls.add('inspect');
    seenPurchaseIds.add(purchaseId);
    return _preflight;
  }

  @override
  Future<bool> prepareLocalRetry(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId}) async {
    calls.add('prepare');
    seenPurchaseIds.add(purchaseId);
    return true;
  }

  @override
  Future<String?> enqueue(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId}) async {
    calls.add('enqueue');
    seenPurchaseIds.add(purchaseId);
    return 'retry-batch';
  }

  @override
  Future<bool> upload(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String localBatchId}) async {
    uploadCalls++;
    calls.add('upload');
    seenBatchIds.add(localBatchId);
    if (uploadCompleter != null) return uploadCompleter!.future;
    return uploadSucceeds;
  }

  @override
  Future<PurchasePermissionRetryEvidence> finalize(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId}) async {
    calls.add('finalize');
    seenPurchaseIds.add(purchaseId);
    return _final;
  }

  @override
  Future<void> reconcileInventory(
          {required RecoveryBlockedPurchaseRetryScope scope}) async =>
      calls.add('reconcile');

  @override
  Future<bool> isPurchaseLocallyConverged(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId}) async {
    calls.add('local_converged');
    return true;
  }

  @override
  Future<bool> isTargetIssueOpen(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String movementId}) async {
    calls.add('issue_open');
    return false;
  }
}
