import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/authorized_operational_context_local_dao.dart';
import '../data/datasources/catalog_entity_sync_state_resolver.dart';
import '../data/datasources/core_context_local_dao.dart';
import '../data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import '../data/datasources/operational_bootstrap_remote_datasource.dart';
import '../data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/datasources/cash_pos_reconciliation_local_dao.dart';
import '../data/datasources/product_operational_reconciliation_local_dao.dart';
import '../../inventory/application/product_stock_balance_providers.dart';
import '../data/datasources/inventory_balance_reconciliation_local_dao.dart';
import '../data/datasources/inventory_movement_acknowledgement_remote_datasource.dart';
import 'category_snapshot_applier.dart';
import 'core_context_snapshot_applier.dart';
import 'operational_bootstrap_download_service.dart';
import 'operational_bootstrap_orchestration_models.dart';
import 'operational_bootstrap_page_applier.dart';
import 'operational_bootstrap_page_applier_router.dart';
import 'operational_bootstrap_service.dart';
import 'product_barcode_snapshot_applier.dart';
import 'product_operational_reconciliation_support.dart';
import 'product_snapshot_applier.dart';
import 'inventory_balance_reconciliation_service.dart';
import 'inventory_balance_snapshot_applier.dart';
import 'cash_pos_snapshot_applier.dart';
import 'cash_pos_recovery_service.dart';
import '../../cash/application/cash_session_local_provider.dart';

final operationalBootstrapRemoteDataSourceProvider =
    Provider<OperationalBootstrapRemoteDataSource>((ref) {
  return OperationalBootstrapRemoteDataSource(
    ref.watch(supabaseClientProvider),
  );
});

final operationalBootstrapCheckpointLocalDaoProvider =
    Provider<OperationalBootstrapCheckpointLocalDao>((ref) {
  return OperationalBootstrapCheckpointLocalDao(
    ref.watch(appDatabaseProvider),
  );
});

final operationalBootstrapSeenRecordLocalDaoProvider =
    Provider<OperationalBootstrapSeenRecordLocalDao>((ref) {
  return OperationalBootstrapSeenRecordLocalDao(
    ref.watch(appDatabaseProvider),
  );
});

final reconciliationIssueLocalDaoProvider =
    Provider<ReconciliationIssueLocalDao>((ref) {
  return ReconciliationIssueLocalDao(ref.watch(appDatabaseProvider));
});

final authorizedOperationalContextLocalDaoProvider =
    Provider<AuthorizedOperationalContextLocalDao>((ref) {
  return AuthorizedOperationalContextLocalDao(ref.watch(appDatabaseProvider));
});

final coreContextLocalDaoProvider = Provider<CoreContextLocalDao>((ref) {
  return CoreContextLocalDao(ref.watch(appDatabaseProvider));
});

final coreContextSnapshotApplierProvider =
    Provider<CoreContextSnapshotApplier>((ref) {
  return CoreContextSnapshotApplier(
    coreContextLocalDao: ref.watch(coreContextLocalDaoProvider),
    authorizationDao: ref.watch(authorizedOperationalContextLocalDaoProvider),
  );
});

final productOperationalReconciliationLocalDaoProvider =
    Provider<ProductOperationalReconciliationLocalDao>((ref) {
  return ProductOperationalReconciliationLocalDao(
    ref.watch(appDatabaseProvider),
  );
});

final catalogEntitySyncStateResolverProvider =
    Provider<CatalogEntitySyncStateResolver>((ref) {
  return CatalogEntitySyncStateResolver(ref.watch(appDatabaseProvider));
});

final productOperationalReconciliationSupportProvider =
    Provider<ProductOperationalReconciliationSupport>((ref) {
  return ProductOperationalReconciliationSupport(
    stateResolver: ref.watch(catalogEntitySyncStateResolverProvider),
    issueDao: ref.watch(reconciliationIssueLocalDaoProvider),
    seenRecordDao: ref.watch(operationalBootstrapSeenRecordLocalDaoProvider),
  );
});

final categorySnapshotApplierProvider =
    Provider<CategorySnapshotApplier>((ref) {
  return CategorySnapshotApplier(
    localDao: ref.watch(productOperationalReconciliationLocalDaoProvider),
    support: ref.watch(productOperationalReconciliationSupportProvider),
  );
});

final productSnapshotApplierProvider = Provider<ProductSnapshotApplier>((ref) {
  return ProductSnapshotApplier(
    localDao: ref.watch(productOperationalReconciliationLocalDaoProvider),
    support: ref.watch(productOperationalReconciliationSupportProvider),
  );
});

final productBarcodeSnapshotApplierProvider =
    Provider<ProductBarcodeSnapshotApplier>((ref) {
  return ProductBarcodeSnapshotApplier(
    localDao: ref.watch(productOperationalReconciliationLocalDaoProvider),
    support: ref.watch(productOperationalReconciliationSupportProvider),
  );
});

final inventoryBalanceReconciliationLocalDaoProvider =
    Provider<InventoryBalanceReconciliationLocalDao>((ref) {
  return InventoryBalanceReconciliationLocalDao(
    ref.watch(appDatabaseProvider),
  );
});

final inventoryMovementAcknowledgementRemoteDataSourceProvider =
    Provider<InventoryMovementAcknowledgementRemoteDataSource>((ref) {
  return InventoryMovementAcknowledgementRemoteDataSource(
    ref.watch(supabaseClientProvider),
  );
});

