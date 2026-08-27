import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/catalog_local_dao.dart';
import '../data/datasources/catalog_remote_datasource.dart';
import '../data/repositories/catalog_local_repository.dart';
import 'catalog_readiness.dart';
import 'catalog_sync_service.dart';
import 'catalog_barcode_lookup_service.dart';
import 'initial_catalog_bootstrap_coordinator.dart';

final catalogLocalDaoProvider = Provider<CatalogLocalDao>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return CatalogLocalDao(database);
});

final catalogLocalRepositoryProvider = Provider<CatalogLocalRepository>((ref) {
  final dao = ref.watch(catalogLocalDaoProvider);
  return CatalogLocalRepository(dao);
});

final catalogRemoteDataSourceProvider =
    Provider<CatalogRemoteDataSource>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return CatalogRemoteDataSource(supabase);
});

final catalogSyncServiceProvider = Provider<CatalogSyncService>((ref) {
  return CatalogSyncService(
    remoteDataSource: ref.watch(catalogRemoteDataSourceProvider),
    localRepository: ref.watch(catalogLocalRepositoryProvider),
  );
});

final catalogReadinessProvider =
    StreamProvider.family<CatalogReadiness, String>((ref, businessId) {
  return ref
      .watch(catalogLocalRepositoryProvider)
      .watchCatalogSyncState(businessId)
      .map(CatalogReadiness.fromSyncState);
});

final initialCatalogBootstrapCoordinatorProvider =
    Provider<InitialCatalogBootstrapCoordinator>((ref) {
  final repository = ref.watch(catalogLocalRepositoryProvider);
  final syncService = ref.watch(catalogSyncServiceProvider);
  return InitialCatalogBootstrapCoordinator(
    readReadiness: (businessId) async => CatalogReadiness.fromSyncState(
      await repository.getCatalogSyncState(businessId),
    ),
    pullCatalog: ({required businessId}) => syncService.pullCatalogDelta(
      businessId: businessId,
    ),
  );
});

final catalogBarcodeLookupServiceProvider =
    Provider<CatalogBarcodeLookupService>((ref) {
  final repository = ref.watch(catalogLocalRepositoryProvider);

  return CatalogBarcodeLookupService(
    lookupByBarcode: repository.lookupByBarcode,
  );
});
