import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../sync/application/operational_bootstrap_providers.dart';
import '../data/datasources/profitability_report_remote_datasource.dart';
import 'profitability_report_service.dart';
import 'sales_report_providers.dart';

final profitabilityReportRemoteDatasourceProvider =
    Provider<ProfitabilityReportRemoteDatasource>((ref) {
  return ProfitabilityReportRemoteDatasource(ref.watch(supabaseClientProvider));
});

final profitabilityReportServiceProvider =
    Provider<ProfitabilityReportService>((ref) {
  return ProfitabilityReportService(
    authenticatedProfileId: () => ref.read(currentSupabaseUserProvider)?.id,
    authorizationDao: ref.watch(authorizedOperationalContextLocalDaoProvider),
    snapshotDao: ref.watch(reportSnapshotLocalDaoProvider),
    remoteDatasource: ref.watch(profitabilityReportRemoteDatasourceProvider),
  );
});
