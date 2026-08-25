import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../inventory/application/purchase_local_provider.dart';
import '../data/datasources/purchase_product_dependency_local_dao.dart';
import '../data/datasources/purchases_sync_remote_datasource.dart';
import 'local_sync_outbox_providers.dart';
import 'purchase_product_dependency_resolver.dart';
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
    dependencyResolver: ref.watch(purchaseProductDependencyResolverProvider),
  );
});

final purchaseProductDependencyLocalDaoProvider =
    Provider<PurchaseProductDependencyLocalDao>((ref) {
  return PurchaseProductDependencyLocalDao(ref.watch(appDatabaseProvider));
});

final purchaseProductDependencyResolverProvider =
    Provider<PurchaseProductDependencyResolver>((ref) {
  return PurchaseProductDependencyResolver(
    ref.watch(purchaseProductDependencyLocalDaoProvider),
  );
});
