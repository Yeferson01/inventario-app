import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/catalog_sync_remote_datasource.dart';
import '../data/datasources/local_sync_outbox_dao.dart';
import 'catalog_sync_upload_service.dart';
import 'local_sync_outbox_service.dart';

final localSyncOutboxDaoProvider = Provider<LocalSyncOutboxDao>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return LocalSyncOutboxDao(database);
});

final localSyncOutboxServiceProvider = Provider<LocalSyncOutboxService>((ref) {
  final dao = ref.watch(localSyncOutboxDaoProvider);
  return LocalSyncOutboxService(dao);
});

final catalogSyncRemoteDataSourceProvider =
    Provider<CatalogSyncRemoteDataSource>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return CatalogSyncRemoteDataSource(supabase);
});

final catalogSyncUploadServiceProvider =
    Provider<CatalogSyncUploadService>((ref) {
  return CatalogSyncUploadService(
    outboxService: ref.watch(localSyncOutboxServiceProvider),
    remoteDataSource: ref.watch(catalogSyncRemoteDataSourceProvider),
  );
});
