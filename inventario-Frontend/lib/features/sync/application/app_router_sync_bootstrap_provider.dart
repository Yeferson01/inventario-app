import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/database/database_provider.dart';
import '../../catalog/application/catalog_local_providers.dart';
import '../../cash/application/cash_session_local_provider.dart';
import '../../inventory/application/purchase_local_provider.dart';
import '../../inventory/application/inventory_product_providers.dart';
import '../../sales/application/pos_local_sale_provider.dart';
import 'app_installation_id_store.dart';
import 'app_sync_coordinator_models.dart';
import 'cash_sync_upload_provider.dart';
import 'cash_close_sync_trigger_service.dart';
import 'cash_session_close_readiness_service.dart';
import '../data/datasources/cash_session_close_readiness_dao.dart';
import '../data/models/cash_pos_recovery_models.dart';
import 'operational_bootstrap_providers.dart';
import 'inventory_sync_upload_provider.dart';
import 'local_sync_outbox_providers.dart';
import 'pos_sync_upload_provider.dart';
import 'productive_manual_sync_service.dart';
import 'productive_scheduled_sync_service.dart';
import 'productive_sync_status_provider.dart';
import 'productive_sync_status_revision_provider.dart';
import 'purchases_sync_upload_provider.dart';

class AppRouterSyncBootstrapData {
  const AppRouterSyncBootstrapData({
    required this.hasAuthenticatedUser,
    this.input,
  });

  final bool hasAuthenticatedUser;
  final AppSyncCoordinatorInput? input;

  bool get canRunShellSync {
    return hasAuthenticatedUser && input != null;
  }
}

final appInstallationIdStoreProvider = Provider<AppInstallationIdStore>((ref) {
  return AppInstallationIdStore();
});

final appRouterSyncBootstrapProvider =
    FutureProvider<AppRouterSyncBootstrapData>((ref) async {
  final user = ref.watch(currentSupabaseUserProvider);

  if (user == null) {
    return const AppRouterSyncBootstrapData(
      hasAuthenticatedUser: false,
    );
  }

  final selectedContextStore = ref.watch(appSelectedSyncContextStoreProvider);
  final selectedContext = await selectedContextStore.getSelectedContext(
    profileId: user.id,
  );

  if (selectedContext == null) {
    return const AppRouterSyncBootstrapData(
      hasAuthenticatedUser: true,
    );
  }

  final installationIdStore = ref.watch(appInstallationIdStoreProvider);
  final installationId = await installationIdStore.getOrCreateInstallationId();

  final isOnline = await _isCurrentlyOnline();
  final packageInfo = await PackageInfo.fromPlatform();

  final input = AppSyncCoordinatorInput(
    businessId: selectedContext.businessId,
    branchId: selectedContext.branchId,
    profileId: selectedContext.profileId,
    installationId: installationId,
    isOnline: isOnline,
    deviceName: _deviceName(),
    platform: defaultTargetPlatform.name,
    appVersion: packageInfo.version,
    osVersion: null,
    metadata: const {
      'source': 'router_shell_bootstrap',
    },
  );

  return AppRouterSyncBootstrapData(
    hasAuthenticatedUser: true,
    input: input,
  );
});

final productiveSyncInputLoaderProvider =
    Provider<ProductiveManualSyncInputLoader>((ref) {
  return () async {
    ref.invalidate(appRouterSyncBootstrapProvider);
    final bootstrap = await ref.read(appRouterSyncBootstrapProvider.future);
    if (!bootstrap.hasAuthenticatedUser) return null;
    return bootstrap.input;
  };
});

