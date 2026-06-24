import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../data/datasources/catalog_local_dao.dart';
import '../data/repositories/catalog_local_repository.dart';

final catalogLocalDaoProvider = Provider<CatalogLocalDao>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return CatalogLocalDao(database);
});

final catalogLocalRepositoryProvider = Provider<CatalogLocalRepository>((ref) {
  final dao = ref.watch(catalogLocalDaoProvider);
  return CatalogLocalRepository(dao);
});
