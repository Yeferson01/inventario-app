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
  );
});
