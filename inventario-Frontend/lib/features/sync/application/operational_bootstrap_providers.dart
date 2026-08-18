import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/authorized_operational_context_local_dao.dart';
import '../data/datasources/core_context_local_dao.dart';
import '../data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import '../data/datasources/operational_bootstrap_remote_datasource.dart';
import '../data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import 'core_context_snapshot_applier.dart';
import 'operational_bootstrap_download_service.dart';
import 'operational_bootstrap_page_applier.dart';

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

final operationalBootstrapPageApplierProvider =
    Provider<OperationalBootstrapPageApplier>((ref) {
  return ref.watch(coreContextSnapshotApplierProvider);
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
