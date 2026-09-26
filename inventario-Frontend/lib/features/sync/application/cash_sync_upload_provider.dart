import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/database/database_provider.dart';
import '../../cash/data/datasources/cash_movement_local_dao.dart';
import '../../cash/application/cash_session_local_provider.dart';
import '../data/datasources/cash_sync_remote_datasource.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import 'cash_sync_upload_service.dart';
import 'local_sync_outbox_providers.dart';

final cashSyncRemoteDataSourceProvider =
    Provider<CashSyncRemoteDataSource>((ref) {
  final client = ref.watch(supabaseClientProvider);

  return CashSyncRemoteDataSource(client);
});

final cashSyncUploadServiceProvider = Provider<CashSyncUploadService>((ref) {
  return CashSyncUploadService(
    outboxService: ref.watch(localSyncOutboxServiceProvider),
    remoteDataSource: ref.watch(cashSyncRemoteDataSourceProvider),
    cashSessionLocalDao: ref.watch(cashSessionLocalDaoProvider),
    cashMovementLocalDao: CashMovementLocalDao(ref.watch(appDatabaseProvider)),
    issueDao: ReconciliationIssueLocalDao(ref.watch(appDatabaseProvider)),
  );
});
