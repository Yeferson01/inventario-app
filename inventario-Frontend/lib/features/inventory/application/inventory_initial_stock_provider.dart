import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../sync/application/local_sync_outbox_providers.dart';
import '../data/datasources/inventory_movement_local_dao.dart';
import 'inventory_initial_stock_service.dart';

final inventoryMovementLocalDaoProvider =
    Provider<InventoryMovementLocalDao>((ref) {
  final db = ref.watch(appDatabaseProvider);

  return InventoryMovementLocalDao(db);
});

final inventoryInitialStockServiceProvider =
    Provider<InventoryInitialStockService>((ref) {
  return InventoryInitialStockService(
    localDao: ref.watch(inventoryMovementLocalDaoProvider),
    outboxService: ref.watch(localSyncOutboxServiceProvider),
  );
});
