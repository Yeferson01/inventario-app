import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../inventory/application/purchase_local_provider.dart';
import '../../inventory/application/purchase_sync_repair_provider.dart';
import '../data/datasources/purchases_sync_remote_datasource.dart';
import '../data/datasources/recovery_blocked_purchase_retry_local_dao.dart';
import '../data/models/inventory_balance_reconciliation_models.dart';
import 'operational_bootstrap_providers.dart';
import 'purchases_sync_upload_provider.dart';
import 'recovery_blocked_purchase_retry_service.dart';

final recoveryBlockedPurchaseRetryLocalDaoProvider =
    Provider<RecoveryBlockedPurchaseRetryLocalDao>((ref) {
  return RecoveryBlockedPurchaseRetryLocalDao(ref.watch(appDatabaseProvider));
});

final recoveryBlockedPurchaseRetryServiceProvider =
    Provider<RecoveryBlockedPurchaseRetryService>((ref) {
  return RecoveryBlockedPurchaseRetryService(
    authenticatedProfileId: () => ref.read(currentSupabaseUserProvider)?.id,
    gateway: _ProductivePurchaseRetryGateway(ref),
  );
});

class _ProductivePurchaseRetryGateway
    implements RecoveryBlockedPurchaseRetryGateway {
  _ProductivePurchaseRetryGateway(this.ref);
  final Ref ref;

  @override
  Future<RecoveryBlockedPurchaseCandidate?> findCandidate(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String movementId}) {
    return ref.read(recoveryBlockedPurchaseRetryLocalDaoProvider).findCandidate(
          profileId: scope.profileId,
          businessId: scope.businessId,
          branchId: scope.branchId,
          appDeviceId: scope.appDeviceId,
          movementId: movementId,
        );
  }

  @override
  Future<PurchasePermissionRetryEvidence> inspect(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId}) {
    return ref
        .read(purchasesSyncRemoteDataSourceProvider)
        .inspectPermissionRetry(
          businessId: scope.businessId,
          branchId: scope.branchId,
          appDeviceId: scope.appDeviceId,
          purchaseId: purchaseId,
        );
  }

  @override
  Future<bool> prepareLocalRetry(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId}) async {
    final result = await ref
        .read(purchaseSyncRepairServiceProvider)
        .repairPurchaseForRetry(
          profileId: scope.profileId,
          businessId: scope.businessId,
          branchId: scope.branchId,
          appDeviceId: scope.appDeviceId,
          purchaseId: purchaseId,
        );
    return result.resetPurchases == 1;
  }

  @override
  Future<String?> enqueue(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId}) async {
    final reusable = await ref
        .read(recoveryBlockedPurchaseRetryLocalDaoProvider)
        .findReusableRetryBatchId(
          profileId: scope.profileId,
          businessId: scope.businessId,
          branchId: scope.branchId,
          appDeviceId: scope.appDeviceId,
          purchaseId: purchaseId,
        );
    if (reusable != null) return reusable;
    final result = await ref
        .read(purchaseSyncOutboxServiceProvider)
        .enqueuePurchaseForRetry(
          businessId: scope.businessId,
          branchId: scope.branchId,
          profileId: scope.profileId,
          appDeviceId: scope.appDeviceId,
          deviceInstallationId: scope.installationId,
          purchaseId: purchaseId,
        );
    if (result.purchasesEnqueued != 1 || result.results.length != 1) {
      return null;
    }
    final outbox = result.results.single['outbox_result'];
    return outbox is Map ? outbox['local_batch_id']?.toString().trim() : null;
  }

  @override
  Future<bool> upload(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String localBatchId}) async {
    final result = await ref
        .read(purchasesSyncUploadServiceProvider)
        .uploadPendingPurchasesBatches(
      businessId: scope.businessId,
      branchId: scope.branchId,
      batchLimit: 50,
      onlyLocalBatchIds: {localBatchId},
    );
    return result.batchesCompleted == 1 &&
        result.batchesPartial == 0 &&
        result.batchesFailed == 0 &&
        result.batchesWaitingForDependencies == 0 &&
        result.batchesBlockedByDependencies == 0;
  }

  @override
  Future<PurchasePermissionRetryEvidence> finalize(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId}) {
    return ref
        .read(purchasesSyncRemoteDataSourceProvider)
        .finalizePermissionRetry(
          businessId: scope.businessId,
          branchId: scope.branchId,
          appDeviceId: scope.appDeviceId,
          purchaseId: purchaseId,
        );
  }

  @override
  Future<void> reconcileInventory(
      {required RecoveryBlockedPurchaseRetryScope scope}) async {
    await ref.read(inventoryBalanceReconciliationServiceProvider).reconcile(
          InventoryBalanceReconciliationRequest(
            profileId: scope.profileId,
            businessId: scope.businessId,
            branchId: scope.branchId,
            appDeviceId: scope.appDeviceId,
          ),
        );
  }

  @override
  Future<bool> isPurchaseLocallyConverged(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String purchaseId}) {
    return ref
        .read(recoveryBlockedPurchaseRetryLocalDaoProvider)
        .isPurchaseLocallyConverged(
          businessId: scope.businessId,
          branchId: scope.branchId,
          purchaseId: purchaseId,
        );
  }

  @override
  Future<bool> isTargetIssueOpen(
      {required RecoveryBlockedPurchaseRetryScope scope,
      required String movementId}) {
    return ref
        .read(recoveryBlockedPurchaseRetryLocalDaoProvider)
        .isTargetIssueOpen(
          profileId: scope.profileId,
          businessId: scope.businessId,
          branchId: scope.branchId,
          movementId: movementId,
        );
  }
}
