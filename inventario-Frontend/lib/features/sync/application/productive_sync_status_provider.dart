import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/connectivity_provider.dart';
import '../../cash/application/cash_session_local_provider.dart';
import '../../inventory/application/purchase_local_provider.dart';
import '../../sales/application/pos_local_sale_provider.dart';
import 'local_sync_outbox_providers.dart';
import 'operational_bootstrap_providers.dart';
import 'productive_sync_status.dart';
import 'productive_sync_status_revision_provider.dart';
import 'purchase_product_dependency_resolver.dart';
import 'purchases_sync_upload_provider.dart';

const _productiveStatusReadLimit = 0x7fffffff;

class ProductiveSyncStatusRequest {
  const ProductiveSyncStatusRequest({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.isSyncing,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final bool isSyncing;

  @override
  bool operator ==(Object other) {
    return other is ProductiveSyncStatusRequest &&
        other.profileId == profileId &&
        other.businessId == businessId &&
        other.branchId == branchId &&
        other.isSyncing == isSyncing;
  }

  @override
  int get hashCode {
    return Object.hash(profileId, businessId, branchId, isSyncing);
  }
}

final productiveSyncStatusServiceProvider =
    Provider<ProductiveSyncStatusService>((ref) {
  final saleDao = ref.watch(posLocalSaleDaoProvider);
  final purchaseDao = ref.watch(purchaseLocalDaoProvider);
  final cashService = ref.watch(cashSessionLocalServiceProvider);
  final issueDao = ref.watch(reconciliationIssueLocalDaoProvider);
  final outboxDao = ref.watch(localSyncOutboxDaoProvider);
  final outboxService = ref.watch(localSyncOutboxServiceProvider);
  final dependencyResolver =
      ref.watch(purchaseProductDependencyResolverProvider);

  return ProductiveSyncStatusService(
    pendingSalesLoader: ({required businessId, required branchId}) {
      return saleDao.getPendingDirtySales(
        businessId: businessId,
        branchId: branchId,
        limit: _productiveStatusReadLimit,
      );
    },
    pendingPurchasesLoader: ({required businessId, required branchId}) {
      return purchaseDao.getPendingDirtyPurchases(
        businessId: businessId,
        branchId: branchId,
        limit: _productiveStatusReadLimit,
      );
    },
    cashReadinessLoader: cashService.getPosCashReadinessSummary,
    openIssuesLoader: issueDao.getOpenIssues,
    outboxStatusRowsLoader: outboxDao.getProductiveStatusRows,
    blockedPurchaseDependenciesLoader: ({
      required businessId,
      required branchId,
    }) async {
      final batches = await outboxService.getPendingBatches(
        businessId: businessId,
        branchId: branchId,
        domain: 'purchases',
        limit: _productiveStatusReadLimit,
      );
      var blocked = 0;
      for (final batch in batches) {
        final batchId = batch['id']?.toString().trim();
        if (batchId == null || batchId.isEmpty) {
          continue;
        }
        final mutations = await outboxService.getMutationsForBatch(batchId);
        final resolution = await dependencyResolver.resolve(
          businessId: businessId,
          purchaseMutations: mutations,
        );
        if (resolution.status == PurchaseProductDependencyStatus.blocked) {
          blocked++;
        }
      }
      return blocked;
    },
  );
});

final productiveSyncStatusProvider =
    FutureProvider.family<ProductiveSyncStatus, ProductiveSyncStatusRequest>(
        (ref, request) async {
  ref.watch(productiveSyncStatusRevisionProvider);
  final connectivity = ref.watch(isOnlineStreamProvider);
  final isOnline = connectivity.asData?.value ??
      await ref.watch(connectivityServiceProvider).isOnline;

  return ref.watch(productiveSyncStatusServiceProvider).load(
        scope: ProductiveSyncScope(
          profileId: request.profileId,
          businessId: request.businessId,
          branchId: request.branchId,
        ),
        isOnline: isOnline,
        isSyncing: request.isSyncing,
      );
});
