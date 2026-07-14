import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../inventory/application/purchase_local_provider.dart';
import '../data/datasources/purchases_sync_remote_datasource.dart';
import 'local_sync_outbox_providers.dart';
import 'purchases_sync_upload_service.dart';

final purchasesSyncRemoteDataSourceProvider =
    Provider<PurchasesSyncRemoteDataSource>((ref) {
  final client = ref.watch(supabaseClientProvider);

  return PurchasesSyncRemoteDataSource(client);
});

final purchasesSyncUploadServiceProvider =
    Provider<PurchasesSyncUploadService>((ref) {
  return PurchasesSyncUploadService(
    outboxService: ref.watch(localSyncOutboxServiceProvider),
    remoteDataSource: ref.watch(purchasesSyncRemoteDataSourceProvider),
    purchaseLocalDao: ref.watch(purchaseLocalDaoProvider),
  );
});
