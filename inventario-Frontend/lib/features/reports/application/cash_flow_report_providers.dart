import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasources/cash_flow_report_remote_datasource.dart';
import 'cash_flow_report_service.dart';
import 'sales_report_providers.dart';
import '../../sync/application/operational_bootstrap_providers.dart';
import '../../../core/supabase/supabase_client_provider.dart';

final cashFlowReportRemoteDatasourceProvider =
    Provider<CashFlowReportRemoteDatasource>((ref) =>
        CashFlowReportRemoteDatasource(ref.watch(supabaseClientProvider)));

final cashFlowReportServiceProvider =
    Provider<CashFlowReportService>((ref) => CashFlowReportService(
          authenticatedProfileId: () =>
              ref.read(currentSupabaseUserProvider)?.id,
          authorizationDao:
              ref.watch(authorizedOperationalContextLocalDaoProvider),
          snapshotDao: ref.watch(reportSnapshotLocalDaoProvider),
          remoteDatasource: ref.watch(cashFlowReportRemoteDatasourceProvider),
        ));
