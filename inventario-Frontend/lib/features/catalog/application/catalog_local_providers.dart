import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/catalog_local_dao.dart';
import '../data/datasources/catalog_remote_datasource.dart';
import '../data/repositories/catalog_local_repository.dart';
import 'catalog_sync_service.dart';
import 'catalog_barcode_lookup_service.dart';

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

final catalogBarcodeLookupServiceProvider =
    Provider<CatalogBarcodeLookupService>((ref) {
  final repository = ref.watch(catalogLocalRepositoryProvider);

  return CatalogBarcodeLookupService(
    lookupByBarcode: repository.lookupByBarcode,
  );
});