final productiveManualSyncServiceProvider =
    Provider<ProductiveManualSyncService>((ref) {
  final runtimeSetup = ref.watch(appRuntimeSetupServiceProvider);
  final operationalContextPull =
      ref.watch(operationalContextPullServiceProvider);
  final catalogUpload = ref.watch(catalogSyncUploadServiceProvider);
  final catalogPull = ref.watch(catalogSyncServiceProvider);
  final cashOutbox = ref.watch(cashSyncOutboxServiceProvider);
  final cashUpload = ref.watch(cashSyncUploadServiceProvider);
  final posOutbox = ref.watch(posSyncOutboxServiceProvider);
  final posUpload = ref.watch(posSyncUploadServiceProvider);
  final purchaseOutbox = ref.watch(purchaseSyncOutboxServiceProvider);
  final purchaseUpload = ref.watch(purchasesSyncUploadServiceProvider);
  final productFromMaster =
      ref.watch(inventoryProductFromMasterSyncServiceProvider);
  final inventoryUpload = ref.watch(inventorySyncUploadServiceProvider);

  return ProductiveManualSyncService(
    inputLoader: ref.watch(productiveSyncInputLoaderProvider),
    contextValidator: (input) async {
      final runtime = await runtimeSetup.prepareRuntimeContext(
        businessId: input.businessId,
        branchId: input.branchId!,
        profileId: input.profileId!,
        installationId: input.installationId,
        deviceName: input.deviceName,
        platform: input.platform,
        appVersion: input.appVersion,
        osVersion: input.osVersion,
        metadata: input.metadata,
      );
      await operationalContextPull.pullAndApply(
        businessId: input.businessId,
        profileId: input.profileId!,
      );
      return runtime;
    },
    catalogUploadRunner: (context) async {
      await productFromMaster
          .enqueueManualProductsUsedByUnsyncedPurchasesForCatalogSync(
        businessId: context.businessId,
        branchId: context.branchId,
        profileId: context.profileId,
        appDeviceId: context.appDeviceId,
        deviceInstallationId: context.installationId,
      );
      final result = await catalogUpload.uploadPendingCatalogBatches(
        businessId: context.businessId,
      );
      return _uploadResult(
        ProductiveSyncDomain.catalog,
        partial: result.batchesPartial,
        failed: result.batchesFailed,
      );
    },
    cashRunner: (context) async {
      try {
        await cashOutbox.enqueuePendingCash(
          businessId: context.businessId,
          branchId: context.branchId,
          profileId: context.profileId,
          appDeviceId: context.appDeviceId,
          deviceInstallationId: context.installationId,
        );
      } on StateError catch (error) {
        // An existing batch owns this mutation. Upload it without moving it.
        if (error.message != 'mutation_batch_identity_conflict') rethrow;
      }
      final result = await cashUpload.uploadPendingCashBatches(
        businessId: context.businessId,
        branchId: context.branchId,
      );
      return _uploadResult(
        ProductiveSyncDomain.cash,
        partial: result.batchesPartial,
        failed: result.batchesFailed,
      );
    },
    posRunner: (context) async {
      await posOutbox.enqueuePendingPosSales(
        businessId: context.businessId,
        branchId: context.branchId,
        profileId: context.profileId,
        appDeviceId: context.appDeviceId,
        deviceInstallationId: context.installationId,
      );
      final result = await posUpload.uploadPendingPosBatches(
        businessId: context.businessId,
        branchId: context.branchId,
      );
      return _uploadResult(
        ProductiveSyncDomain.pos,
        partial: result.batchesPartial,
        failed: result.batchesFailed,
      );
    },
    purchasesRunner: (context) async {
      await purchaseOutbox.enqueuePendingPurchases(
        businessId: context.businessId,
        branchId: context.branchId,
        profileId: context.profileId,
        appDeviceId: context.appDeviceId,
        deviceInstallationId: context.installationId,
      );
      final result = await purchaseUpload.uploadPendingPurchasesBatches(
        businessId: context.businessId,
        branchId: context.branchId,
      );
      if (result.batchesBlockedByDependencies > 0) {
        return const ProductiveSyncDomainResult.pending(
          ProductiveSyncDomain.purchases,
          requiresAttention: true,
        );
      }
      if (result.batchesWaitingForDependencies > 0) {
        return const ProductiveSyncDomainResult.pending(
          ProductiveSyncDomain.purchases,
        );
      }
      return _uploadResult(
        ProductiveSyncDomain.purchases,
        partial: result.batchesPartial,
        failed: result.batchesFailed,
      );
    },
    inventoryRunner: (context) async {
      final result = await inventoryUpload.uploadPendingInventoryBatches(
        businessId: context.businessId,
        branchId: context.branchId,
      );
      return _uploadResult(
        ProductiveSyncDomain.inventory,
        partial: result.batchesPartial,
        failed: result.batchesFailed,
      );
    },
    catalogRefreshRunner: (context) async {
      final result = await catalogPull.pullCatalogDelta(
        businessId: context.businessId,
      );
      return result.completed
          ? const ProductiveSyncDomainResult.succeeded(
              ProductiveSyncDomain.catalog,
            )
          : const ProductiveSyncDomainResult.pending(
              ProductiveSyncDomain.catalog,
              failedRetryable: true,
            );
    },
    statusLoader: ref.watch(productiveSyncStatusServiceProvider).load,
    dependencyProgressLoader: ({required businessId, required branchId}) =>
        ref.read(localSyncOutboxDaoProvider).getDependencyProgress(
              businessId: businessId,
              branchId: branchId,
            ),
    onLocalStateChanged: ref
        .read(productiveSyncStatusRevisionProvider.notifier)
        .markLocalStateChanged,
  );
});

