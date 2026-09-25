import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../sync/application/operational_bootstrap_providers.dart';
import '../data/datasources/report_snapshot_local_dao.dart';
import '../data/datasources/sales_report_remote_datasource.dart';
import 'sales_report_service.dart';

final reportSnapshotLocalDaoProvider = Provider<ReportSnapshotLocalDao>((ref) {
  return ReportSnapshotLocalDao(ref.watch(appDatabaseProvider));
});

final salesReportRemoteDatasourceProvider =
    Provider<SalesReportRemoteDatasource>((ref) {
  return SalesReportRemoteDatasource(ref.watch(supabaseClientProvider));
});

final salesReportServiceProvider = Provider<SalesReportService>((ref) {
  return SalesReportService(
    authenticatedProfileId: () => ref.read(currentSupabaseUserProvider)?.id,
    authorizationDao: ref.watch(authorizedOperationalContextLocalDaoProvider),
    snapshotDao: ref.watch(reportSnapshotLocalDaoProvider),
    remoteDatasource: ref.watch(salesReportRemoteDatasourceProvider),
  );
});

typedef SalesReportOnlineCheck = Future<bool> Function();

final salesReportOnlineCheckProvider = Provider<SalesReportOnlineCheck>((ref) {
  return () => ref.read(connectivityServiceProvider).isOnline;
});

final salesReportClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});
