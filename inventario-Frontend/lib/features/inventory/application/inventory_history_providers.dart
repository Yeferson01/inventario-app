import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/inventory_history_local_dao.dart';
import '../data/datasources/inventory_history_remote_datasource.dart';
import 'inventory_history_service.dart';

final inventoryHistoryLocalDaoProvider =
    Provider<InventoryHistoryLocalDao>((ref) {
  return InventoryHistoryLocalDao(ref.watch(appDatabaseProvider));
});

final inventoryHistoryRemoteDatasourceProvider =
    Provider<InventoryHistoryRemoteDatasource>((ref) {
  return InventoryHistoryRemoteDatasource(ref.watch(supabaseClientProvider));
});

final inventoryHistoryServiceProvider =
    Provider<InventoryHistoryService>((ref) {
  return InventoryHistoryService(
    localDao: ref.watch(inventoryHistoryLocalDaoProvider),
    remoteDatasource: ref.watch(inventoryHistoryRemoteDatasourceProvider),
    isOnline: () => ref.read(connectivityServiceProvider).isOnline,
  );
});
