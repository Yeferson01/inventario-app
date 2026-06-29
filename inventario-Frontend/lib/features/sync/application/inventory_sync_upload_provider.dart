import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/inventory_sync_remote_datasource.dart';
import 'inventory_sync_upload_service.dart';
import 'local_sync_outbox_providers.dart';

final inventorySyncRemoteDataSourceProvider =
    Provider<InventorySyncRemoteDataSource>((ref) {
  final client = ref.watch(supabaseClientProvider);

  return InventorySyncRemoteDataSource(client);
});

final inventorySyncUploadServiceProvider =
    Provider<InventorySyncUploadService>((ref) {
  return InventorySyncUploadService(
    outboxService: ref.watch(localSyncOutboxServiceProvider),
    remoteDataSource: ref.watch(inventorySyncRemoteDataSourceProvider),
  );
});
