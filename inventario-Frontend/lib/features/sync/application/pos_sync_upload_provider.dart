import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/pos_sync_remote_datasource.dart';
import 'local_sync_outbox_providers.dart';
import 'pos_sync_upload_service.dart';
import '../../sales/application/pos_local_sale_provider.dart';
import '../../cash/application/cash_session_local_provider.dart';
import 'operational_bootstrap_providers.dart';
import 'pos_cash_session_failure_reconciliation_service.dart';
import 'pos_inventory_failure_reconciliation_service.dart';
import 'unmaterialized_local_sale_discard_service.dart';
import 'intentional_stale_sale_reconciliation_service.dart';
import 'productive_stale_sale_reconciliation_service.dart';
import 'recovery_blocked_stale_sale_service.dart';
import '../data/models/cash_pos_recovery_models.dart';
import '../data/models/inventory_balance_reconciliation_models.dart';

final posSyncRemoteDataSourceProvider =
    Provider<PosSyncRemoteDataSource>((ref) {
  final client = ref.watch(supabaseClientProvider);

  return PosSyncRemoteDataSource(client);
});

final posSyncUploadServiceProvider = Provider<PosSyncUploadService>((ref) {
  return PosSyncUploadService(
    outboxService: ref.watch(localSyncOutboxServiceProvider),
    remoteDataSource: ref.watch(posSyncRemoteDataSourceProvider),
    posLocalSaleDao: ref.watch(posLocalSaleDaoProvider),
    cashSessionLocalDao: ref.watch(cashSessionLocalDaoProvider),
    cashSessionFailureReconciliationService:
        PosCashSessionFailureReconciliationService(
      issueDao: ref.watch(reconciliationIssueLocalDaoProvider),
    ),
    inventoryFailureReconciliationService:
        PosInventoryFailureReconciliationService(
      saleDao: ref.watch(posLocalSaleDaoProvider),
      issueDao: ref.watch(reconciliationIssueLocalDaoProvider),
    ),
  );
});

final unmaterializedLocalSaleDiscardServiceProvider =
    Provider<UnmaterializedLocalSaleDiscardService>((ref) {
  final remote = ref.watch(posSyncRemoteDataSourceProvider);
  return UnmaterializedLocalSaleDiscardService(
    localDao: ref.watch(posLocalSaleDaoProvider),
    remoteVerifier: remote.verifyUnmaterializedSale,
    remoteFinalizer: remote.resolveUnmaterializedSaleDidNotOccur,
  );
});

final intentionalStaleSaleReconciliationServiceProvider =
    Provider<IntentionalStaleSaleReconciliationService>((ref) {
  final remote = ref.watch(posSyncRemoteDataSourceProvider);
  final localDao = ref.watch(posLocalSaleDaoProvider);
  final inventory = ref.watch(inventoryBalanceReconciliationServiceProvider);
  final cash = ref.watch(cashPosRecoveryServiceProvider);
  return IntentionalStaleSaleReconciliationService(
    remoteExecutor: remote.reconcileRejectedSaleToOpenCashSession,
    localProjector: localDao.projectIntentionalStaleSaleReconciliation,
    localPreviewLoader: localDao.loadIntentionalStaleSaleReconciliationPreview,
    inventoryRefresher: (input, result) async {
      final reconciliation = await inventory.reconcile(
        InventoryBalanceReconciliationRequest(
          profileId: input.profileId,
          businessId: input.businessId,
          branchId: input.branchId,
          appDeviceId: input.appDeviceId,
        ),
        restart: true,
      );
      if (!reconciliation.converged) {
        throw StateError(
          'Inventory reconciliation retained '
          '${reconciliation.blockingIssues} blocker(s).',
        );
      }
    },
    cashRefresher: (input, result) async {
      final recovery = await cash.recover(
        CashPosRecoveryRequest(
          profileId: input.profileId,
          businessId: input.businessId,
          branchId: input.branchId,
          appDeviceId: input.appDeviceId,
          canonicalCashRegisterId: result.cashRegisterId,
        ),
        restart: true,
      );
      if (!recovery.completed || !recovery.cashContextReady) {
        throw StateError(
          'Cash refresh retained ${recovery.blockingIssues} blocker(s).',
        );
      }
    },
  );
});

final productiveStaleSaleReconciliationServiceProvider =
    Provider<ProductiveStaleSaleReconciliationController>((ref) {
  final remote = ref.watch(posSyncRemoteDataSourceProvider);
  final inventory = ref.watch(inventoryBalanceReconciliationServiceProvider);
  final cash = ref.watch(cashPosRecoveryServiceProvider);
  final saleDao = ref.watch(posLocalSaleDaoProvider);
  return ProductiveStaleSaleReconciliationService(
    saleDao: saleDao,
    cashDao: ref.watch(cashSessionLocalDaoProvider),
    discardService: ref.watch(unmaterializedLocalSaleDiscardServiceProvider),
    reconciliationService:
        ref.watch(intentionalStaleSaleReconciliationServiceProvider),
    conflictIdResolver: remote.findOpenClosedCashSessionSaleConflictId,
    postDiscardRefresher: ({
      required profileId,
      required appDeviceId,
      required candidate,
    }) async {
      await inventory.reconcile(
        InventoryBalanceReconciliationRequest(
          profileId: profileId,
          businessId: candidate.businessId,
          branchId: candidate.branchId,
          appDeviceId: appDeviceId,
        ),
        restart: true,
      );
      await cash.recover(
        CashPosRecoveryRequest(
          profileId: profileId,
          businessId: candidate.businessId,
          branchId: candidate.branchId,
          appDeviceId: appDeviceId,
          canonicalCashRegisterId: candidate.cashRegisterId,
        ),
        restart: true,
      );
      final validation = await saleDao.validateDiscardedSalePostRefresh(
        profileId: profileId,
        businessId: candidate.businessId,
        branchId: candidate.branchId,
        saleId: candidate.saleId,
      );
      if (!validation.isConsistent) {
        throw StateError(
          'Post-discard validation retained target Sale inconsistencies: '
          '${validation.problemCodes.join(', ')}.',
        );
      }
    },
  );
});

final recoveryBlockedStaleSaleAssessmentServiceProvider =
    Provider<RecoveryBlockedStaleSaleAssessmentService>((ref) {
  final reconciliation = ref.watch(
    productiveStaleSaleReconciliationServiceProvider,
  );
  final saleDao = ref.watch(posLocalSaleDaoProvider);
  return RecoveryBlockedStaleSaleAssessmentService(
    loadPendingSales: reconciliation.loadPending,
    loadSaleMovements: saleDao.getSaleInventoryMovementsForSyncContext,
  );
});