final productiveScheduledSyncServiceProvider =
    Provider<ProductiveScheduledSyncService>((ref) {
  return ProductiveScheduledSyncService(
    inputLoader: ref.watch(productiveSyncInputLoaderProvider),
    productiveSyncService: ref.watch(productiveManualSyncServiceProvider),
    policy: ref.watch(scheduledSyncPolicyProvider),
    stateStore: ref.watch(scheduledSyncStateStoreProvider),
  );
});

final cashCloseSyncTriggerServiceProvider =
    Provider<CashCloseSyncTriggerService>((ref) {
  final evidenceDao = CashSessionCloseReadinessDao(
    database: ref.watch(appDatabaseProvider),
    cashSessionDao: ref.watch(cashSessionLocalDaoProvider),
    issueDao: ref.watch(reconciliationIssueLocalDaoProvider),
  );
  return CashCloseSyncTriggerService(
    productiveSyncService: ref.watch(productiveManualSyncServiceProvider),
    cashSessionService: ref.watch(cashSessionLocalServiceProvider),
    closeReadinessService: CashSessionCloseReadinessService(
      evidenceLoader: evidenceDao.load,
      dependencyReadinessLoader:
          ref.watch(localSyncOutboxDaoProvider).getBatchDependencyReadiness,
      provenanceRefresher: ({
        required profileId,
        required businessId,
        required branchId,
        required cashRegisterId,
        required appDeviceId,
      }) async {
        await ref.read(cashPosRecoveryServiceProvider).recover(
              CashPosRecoveryRequest(
                profileId: profileId,
                businessId: businessId,
                branchId: branchId,
                appDeviceId: appDeviceId,
                canonicalCashRegisterId: cashRegisterId,
              ),
            );
      },
    ),
  );
});

final productiveManualSyncRunnerProvider =
    Provider<ProductiveManualSyncRunner>((ref) {
  return ref.watch(productiveManualSyncServiceProvider).run;
});

Future<bool> _isCurrentlyOnline() async {
  final result = await Connectivity().checkConnectivity();

  return result.any((item) => item != ConnectivityResult.none);
}

String _deviceName() {
  if (kIsWeb) {
    return 'Web';
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'Android device';
    case TargetPlatform.iOS:
      return 'iOS device';
    case TargetPlatform.macOS:
      return 'macOS device';
    case TargetPlatform.windows:
      return 'Windows device';
    case TargetPlatform.linux:
      return 'Linux device';
    case TargetPlatform.fuchsia:
      return 'Fuchsia device';
  }
}

ProductiveSyncDomainResult _uploadResult(
  ProductiveSyncDomain domain, {
  required int partial,
  required int failed,
}) {
  if (partial > 0) {
    return ProductiveSyncDomainResult.pending(
      domain,
      requiresAttention: true,
      failedRetryable: failed > 0,
    );
  }
  if (failed > 0) {
    return ProductiveSyncDomainResult.pending(
      domain,
      failedRetryable: true,
    );
  }
  return ProductiveSyncDomainResult.succeeded(domain);
}
