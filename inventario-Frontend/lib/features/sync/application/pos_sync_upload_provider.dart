import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/pos_sync_remote_datasource.dart';
import 'local_sync_outbox_providers.dart';
import 'pos_sync_upload_service.dart';
import '../../sales/application/pos_local_sale_provider.dart';
import '../../cash/application/cash_session_local_provider.dart';

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
  );
});
