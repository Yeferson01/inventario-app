import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../catalog/application/catalog_local_providers.dart';
import '../data/datasources/catalog_sync_remote_datasource.dart';
import '../data/datasources/local_sync_outbox_dao.dart';
import '../data/datasources/runtime_setup_remote_datasource.dart';
import 'app_runtime_context_store.dart';
import 'app_runtime_setup_service.dart';
import 'app_sync_coordinator_service.dart';
import 'catalog_sync_upload_service.dart';
import 'local_sync_outbox_service.dart';
import 'scheduled_sync_policy.dart';
import 'scheduled_sync_service.dart';
import 'scheduled_sync_state_store.dart';

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

final scheduledSyncPolicyProvider = Provider<ScheduledSyncPolicy>((ref) {
  return const ScheduledSyncPolicy();
});

final scheduledSyncStateStoreProvider =
    Provider<ScheduledSyncStateStore>((ref) {
  return ScheduledSyncStateStore();
});

final scheduledSyncServiceProvider = Provider<ScheduledSyncService>((ref) {
  return ScheduledSyncService(
    catalogUploadService: ref.watch(catalogSyncUploadServiceProvider),
    catalogPullService: ref.watch(catalogSyncServiceProvider),
    policy: ref.watch(scheduledSyncPolicyProvider),
    stateStore: ref.watch(scheduledSyncStateStoreProvider),
  );
});

final runtimeSetupRemoteDataSourceProvider =
    Provider<RuntimeSetupRemoteDataSource>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return RuntimeSetupRemoteDataSource(supabase);
});

final appRuntimeContextStoreProvider = Provider<AppRuntimeContextStore>((ref) {
  return AppRuntimeContextStore();
});

final appRuntimeSetupServiceProvider = Provider<AppRuntimeSetupService>((ref) {
  return AppRuntimeSetupService(
    remoteDataSource: ref.watch(runtimeSetupRemoteDataSourceProvider),
    contextStore: ref.watch(appRuntimeContextStoreProvider),
  );
});

final appSyncCoordinatorServiceProvider =
    Provider<AppSyncCoordinatorService>((ref) {
  return AppSyncCoordinatorService(
    runtimeSetupService: ref.watch(appRuntimeSetupServiceProvider),
    scheduledSyncService: ref.watch(scheduledSyncServiceProvider),
  );
});