final inventoryBalanceSnapshotApplierProvider =
    Provider<InventoryBalanceSnapshotApplier>((ref) {
  return InventoryBalanceSnapshotApplier(
    balanceDao: ref.watch(productStockBalanceLocalDaoProvider),
  );
});

final cashPosReconciliationLocalDaoProvider =
    Provider<CashPosReconciliationLocalDao>((ref) {
  return CashPosReconciliationLocalDao(ref.watch(appDatabaseProvider));
});

final cashPosSnapshotApplierProvider = Provider<CashPosSnapshotApplier>((ref) {
  return CashPosSnapshotApplier(
    localDao: ref.watch(cashPosReconciliationLocalDaoProvider),
    seenRecordDao: ref.watch(operationalBootstrapSeenRecordLocalDaoProvider),
    issueDao: ref.watch(reconciliationIssueLocalDaoProvider),
  );
});

final operationalBootstrapPageApplierProvider =
    Provider<OperationalBootstrapPageApplier>((ref) {
  return OperationalBootstrapPageApplierRouter(
    routes: {
      'core/context': ref.watch(coreContextSnapshotApplierProvider),
      'product_operational/categories':
          ref.watch(categorySnapshotApplierProvider),
      'product_operational/products': ref.watch(productSnapshotApplierProvider),
      'product_operational/product_barcodes':
          ref.watch(productBarcodeSnapshotApplierProvider),
      'product_operational/product_stock_balances':
          ref.watch(inventoryBalanceSnapshotApplierProvider),
      for (final dataset in CashPosSnapshotApplier.datasets)
        'cash_pos/$dataset': ref.watch(cashPosSnapshotApplierProvider),
    },
    dependencyOrder: const {
      'cash_pos': CashPosSnapshotApplier.datasets,
    },
  );
});

final cashPosRecoveryServiceProvider = Provider<CashPosRecoveryService>((ref) {
  return CashPosRecoveryService(
    downloadService: ref.watch(operationalBootstrapDownloadServiceProvider),
    reconciliationDao: ref.watch(cashPosReconciliationLocalDaoProvider),
    cashSessionDao: ref.watch(cashSessionLocalDaoProvider),
    issueDao: ref.watch(reconciliationIssueLocalDaoProvider),
  );
});

final inventoryBalanceReconciliationServiceProvider =
    Provider<InventoryBalanceReconciliationService>((ref) {
  return InventoryBalanceReconciliationService(
    database: ref.watch(appDatabaseProvider),
    acknowledgementDataSource:
        ref.watch(inventoryMovementAcknowledgementRemoteDataSourceProvider),
    movementDao: ref.watch(inventoryBalanceReconciliationLocalDaoProvider),
    balanceDao: ref.watch(productStockBalanceLocalDaoProvider),
    downloadService: ref.watch(operationalBootstrapDownloadServiceProvider),
    seenRecordDao: ref.watch(operationalBootstrapSeenRecordLocalDaoProvider),
    checkpointDao: ref.watch(operationalBootstrapCheckpointLocalDaoProvider),
    issueDao: ref.watch(reconciliationIssueLocalDaoProvider),
  );
});

final operationalBootstrapDownloadServiceProvider =
    Provider<OperationalBootstrapDownloadService>((ref) {
  return OperationalBootstrapDownloadService(
    database: ref.watch(appDatabaseProvider),
    remoteDataSource: ref.watch(operationalBootstrapRemoteDataSourceProvider),
    checkpointDao: ref.watch(operationalBootstrapCheckpointLocalDaoProvider),
    seenRecordDao: ref.watch(operationalBootstrapSeenRecordLocalDaoProvider),
    reconciliationIssueDao: ref.watch(reconciliationIssueLocalDaoProvider),
    pageApplier: ref.watch(operationalBootstrapPageApplierProvider),
    authorizationContextDao:
        ref.watch(authorizedOperationalContextLocalDaoProvider),
  );
});

class OperationalBootstrapProgressNotifier
    extends Notifier<OperationalBootstrapProgress> {
  @override
  OperationalBootstrapProgress build() {
    return const OperationalBootstrapProgress.idle();
  }

  void publish(OperationalBootstrapProgress progress) {
    state = progress;
  }
}

final operationalBootstrapProgressProvider = NotifierProvider<
    OperationalBootstrapProgressNotifier, OperationalBootstrapProgress>(
  OperationalBootstrapProgressNotifier.new,
);

final operationalBootstrapServiceProvider =
    Provider<OperationalBootstrapService>((ref) {
  return OperationalBootstrapService(
    downloadService: ref.watch(operationalBootstrapDownloadServiceProvider),
    inventoryService: ref.watch(inventoryBalanceReconciliationServiceProvider),
    cashPosRecoveryService: ref.watch(cashPosRecoveryServiceProvider),
    authorizationContextDao:
        ref.watch(authorizedOperationalContextLocalDaoProvider),
    checkpointDao: ref.watch(operationalBootstrapCheckpointLocalDaoProvider),
    issueDao: ref.watch(reconciliationIssueLocalDaoProvider),
    authenticatedProfileId: () => ref.read(currentSupabaseUserProvider)?.id,
    onProgress: ref.read(operationalBootstrapProgressProvider.notifier).publish,
  );
});
